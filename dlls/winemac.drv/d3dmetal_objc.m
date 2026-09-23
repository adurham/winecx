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

#include "macdrv_cocoa.h"
#import "cocoa_app.h"
#import "cocoa_event.h"
#import "cocoa_window.h"
#import "d3dmetal_objc.h"

#pragma GCC diagnostic ignored "-Wdeclaration-after-statement"


@implementation WineMetalLayer

    /* Extend [CAMetalLayer nextDrawable] so client_surface_present() can be
     * called for the corresponding client_surface.
     */
    - (id<CAMetalDrawable>) nextDrawable
    {
        /* CAMetalLayer's delegate is the WineMetalView that contains it (seems like that's always true
         * for an NSView backing layer).
         * That WineMetalView's parent is the client_surface->cocoa_view WineContentView, it has the
         * client_surface set on it as an associated object.
         */
        if ([self.delegate isKindOfClass:NSClassFromString(@"WineMetalView")])
        {
            NSView* view = (NSView *)self.delegate;
            if ([view.superview isKindOfClass:NSClassFromString(@"WineContentView")] &&
                [view.window    isKindOfClass:NSClassFromString(@"WineWindow")])
            {
                void *client_surface = macdrv_get_view_d3dmetal_client_surface((macdrv_view)view.superview);
                if (client_surface)
                {
                    macdrv_event* event;
                    event = macdrv_create_event(CLIENT_SURFACE_PRESENTED, (WineWindow*)view.window);
                    event->client_surface_presented.client_surface = client_surface;

                    WineEventQueue *queue = [(WineWindow*)view.window queue];
                    [queue postEvent:event];
                    macdrv_release_event(event);
                }

                /* OPT-IN WHISKY_DECLARE_FRAME_RATE_RANGE=1: make the compositor
                 * follow the cadence this window's content is produced at, by
                 * arming a 1x1 carrier CAMetalLayer (a sublayer of this view's
                 * layer) with a CAMetalDisplayLink that presents the carrier's
                 * own drawable.  The panel follows presentation cadence, not a
                 * declaration, which is why the old CADisplayLink approach did
                 * nothing here.  This is the one place that reliably identifies
                 * "a window presenting D3DMetal content"; the function returns
                 * immediately when the variable is unset.  It never touches this
                 * layer or nextDrawable.
                 *
                 * This call is also the GAME'S PRESENT MOMENT: it bumps the
                 * carrier's atomic present counter, which is what the carrier's
                 * CAMetalDisplayLink callback gates on, so the carrier presents
                 * only when the game has produced a new frame instead of
                 * free-running at the display's rate. */
                macdrv_declare_frame_rate_range(view);
            }
        }

        return [super nextDrawable];
    }

@end

#endif
