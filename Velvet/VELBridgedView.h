//
//  VELBridgedView.h
//  Velvet
//
//  Created by Justin Spahr-Summers on 22.11.11.
//  Copyright (c) 2011 Bitswift. All rights reserved.
//

#import <AppKit/AppKit.h>

@class NSVelvetView;
@protocol VELHostView;
@protocol VELScrollView;

/**
 * Represents a view that can be bridged by Velvet, allowing interoperation with
 * other UI frameworks.
 */
@protocol VELBridgedView <NSObject>
@required

/**
 * @name Geometry Conversion
 */

/**
 * Converts a point from the coordinate system of the window to that of the
 * receiver.
 *
 * @param point A point in the coordinate system of the receiver's window.
 */
- (CGPoint)convertFromWindowPoint:(CGPoint)point;

/**
 * Converts a point from the receiver's coordinate system to that of its window.
 *
 * @param point A point in the coordinate system of the receiver.
 */
- (CGPoint)convertToWindowPoint:(CGPoint)point;

/**
 * Converts a rectangle from the coordinate system of the window to that of the
 * receiver.
 *
 * @param rect A rectangle in the coordinate system of the receiver's window.
 */
- (CGRect)convertFromWindowRect:(CGRect)rect;

/**
 * Converts a rectangle from the receiver's coordinate system to that of its window.
 *
 * @param rect A rectangle in the coordinate system of the receiver.
 */
- (CGRect)convertToWindowRect:(CGRect)rect;

/**
 * @name Layer
 */

/**
 * The layer backing the receiver.
 *
 * This property must never be `nil`.
 */
@property (nonatomic, strong, readonly) CALayer *layer;

/**
 * @name View Hierarchy
 */

/**
 * The view directly or indirectly hosting the receiver, or `nil` if the
 * receiver is not part of a hosted view hierarchy.
 *
 * The receiver or one of its ancestors will be the <[VELHostView guestView]> of
 * this view.
 *
 * Implementing classes may require that this property be of a more specific
 * type.
 *
 * @note This property should not be set except by the <VELHostView> itself.
 */
@property (nonatomic, unsafe_unretained) id<VELHostView> hostView;

/**
 * Returns the receiver's <hostView> or superview, whichever is closer in the
 * hierarchy.
 */
- (id<VELBridgedView>)immediateParentView;

/**
 * Invoked any time an ancestor of the receiver has relaid itself out,
 * potentially moving or clipping the receiver relative to one of its ancestor
 * views.
 *
 * @note The receiver _must_ forward this message to all of its subviews and any
 * <[VELHostView guestView]>.
 */
- (void)ancestorDidLayout;

/**
 * Invoked any time the receiver has changed absolute positions in the view
 * hierarchy.
 *
 * This will include, for example, any time the receiver or one of its ancestors
 * changes superviews, changes host views, is reordered within its superview,
 * etc.
 *
 * @note The receiver _must_ forward this message to all of its subviews and any
 * <[VELHostView guestView]>.
 */
- (void)viewHierarchyDidChange;

/**
 * Returns the nearest <NSVelvetView> that is an ancestor of the receiver, or of
 * a view hosting the receiver.
 *
 * Returns `nil` if the receiver is not part of a Velvet-hosted view hierarchy.
 */
- (NSVelvetView *)ancestorNSVelvetView;

/**
 * Walks up the receiver's ancestor views, returning the nearest
 * <VELScrollView>.
 *
 * Returns `nil` if no scroll view is an ancestor of the receiver.
 */
- (id<VELScrollView>)ancestorScrollView;

/**
 * Invoked when the receiver is moving to a new <ancestorNSVelvetView>.
 *
 * @param view The new <NSVelvetView> that will host the receiver, or `nil` if
 * the receiver is being detached from its current <ancestorNSVelvetView>.
 *
 * @note The receiver _must_ forward this message to all of its subviews and any
 * <[VELHostView guestView]>.
 */
- (void)willMoveToNSVelvetView:(NSVelvetView *)view;

/**
 * Invoked when the receiver has moved to a new <ancestorNSVelvetView>.
 *
 * @param view The <NSVelvetView> that was previously hosting the receiver, or
 * `nil` if the receiver was not hosted.
 *
 * @note The receiver _must_ forward this message to all of its subviews and any
 * <[VELHostView guestView]>.
 */
- (void)didMoveFromNSVelvetView:(NSVelvetView *)view;

/**
 * @name Focused State
 */

/**
 * Indicates whether the receiver is focused.
 *
 * The receiver is focused if:
 *
 * - It is hosted directly or indirectly within the most descendant
 *   <VELViewController>.
 * - A subview of that <VELViewController> is currently the first responder.
 *
 * The default value for this property is `NO`.
 */
@property (nonatomic, getter = isFocused) BOOL focused;

/**
 * @name Hit Testing
 */

/**
 * Hit tests the receiver's view hierarchy, returning the <VELBridgedView> which
 * is occupying the given point, or `nil` if there is no such view.
 *
 * This method should only traverse views which are visible and allow user
 * interaction.
 *
 * @param point A point, specified in the coordinate system of the receiver,
 * at which to look for a view.
 */
- (id<VELBridgedView>)descendantViewAtPoint:(CGPoint)point;

/**
 * Returns whether the receiver is occupying the given point.
 *
 * @param point A point, specified in the coordinate system of the receiver.
 */
- (BOOL)pointInside:(CGPoint)point;

@end
