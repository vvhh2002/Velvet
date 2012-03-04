//
//  VELEventManager.m
//  Velvet
//
//  Created by Justin Spahr-Summers on 03.01.12.
//  Copyright (c) 2012 Bitswift. All rights reserved.
//

#import "VELEventManager.h"
#import "EXTScope.h"
#import "NSWindow+EventHandlingAdditions.h"
#import "VELEventRecognizer.h"
#import "VELEventRecognizerPrivate.h"
#import "VELEventRecognizerProtected.h"
#import "VELHostView.h"
#import "VELView.h"

@interface VELEventManager ()
/**
 * Any Velvet-hosted responder currently handling a continuous gesture event.
 */
@property (nonatomic, strong) id<VELBridgedView> currentGestureResponder;

/**
 * The Velvet-hosted responder that handled the last mouse down or mouse drag
 * event.
 */
@property (nonatomic, strong) id<VELBridgedView> currentMouseDownResponder;

/**
 * The Velvet-hosted responder that received the last handled mouse tracking
 * event.
 */
@property (nonatomic, weak) id lastMouseTrackingResponder;

/**
 * Whether an event is currently in the process of being handled in
 * <handleVelvetEvent:>.
 *
 * This is used to avoid infinite recursion, as apparently some `NSResponder`
 * messages eventually jump back up to event monitors.
 */
@property (nonatomic, assign, getter = isHandlingEvent) BOOL handlingEvent;

/**
 * Tracks event recognizers that have already received the current event via
 * <dispatchEvent:toEventRecognizersForView:> or
 * <dispatchEvent:toEventRecognizersForLayer:>, to avoid double dispatch.
 *
 * This is `nil` by default. It should be set to an empty set before dispatching
 * an event, and set back to `nil` afterward.
 */
@property (nonatomic, strong) NSMutableSet *eventRecognizersReceivingEvent;

/**
 * Turns an event into an `NSResponder` message, and attempts to send it to the
 * given responder. If neither `responder` nor the rest of its responder chain
 * implement the corresponding action, `NO` is returned.
 *
 * @param event The event to dispatch.
 * @param view The <VELBridgedView> which should receive the message
 * corresponding to `event`. This view must be an `NSResponder`.
 */
- (BOOL)dispatchEvent:(NSEvent *)event toBridgedView:(id<VELBridgedView>)view;

/**
 * Dispatches the given event to all of the event recognizers that are directly
 * or indirectly attached to the given view. Returns whether the event should
 * still be passed to the view.
 *
 * In other words, this returns `NO` if one or more of the event recognizers has
 * <[VELEventRecognizer delaysEventDelivery]> set to `YES`.
 *
 * This method will dispatch events to the farthest ancestors first, then walk
 * down the tree, eventually ending at `view`. If the given view has
 * a <[VELBridgedView hostView]> that is not an ancestor, the host view's event
 * recognizers will receive `event` before those of `view`.
 *
 * @param event The event to dispatch.
 * @param view A view that may have attached event recognizers, or may have
 * superviews or a <[VELBridgedView hostView]> with attached event recognizers.
 */
- (BOOL)dispatchEvent:(NSEvent *)event toEventRecognizersForView:(id<VELBridgedView>)view;

/**
 * Dispatches the given event to all of the event recognizers that are directly
 * or indirectly attached to the given layer. Returns whether the event should
 * still be passed to the corresponding view.
 *
 * In other words, this returns `NO` if one or more of the event recognizers has
 * <[VELEventRecognizer delaysEventDelivery]> set to `YES`.
 *
 * This method will dispatch events to the farthest ancestors first, then walk
 * down the tree, eventually ending at `layer`.
 *
 * @param event The event to dispatch.
 * @param layer A layer that may have attached event recognizers, or may have
 * superlayers with attached event recognizers.
 */
- (BOOL)dispatchEvent:(NSEvent *)event toEventRecognizersForLayer:(CALayer *)layer;

/**
 * Attempts to dispatch the given mouse tracking event (`NSMouseEntered`,
 * `NSMouseMoved` or `NSMouseExited`) to Velvet. Regardless of whether the event
 * was handled by Velvet, it should _not_ be discarded.
 *
 * This may translate into a different message than suggested by the exact event
 * type, or several events, in Velvet. For instance, an `NSMouseMoved` event may
 * trigger `mouseExited:` and `mouseEntered:` events on Velvet hosted views.
 *
 * @param event The event that occurred.
 */
- (void)handleMouseTrackingEvent:(NSEvent *)event;

/**
 * If the given event doesn't have an associated window, give it one, and update
 * its location accordingly.
 *
 * This currently just uses the application's `keyWindow` as the receiver, no
 * matter where the event is.
 *
 * @param event The event that may have a `nil` window.
 */
- (NSEvent *)mouseEventByAddingWindow:(NSEvent *)event;

/**
 * Attempts to dispatch the given event to Velvet via the appropriate window.
 * Returns whether the event was handled by Velvet (and thus should be
 * disregarded by AppKit).
 *
 * @param event The event that occurred.
 */
- (BOOL)handleVelvetEvent:(NSEvent *)event;
@end

@implementation VELEventManager

#pragma mark Properties

@synthesize currentGestureResponder = m_currentGestureResponder;
@synthesize currentMouseDownResponder = m_currentMouseDownResponder;
@synthesize handlingEvent = m_handlingEvent;
@synthesize lastMouseTrackingResponder = m_lastMouseTrackingResponder;
@synthesize eventRecognizersReceivingEvent = m_eventRecognizersReceivingEvent;

#pragma mark Lifecycle

+ (void)load {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSAnyEventMask handler:^ id (NSEvent *event){
        if ([[self defaultManager] handleVelvetEvent:event])
            return nil;
        else
            return event;
    }];
}

+ (id)defaultManager {
    static id singleton = nil;
    static dispatch_once_t pred;

    dispatch_once(&pred, ^{
        singleton = [[self alloc] init];
    });

    return singleton;
}

#pragma mark Event handling

- (BOOL)dispatchEvent:(NSEvent *)event toBridgedView:(id<VELBridgedView>)view; {
    NSAssert([view isKindOfClass:[NSResponder class]], @"View %@ is not an NSResponder", view);

    SEL action = NULL;

    switch ([event type]) {
        case NSLeftMouseDown:
            action = @selector(mouseDown:);
            break;

        case NSLeftMouseUp:
            action = @selector(mouseUp:);
            break;

        case NSRightMouseDown:
            action = @selector(rightMouseDown:);
            break;

        case NSRightMouseUp:
            action = @selector(rightMouseUp:);
            break;

        case NSMouseMoved:
            action = @selector(mouseMoved:);
            break;

        case NSLeftMouseDragged:
            action = @selector(mouseDragged:);
            break;

        case NSRightMouseDragged:
            action = @selector(rightMouseDragged:);
            break;

        case NSMouseEntered:
            action = @selector(mouseEntered:);
            break;

        case NSMouseExited:
            action = @selector(mouseExited:);
            break;

        case NSOtherMouseDown:
            action = @selector(otherMouseDown:);
            break;

        case NSOtherMouseUp:
            action = @selector(otherMouseUp:);
            break;

        case NSOtherMouseDragged:
            action = @selector(otherMouseDragged:);
            break;
        
        case NSScrollWheel:
            action = @selector(scrollWheel:);
            break;

        case NSEventTypeMagnify:
            action = @selector(magnifyWithEvent:);
            break;

        case NSEventTypeSwipe:
            action = @selector(swipeWithEvent:);
            break;

        case NSEventTypeRotate:
            action = @selector(rotateWithEvent:);
            break;

        case NSEventTypeBeginGesture:
            action = @selector(beginGestureWithEvent:);
            break;

        case NSEventTypeEndGesture:
            action = @selector(endGestureWithEvent:);
            break;

        default:
            NSLog(@"*** Unrecognized event: %@", event);
    }

    if (action)
        return [(id)view tryToPerform:action with:event];
    else
        return NO;
}

- (BOOL)dispatchEvent:(NSEvent *)event toEventRecognizersForView:(id<VELBridgedView>)view; {
    NSParameterAssert(event != nil);

    if (!view)
        return YES;

    // dispatch to the host view first, and rely on
    // eventRecognizersReceivingEvent to deduplicate our events for any common
    // recognizers
    return [self dispatchEvent:event toEventRecognizersForView:view.hostView] && [self dispatchEvent:event toEventRecognizersForLayer:view.layer];
}

- (BOOL)dispatchEvent:(NSEvent *)event toEventRecognizersForLayer:(CALayer *)layer; {
    NSParameterAssert(event != nil);

    if (!layer)
        return YES;

    BOOL dispatchToView = [self dispatchEvent:event toEventRecognizersForLayer:layer.superlayer];

    NSArray *attachedRecognizers = [VELEventRecognizer eventRecognizersForLayer:layer];
    for (VELEventRecognizer *recognizer in attachedRecognizers) {
        if ([self.eventRecognizersReceivingEvent containsObject:recognizer])
            continue;

        if ([recognizer.eventsToIgnore containsObject:event]) {
            [recognizer.eventsToIgnore removeObject:event];
            continue;
        }

        if (!recognizer.enabled)
            continue;

        if (recognizer.delaysEventDelivery)
            dispatchToView = NO;

        [recognizer handleEvent:event];
        [self.eventRecognizersReceivingEvent addObject:recognizer];
    }

    return dispatchToView;
}

- (BOOL)handleVelvetEvent:(NSEvent *)event; {
    if (self.handlingEvent) {
        // don't recurse -- see the description for this property
        return NO;
    }

    self.handlingEvent = YES;
    @onExit {
        self.handlingEvent = NO;
    };

    __block id respondingView = nil;

    // whether the event was received by an event recognizer and delayed from
    // delivery
    __block BOOL eventAbsorbedByRecognizer = NO;

    /**
     * Returns whether we should handle the event dispatch for `respondingView`.
     * If this returns `NO`, the event should be returned to AppKit for
     * processing.
     */
    BOOL (^velvetShouldHandleRespondingView)(void) = ^ BOOL {
        return respondingView && ![respondingView isKindOfClass:[NSView class]];
    };

    /**
     * Attempts to dispatch the event to `respondingView`. Returns whether the
     * event should be considered handled.
     */
    BOOL (^dispatchToView)(void) = ^{
        if (![respondingView conformsToProtocol:@protocol(VELBridgedView)])
            return NO;

        {
            self.eventRecognizersReceivingEvent = [NSMutableSet set];
            @onExit {
                self.eventRecognizersReceivingEvent = nil;
            };

            if (![self dispatchEvent:event toEventRecognizersForView:respondingView]) {
                eventAbsorbedByRecognizer = YES;
                return YES;
            }
        }

        if (!velvetShouldHandleRespondingView())
            return NO;

        return [self dispatchEvent:event toBridgedView:respondingView];
    };

    switch ([event type]) {
        case NSLeftMouseDown:
        case NSRightMouseDown:
        case NSOtherMouseDown:
            respondingView = [event.window bridgedHitTest:[event locationInWindow]];
            if (!dispatchToView()) {
                self.currentMouseDownResponder = nil;
                return NO;
            }

            if (!eventAbsorbedByRecognizer) {
                NSAssert([respondingView isKindOfClass:[NSResponder class]], @"View %@ is not an NSResponder", respondingView);

                // make the view that received the click the first responder for
                // that window
                [event.window makeFirstResponder:(id)respondingView];
            }

            self.currentMouseDownResponder = respondingView;
            return YES;

        case NSScrollWheel:
        case NSEventTypeMagnify:
        case NSEventTypeSwipe:
        case NSEventTypeRotate:
            respondingView = [event.window bridgedHitTest:[event locationInWindow]];
            break;

        case NSEventTypeBeginGesture:
            respondingView = [event.window bridgedHitTest:[event locationInWindow]];
            if (velvetShouldHandleRespondingView()) {
                self.currentGestureResponder = respondingView;
            }

            break;

        case NSEventTypeEndGesture:
            respondingView = self.currentGestureResponder;
            self.currentGestureResponder = nil;

            break;

        case NSLeftMouseUp:
        case NSRightMouseUp:
        case NSOtherMouseUp:
            respondingView = (id)self.currentMouseDownResponder ?: [event.window firstResponder];

            self.currentMouseDownResponder = nil;
            break;

        case NSLeftMouseDragged:
        case NSRightMouseDragged:
        case NSOtherMouseDragged:
            respondingView = (id)self.currentMouseDownResponder ?: [event.window firstResponder];
            break;

        case NSMouseMoved:
        case NSMouseEntered:
        case NSMouseExited:
            [self handleMouseTrackingEvent:event];
            return NO;

        default:
            // any other kind of event is not handled by us
            ;
    }

    return dispatchToView();
}

- (NSPoint)convertScreenPoint:(NSPoint)point toWindow:(NSWindow *)window {
    if (!window)
        return point;

    NSRect r = NSMakeRect(point.x, point.y, 1, 1);
    r = [window convertRectFromScreen:r];
    return r.origin;
}

- (NSEvent *)mouseEventByAddingWindow:(NSEvent *)event {
    if (!event || event.window)
        return event;

    // For the moment, only consider the key window, because it's all we need
    NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
    NSPoint windowLoc = [self convertScreenPoint:event.locationInWindow toWindow:keyWindow];

    NSEvent *windowEvent = [NSEvent mouseEventWithType:event.type
        location:windowLoc
        modifierFlags:event.modifierFlags
        timestamp:event.timestamp
        windowNumber:keyWindow.windowNumber
        context:keyWindow.graphicsContext
        eventNumber:event.eventNumber
        clickCount:event.clickCount
        pressure:event.pressure];

    return windowEvent;
}

- (void)handleMouseTrackingEvent:(NSEvent *)event {
    // Try to determine the window to get the event.
    event = [self mouseEventByAddingWindow:event];
    if (!event)
        return;

    id hitView = [event.window bridgedHitTest:[event locationInWindow]];
    if (hitView == self.lastMouseTrackingResponder) {
        [hitView tryToPerform:@selector(mouseMoved:) with:event];
        return;
    }

    [self.lastMouseTrackingResponder tryToPerform:@selector(mouseExited:) with:event];

    if ([hitView isKindOfClass:[NSView class]]) {
        self.lastMouseTrackingResponder = nil;
        return;
    }

    [event.window setAcceptsMouseMovedEvents:YES];

    self.lastMouseTrackingResponder = hitView;
    [hitView tryToPerform:@selector(mouseEntered:) with:event];
}

@end
