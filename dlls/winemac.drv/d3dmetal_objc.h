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

#import <QuartzCore/QuartzCore.h>

@interface WineMetalLayer : CAMetalLayer

/* The most recent drawable handed out by -nextDrawable.  When the engine is in
 * broker mode (WHISKY_DECLARE_FRAME_RATE_RANGE=1) this layer is OFFSCREEN and
 * is not the layer a CAMetalDisplayLink owns, so nothing in QuartzCore minds
 * that we keep a reference; the broker blits -[drawable texture] into the
 * link's drawable.  Weakly retained: it is replaced on every acquire. */
- (id<CAMetalDrawable>) wineLastAcquiredDrawable;

@end

/* Implemented by WineMetalView in cocoa_window.m.  Returns the view that
 * carries the D3DMetal client_surface association and whose layer is the
 * PRESENTING one: the receiver itself in the normal arrangement, or the paired
 * on-screen sibling when the receiver is the broker's offscreen surface view.
 * Never nil. */
@interface NSView (WinePresentationView)
- (NSView*) winePresentationView;
@end

/* Explicit owner link between a backing CAMetalLayer and the WineMetalView that
 * created it.  Needed because AppKit only sets a backing layer's -delegate for
 * views that live in a window: the broker's OFFSCREEN D3DMetal surface is
 * outside the view hierarchy, so -[WineMetalLayer nextDrawable] cannot rely on
 * -delegate to find its view.  Stored with OBJC_ASSOCIATION_ASSIGN -- the view
 * owns the layer, so a retain here would be a cycle. */
void wine_metal_layer_set_owner(CAMetalLayer* layer, NSView* view);
NSView* wine_metal_layer_owner(CAMetalLayer* layer);

#endif
