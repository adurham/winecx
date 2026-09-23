/*
 * MACDRV Cocoa window declarations
 *
 * Copyright 2011, 2012, 2013 Ken Thomases for CodeWeavers Inc.
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

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>


@class WineEventQueue;


/* OPT-IN: carry a frame-rate cadence to the compositor.
 *
 * The panel follows PRESENTATION CADENCE, not a declared range: a CADisplayLink
 * carrying a CAFrameRateRange does nothing on this external panel, while a
 * CAMetalDisplayLink whose callback actually presents a drawable moves it
 * (measured, 2026-09-23).  So this creates a 1x1 non-opaque carrier CAMetalLayer
 * as a sublayer of a WineMetalView's backing layer, with its own
 * CAMetalDisplayLink whose callback presents the carrier's own drawable, and
 * sets preferredFrameRateRange on it to the display's own variable-refresh range
 * (read at runtime from the IORegistry).  The layer D3DMetal presents through is
 * never touched.  Exposed in the header so d3dmetal_objc.m can call it from
 * -[WineMetalLayer nextDrawable], which is the one place that reliably
 * identifies "this window is presenting through a D3DMetal CAMetalLayer".
 *
 * Set WHISKY_DECLARE_FRAME_RATE_RANGE=1 to enable and
 * WHISKY_DECLARE_FRAME_RATE_PREFERRED=<hz> for the game's cadence.  Default off:
 * with the variable unset this returns immediately, allocating nothing, and the
 * driver behaves exactly as before.  See the implementation in cocoa_window.m
 * for the measurements behind the shape and for the range-discovery path. */
extern void macdrv_declare_frame_rate_range(NSView* view);


@interface WineWindow : NSPanel <NSWindowDelegate>
{
    BOOL disabled;
    BOOL noForeground;
    BOOL preventsAppActivation;
    BOOL floating;
    BOOL resizable;
    BOOL maximized;
    BOOL fullscreen;
    BOOL pendingMinimize;
    BOOL pendingOrderOut;
    BOOL savedVisibleState;
    BOOL drawnSinceShown;
    BOOL closing;
    WineWindow* latentParentWindow;
    NSMutableArray* latentChildWindows;

    void* hwnd;
    WineEventQueue* queue;

    CGDirectDisplayID _lastDisplayID;
    NSTimeInterval _lastDisplayTime;

    NSRect wineFrame;
    NSRect roundedWineFrame;

    BOOL shapeChangedSinceLastDraw;

    BOOL usePerPixelAlpha;

    NSUInteger lastModifierFlags;

    NSRect frameAtResizeStart;
    BOOL resizingFromLeft, resizingFromTop;

    void* himc;
    BOOL commandDone;

    NSSize savedContentMinSize;
    NSSize savedContentMaxSize;

    BOOL enteringFullScreen;
    BOOL exitingFullScreen;
    NSRect nonFullscreenFrame;
    NSTimeInterval enteredFullScreenTime;

    int draggingPhase;
    NSPoint dragStartPosition;
    NSPoint dragWindowStartPosition;

    NSTimeInterval lastDockIconSnapshot;

    BOOL allowKeyRepeats;

    BOOL ignore_windowDeminiaturize;
    BOOL ignore_windowResize;
    BOOL fakingClose;

    CAShapeLayer* contentViewMaskLayer;
}

@property (retain, readonly, nonatomic) WineEventQueue* queue;
@property (readonly, nonatomic) BOOL disabled;
@property (readonly, nonatomic) BOOL noForeground;
@property (readonly, nonatomic) BOOL preventsAppActivation;
@property (readonly, nonatomic) BOOL floating;
@property (readonly, getter=isFullscreen, nonatomic) BOOL fullscreen;
@property (readonly, getter=isFakingClose, nonatomic) BOOL fakingClose;
@property (readonly, nonatomic) NSRect wine_fractionalFrame;

/* Whether this window, when ordered in and not miniaturized, would appear to
   the user on-screen. That means it has a non-zero size and is not empty-
   shaped, or has a child window that meets those criteria. */
@property (readonly, nonatomic) BOOL presentsVisibleContent;

    - (NSInteger) minimumLevelForActive:(BOOL)active;
    - (void) updateFullscreen;

    - (void) postKeyEvent:(NSEvent *)theEvent;
    - (void) postBroughtForwardEvent;

    - (WineWindow*) ancestorWineWindow;

    - (void) updateForCursorClipping;

    - (void) setRetinaMode:(BOOL)mode;

@end
