/*
 * Mac graphics driver hooks used by D3DMetal (part of the Apple Game Porting Toolkit)
 *
 * Copyright 2025 Brendan Shanks for CodeWeavers, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#if defined(__x86_64__)

#include "config.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#include "macdrv_cocoa.h"
#import "cocoa_app.h"
#import "cocoa_event.h"
#import "cocoa_window.h"
#import "d3dmetal_objc.h"

#pragma GCC diagnostic ignored "-Wdeclaration-after-statement"

/* Key for the layer -> owning view link; see the declarations in d3dmetal_objc.h. */
static char wine_metal_layer_owner_key;

/* TEMPORARY DIAGNOSTIC (remove once the broker path is proven in the rig).
   NSLog from this driver has been silent in rig runs, so every decision in
   -nextDrawable is recorded here instead.  Off unless WHISKY_BROKER_DIAG=1. */
static void wine_broker_diag(const char* fmt, ...)
{
    static int enabled = -1;
    FILE* f;
    va_list ap;

    if (enabled < 0)
        enabled = getenv("WHISKY_BROKER_DIAG") ? 1 : 0;
    if (!enabled)
        return;

    f = fopen("/tmp/broker-diag.log", "a");
    if (!f)
        return;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}


@implementation WineMetalLayer
{
    id<CAMetalDrawable> _last_acquired;     /* not retained: see below */
}

    void wine_metal_layer_set_owner(CAMetalLayer* layer, NSView* view)
    {
        objc_setAssociatedObject(layer, &wine_metal_layer_owner_key, view,
                                 OBJC_ASSOCIATION_ASSIGN);
    }

    NSView* wine_metal_layer_owner(CAMetalLayer* layer)
    {
        return (NSView*)objc_getAssociatedObject(layer, &wine_metal_layer_owner_key);
    }

    /* The last drawable -nextDrawable handed out.  Deliberately NOT retained:
       D3DMetal owns the drawable for the duration of its frame and presents it
       itself, and holding a strong reference here would keep a pool slot
       (maximumDrawableCount is 3) out of circulation for exactly the window in
       which the broker wants to blit from it.  The pointer is read by the
       broker on the main thread; it can go stale only if D3DMetal releases the
       drawable, and every use is guarded against a nil/dead texture by the
       layer identity check in the broker. */
    - (id<CAMetalDrawable>) wineLastAcquiredDrawable
    {
        return _last_acquired;
    }

    /* Extend [CAMetalLayer nextDrawable] so client_surface_present() can be
     * called for the corresponding client_surface.
     */
    - (void) dealloc
    {
        if (_last_acquired) [_last_acquired release];
        [super dealloc];
    }

    - (id<CAMetalDrawable>) nextDrawable
    {
        /* CAMetalLayer's delegate is the WineMetalView that contains it (seems like that's always true
         * for an NSView backing layer).
         * That WineMetalView's parent is the client_surface->cocoa_view WineContentView, it has the
         * client_surface set on it as an associated object.
         */
        /* Resolve the view this layer belongs to.  -delegate is the normal
           route for a layer-backed view inside a window, but the broker's
           OFFSCREEN D3DMetal surface is not in the view hierarchy and AppKit
           leaves its backing layer's delegate nil -- so the explicit owner link
           set in -makeBackingLayer is the reliable route, with -delegate as the
           fallback for every other case. */
        NSView* layer_view = wine_metal_layer_owner(self);
        if (!layer_view && [self.delegate isKindOfClass:[NSView class]])
            layer_view = (NSView*)self.delegate;

        NSView* host = layer_view;
        if ([host respondsToSelector:@selector(winePresentationView)])
            host = [host winePresentationView];

        {
            static int logged = 0;
            if (logged < 6)
            {
                logged++;
                wine_broker_diag("nextDrawable: layer=%p owner=%s delegate=%s layer_view=%s "
                                 "host=%s host.superview=%s host.window=%s",
                                 (void*)self,
                                 layer_view ? object_getClassName(layer_view) : "nil",
                                 self.delegate ? object_getClassName(self.delegate) : "nil",
                                 layer_view ? object_getClassName(layer_view) : "nil",
                                 host ? object_getClassName(host) : "nil",
                                 (host && host.superview) ? object_getClassName(host.superview) : "nil",
                                 (host && host.window) ? object_getClassName(host.window) : "nil");
            }
        }

        if ([layer_view isKindOfClass:NSClassFromString(@"WineMetalView")] &&
            [host.superview isKindOfClass:NSClassFromString(@"WineContentView")] &&
            [host.window    isKindOfClass:NSClassFromString(@"WineWindow")])
        {
            void *client_surface = macdrv_get_view_d3dmetal_client_surface((macdrv_view)host.superview);
            if (client_surface)
            {
                macdrv_event* event;
                event = macdrv_create_event(CLIENT_SURFACE_PRESENTED, (WineWindow*)host.window);
                event->client_surface_presented.client_surface = client_surface;

                WineEventQueue *queue = [(WineWindow*)host.window queue];
                [queue postEvent:event];
                macdrv_release_event(event);
            }

            /* OPT-IN WHISKY_DECLARE_FRAME_RATE_RANGE=1: make the compositor
             * follow the cadence this window's content is produced at.  In
             * broker mode that is a CAMetalDisplayLink bound to the PRESENTING
             * layer (the on-screen view's backing layer), whose callback blits
             * this layer's latest drawable into its own and presents it on every
             * tick -- never skipping one, because skipping exhausts the link's
             * three-drawable pool and freezes it.  The panel follows
             * presentation cadence, not a declared range, which is why the old
             * CADisplayLink approach did nothing here.  This call is the one
             * place that reliably identifies "a window presenting D3DMetal
             * content"; the function returns immediately when the variable is
             * unset.
             *
             * This call is also the GAME'S PRESENT MOMENT: it bumps the
             * broker's atomic present counter, used for diagnostics. */
            macdrv_declare_frame_rate_range(layer_view);
        }

        id<CAMetalDrawable> drawable = [super nextDrawable];

        /* Remember what we just handed out.  Under broker mode
           (WHISKY_DECLARE_FRAME_RATE_RANGE=1) D3DMetal renders into THIS layer,
           which is offscreen, and the link owns a DIFFERENT, visible layer; the
           broker blits this drawable's texture into the link's drawable.

           RETAINED FOR EXACTLY ONE FRAME, then released on the next acquire.
           That is not tidiness: the broker's display-link callback runs on its
           own thread (wine's main run loop stops being serviced after startup,
           so a link added there never ticks), and it reads this pointer from
           there.  A borrowed reference could be deallocated between the read and
           the blit.  Holding it for one frame keeps the slot out of the pool for
           only that long, so D3DMetal still gets its frames in flight. */
        if (_last_acquired) [_last_acquired release];
        _last_acquired = [drawable retain];

        return drawable;
    }

@end

#endif
