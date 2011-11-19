//
//  VELNSView.h
//  Velvet
//
//  Created by Justin Spahr-Summers on 19.11.11.
//  Copyright (c) 2011 Emerald Lark. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/**
 * A layer-hosted `NSView` that is used to host a `VELView` hierarchy. You must
 * use this class to present a `VELView` and allow it to respond to events.
 */
@interface VELNSView : NSView
@end
