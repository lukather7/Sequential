/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGThumbnailView.h"
#import <tgmath.h>

// Views
#import "PGClipView.h"

// Other Sources
#import "PGAppKitAdditions.h"
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"

#define PGBackgroundHoleSize 6.0f
#define PGBackgroundHoleSpacing 3.0f
#define PGBackgroundHeight (PGBackgroundHoleSize + PGBackgroundHoleSpacing)
#define PGThumbnailSize 128.0f
#define PGThumbnailMarginWidth (PGBackgroundHoleSize + PGBackgroundHoleSpacing * 2.0f)
#define PGThumbnailMarginHeight 2.0f
#define PGThumbnailTotalHeight (PGThumbnailSize + PGThumbnailMarginHeight * 2.0f)
#define PGInnerTotalWidth (PGThumbnailSize + PGThumbnailMarginWidth * 2.0f)
#define PGOuterTotalWidth (PGInnerTotalWidth + 2.0f)

static NSString *const PGThumbnailGlossStyleEnabledKey = @"PGThumbnailGlossStyleEnabled";
static BOOL PGThumbnailGlossStyleEnabled = NO;
static NSColor *PGBackgroundColor = nil;
static NSColor *PGHighlightedBackgroundColor = nil;

@interface PGThumbnailView(Private)

- (void)_validateSelection;
- (NSColor *)_backgroundColorWithHighlight:(BOOL)highlight;

@end

static void PGGradientCallback(void *info, CGFloat const *inData, CGFloat *outData)
{
	if(PGThumbnailGlossStyleEnabled) {
		outData[0] = 1.0f;
		outData[1] = inData[0] < 0.5f ? 0.1f * inData[0] + 0.15f : -0.3f * inData[0] + 0.45f;
	} else {
		outData[0] = (0.25f - pow(inData[0] - 0.5f, 2.0f)) / 2.0f + 0.1f;
		outData[1] = 0.95f;
	}
}
static void PGDrawGradient(void)
{
	static CGShadingRef shade = NULL;
	if(!shade) {
		CGColorSpaceRef const colorSpace = CGColorSpaceCreateDeviceGray();
		CGFloat const domain[] = {0.0f, 1.0f};
		CGFloat const range[] = {0.0f, 1.0f, 0.0f, 1.0f};
		CGFunctionCallbacks const callbacks = {0, PGGradientCallback, NULL};
		CGFunctionRef const function = CGFunctionCreate(NULL, 1, domain, 2, range, &callbacks);
		shade = CGShadingCreateAxial(colorSpace, CGPointMake(0.0f, 0.0f), CGPointMake(PGInnerTotalWidth, 0.0f), function, NO, NO);
		CFRelease(function);
		CFRelease(colorSpace);
	}
	CGContextDrawShading([[NSGraphicsContext currentContext] graphicsPort], shade);
}

@implementation PGThumbnailView

#pragma mark +NSObject

+ (void)initialize
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO] forKey:PGThumbnailGlossStyleEnabledKey]];
	PGThumbnailGlossStyleEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:PGThumbnailGlossStyleEnabledKey];
}

#pragma mark -PGThumbnailView

@synthesize dataSource;
@synthesize delegate;
@synthesize representedObject;
@synthesize thumbnailOrientation = _thumbnailOrientation;
- (void)setThumbnailOrientation:(PGOrientation)orientation
{
	if(orientation == _thumbnailOrientation) return;
	_thumbnailOrientation = orientation;
	[self setNeedsDisplay:YES];
}
@synthesize items = _items;
@synthesize selection = _selection;
- (void)setSelection:(NSSet *)items
{
	if(items == _selection) return;
	NSMutableSet *const removedItems = [[_selection mutableCopy] autorelease];
	[removedItems minusSet:items];
	for(id const removedItem in removedItems) [self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:removedItem] withMargin:YES]];
	NSMutableSet *const addedItems = [[items mutableCopy] autorelease];
	[addedItems minusSet:_selection];
	for(id const addedItem in addedItems) [self setNeedsDisplayInRect:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:addedItem] withMargin:YES]];
	[_selection setSet:items];
	[self _validateSelection];
	[[self delegate] thumbnailViewSelectionDidChange:self];
}

#pragma mark -

- (NSUInteger)indexOfItemAtPoint:(NSPoint)p
{
	return floor(p.y / PGThumbnailTotalHeight);
}
- (NSRect)frameOfItemAtIndex:(NSUInteger)index withMargin:(BOOL)flag
{
	NSRect frame = NSMakeRect(PGThumbnailMarginWidth, index * PGThumbnailTotalHeight + PGThumbnailMarginHeight, PGThumbnailSize, PGThumbnailSize);
	return flag ? NSInsetRect(frame, -PGThumbnailMarginWidth, -PGThumbnailMarginHeight) : frame;
}

#pragma mark -

- (void)reloadData
{
	BOOL const hadSelection = !![_selection count];
	[_items release];
	_items = [[[self dataSource] itemsForThumbnailView:self] copy];
	[self _validateSelection];
	[self sizeToFit];
	[self scrollToFirstSelectedItem];
	[self setNeedsDisplay:YES];
	if(hadSelection) [[self delegate] thumbnailViewSelectionDidChange:self];
}
- (void)sizeToFit
{
	CGFloat const height = [self superview] ? NSHeight([[self superview] bounds]) : 0.0f;
	[super setFrameSize:NSMakeSize(PGOuterTotalWidth, MAX(height, [_items count] * PGThumbnailTotalHeight))];
}
- (void)scrollToFirstSelectedItem
{
	NSUInteger const selCount = [_selection count];
	if(1 == selCount) return [self PG_scrollRectToVisible:[self frameOfItemAtIndex:[_items indexOfObjectIdenticalTo:[_selection anyObject]] withMargin:YES] type:PGScrollCenterToRect];
	else if(selCount) {
		NSUInteger i = 0;
		for(; i < [_items count]; i++) {
			if(![_selection containsObject:[_items objectAtIndex:i]]) continue;
			[self PG_scrollRectToVisible:[self frameOfItemAtIndex:i withMargin:YES] type:PGScrollCenterToRect];
			return;
		}
	}
	[[self PG_enclosingClipView] scrollToEdge:PGMaxYEdgeMask animation:PGAllowAnimation];
}

#pragma mark -

- (void)systemColorsDidChange:(NSNotification *)aNotif
{
	[PGHighlightedBackgroundColor release];
	PGHighlightedBackgroundColor = nil;
	[self setNeedsDisplay:YES];
}

#pragma mark -PGThumbnailView(Private)

- (void)_validateSelection
{
	for(id const selectedItem in [[_selection copy] autorelease]) if([_items indexOfObjectIdenticalTo:selectedItem] == NSNotFound) [_selection removeObject:selectedItem];
}
- (NSColor *)_backgroundColorWithHighlight:(BOOL)highlight
{
	NSImage *const background = [[[NSImage alloc] initWithSize:NSMakeSize(PGOuterTotalWidth, PGBackgroundHeight)] autorelease];
	[background lockFocus];

	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow setShadowBlurRadius:4.0f];
	[shadow set];
	CGContextRef const imageContext = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextBeginTransparencyLayerWithRect(imageContext, CGRectMake(0, 0, PGOuterTotalWidth, PGBackgroundHeight), NULL);
	NSRect const r = NSMakeRect(0.0f, 0.0f, PGInnerTotalWidth, PGBackgroundHeight);
	if(PGThumbnailGlossStyleEnabled) {
		[[NSColor blackColor] set];
		NSRectFill(r);
	} else PGDrawGradient();
	if(highlight) {
		[[[NSColor alternateSelectedControlColor] colorWithAlphaComponent:0.5f] set];
		NSRectFillUsingOperation(r, NSCompositeSourceOver);
	}
	if(PGThumbnailGlossStyleEnabled) PGDrawGradient();

	NSRect const leftHoleRect = NSMakeRect(PGBackgroundHoleSpacing, 0.0f, PGBackgroundHoleSize, PGBackgroundHoleSize);
	NSRect const rightHoleRect = NSMakeRect(PGInnerTotalWidth - PGThumbnailMarginWidth + PGBackgroundHoleSpacing, 0.0f, PGBackgroundHoleSize, PGBackgroundHoleSize);
	[[NSColor colorWithDeviceWhite:1.0f alpha:0.2f] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:leftHoleRect cornerRadius:2.0f] fill];
	[[NSBezierPath PG_bezierPathWithRoundRect:rightHoleRect cornerRadius:2.0f] fill];
	[[NSColor clearColor] set];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(leftHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositeCopy];
	[[NSBezierPath PG_bezierPathWithRoundRect:NSOffsetRect(rightHoleRect, 0.0f, 1.0f) cornerRadius:2.0f] PG_fillUsingOperation:NSCompositeCopy];

	CGContextEndTransparencyLayer(imageContext);
	[background unlockFocus];
	return [NSColor colorWithPatternImage:background];
}

#pragma mark -NSView

- (id)initWithFrame:(NSRect)aRect
{
	if((self = [super initWithFrame:aRect])) {
		_selection = (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
		[(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(systemColorsDidChange:) name:NSSystemColorsDidChangeNotification object:nil];
	}
	return self;
}

#pragma mark -

- (BOOL)isFlipped
{
	return YES;
}
- (BOOL)isOpaque
{
	return YES;
}
- (void)setUpGState
{
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
}
- (void)drawRect:(NSRect)aRect
{
	CGContextRef const context = [[NSGraphicsContext currentContext] graphicsPort];

	NSRect const patternRect = [self convertRect:[self bounds] toView:nil];
	CGContextSetPatternPhase(context, CGSizeMake(NSMinX(patternRect), NSMaxY(patternRect) - PGBackgroundHoleSize / 2.0f));

	NSInteger count = 0;
	NSRect const *rects = NULL;
	[self getRectsBeingDrawn:&rects count:&count];

	if(!PGBackgroundColor) PGBackgroundColor = [[self _backgroundColorWithHighlight:NO] retain];
	[PGBackgroundColor set];
	NSRectFillList(rects, count);

	NSShadow *const nilShadow = [[[NSShadow alloc] init] autorelease];
	[nilShadow setShadowColor:nil];
	NSShadow *const shadow = [[[NSShadow alloc] init] autorelease];
	[shadow setShadowOffset:NSMakeSize(0.0f, -2.0f)];
	[shadow setShadowBlurRadius:4.0f];
	[shadow set];

	NSUInteger i = 0;
	for(; i < [_items count]; i++) {
		NSRect const frameWithMargin = [self frameOfItemAtIndex:i withMargin:YES];
		if(!PGIntersectsRectList(frameWithMargin, rects, count)) continue;
		id const item = [_items objectAtIndex:i];
		if([_selection containsObject:item]) {
			[nilShadow set];
			if(!PGHighlightedBackgroundColor) PGHighlightedBackgroundColor = [[self _backgroundColorWithHighlight:YES] retain];
			[PGHighlightedBackgroundColor set];
			NSRectFill(frameWithMargin);
			[shadow set];
		}
		NSImage *const thumb = [[self dataSource] thumbnailView:self thumbnailForItem:item];
		if(!thumb) {
			[NSBezierPath PG_drawSpinnerInRect:NSInsetRect([self frameOfItemAtIndex:i withMargin:NO], 20.0f, 20.0f) startAtPetal:-1];
			continue;
		}
		NSSize originalSize = [thumb size];
		if(PGRotated90CC & _thumbnailOrientation) originalSize = NSMakeSize(originalSize.height, originalSize.width);
		NSRect const frame = [self frameOfItemAtIndex:i withMargin:NO];
		NSRect const thumbnailRect = PGIntegralRect(PGCenteredSizeInRect(PGScaleSizeByFloat(originalSize, MIN(1, MIN(NSWidth(frame) / originalSize.width, NSHeight(frame) / originalSize.height))), frame));
		BOOL const enabled = [[self dataSource] thumbnailView:self canSelectItem:item];

		NSRect const highlight = [self dataSource] ? [[self dataSource] thumbnailView:self highlightRectForItem:item] : NSZeroRect;
		BOOL const entirelyHighlighted = NSEqualRects(highlight, NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f));
		if(!entirelyHighlighted) {
			CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(thumbnailRect), NULL);
			[nilShadow set];
		}
		NSRect transformedThumbnailRect = thumbnailRect;
		NSAffineTransform *const transform = [NSAffineTransform PG_transformWithRect:&transformedThumbnailRect orientation:[[self dataSource] thumbnailView:self shouldRotateThumbnailForItem:item] ? PGAddOrientation(_thumbnailOrientation, PGFlippedVert) : PGFlippedVert]; // Also flip it vertically because our view is flipped and -drawInRect:… ignores that.
		[transform concat];
		[thumb drawInRect:transformedThumbnailRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:enabled ? 1.0f : 0.33f];
		[transform invert];
		[transform concat];
		if(!entirelyHighlighted) {
			NSRect rects[4];
			NSUInteger count = 0;
			NSRect const r = NSIntersectionRect(thumbnailRect, PGIntegralRect(NSOffsetRect(PGScaleRect(highlight, NSWidth(thumbnailRect), NSHeight(thumbnailRect)), NSMinX(thumbnailRect), NSMinY(thumbnailRect))));
			PGGetRectDifference(rects, &count, thumbnailRect, r);
			[[NSColor colorWithDeviceWhite:0.0f alpha:0.5f] set];
			NSRectFillListUsingOperation(rects, count, NSCompositeSourceAtop);
			CGContextEndTransparencyLayer(context);
			[nilShadow set];
			[[NSColor whiteColor] set];
			NSFrameRect(r);
			[shadow set];
		}

		NSString *const label = [[self dataSource] thumbnailView:self labelForItem:item];
		NSColor *const labelColor = [[self dataSource] thumbnailView:self labelColorForItem:item];
		if(label) {
			[nilShadow set];
			static NSMutableDictionary *attributes = nil;
			if(!attributes) {
				NSMutableParagraphStyle *const style = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
				[style setLineBreakMode:NSLineBreakByWordWrapping];
				[style setAlignment:NSCenterTextAlignment];
				NSShadow *const textShadow = [[[NSShadow alloc] init] autorelease];
				[textShadow setShadowBlurRadius:2.0f];
				[textShadow setShadowOffset:NSMakeSize(0.0f, -1.0f)];
				attributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:textShadow, NSShadowAttributeName, [NSFont systemFontOfSize:11], NSFontAttributeName, style, NSParagraphStyleAttributeName, nil];
			}
			[attributes setObject:enabled ? [NSColor alternateSelectedControlTextColor] : [NSColor disabledControlTextColor] forKey:NSForegroundColorAttributeName];
			static NSTextStorage *textStorage = nil;
			static NSLayoutManager *layoutManager = nil;
			static NSTextContainer *textContainer = nil;
			if(!textStorage) {
				textStorage = [[NSTextStorage alloc] init];
				layoutManager = [[NSLayoutManager alloc] init];
				textContainer = [[NSTextContainer alloc] init];
				[layoutManager addTextContainer:[textContainer autorelease]];
				[textStorage addLayoutManager:[layoutManager autorelease]];
				[textContainer setLineFragmentPadding:0];
			}
			[[textStorage mutableString] setString:label];
			[textStorage setAttributes:attributes range:NSMakeRange(0, [textStorage length])];
			[textContainer setContainerSize:NSMakeSize(PGThumbnailSize - 12.0f, PGThumbnailSize - 8.0f)];
			NSRange const glyphRange = [layoutManager glyphRangeForTextContainer:textContainer];
			NSSize const labelSize = [layoutManager usedRectForTextContainer:textContainer].size;
			[textContainer setContainerSize:labelSize]; // We center the text in the text container, so the final size has to be the right width.
			NSRect const labelRect = NSIntegralRect(NSMakeRect(NSMidX(frame) - labelSize.width / 2.0f, NSMidY(frame) - labelSize.height / 2.0f, labelSize.width, labelSize.height));
			[[(labelColor ? labelColor : [NSColor blackColor]) colorWithAlphaComponent:0.5f] set];
			[[NSBezierPath PG_bezierPathWithRoundRect:NSInsetRect(labelRect, -4.0f, -2.0f) cornerRadius:6.0f] fill];
			[layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:labelRect.origin];
			[shadow set];
		} else if(labelColor) {
			NSRect const labelRect = NSMakeRect(NSMaxX(frame) - 16.0f, round(MAX(NSMaxY(thumbnailRect) - 16.0f, NSMidY(thumbnailRect) - 6.0f)), 12.0f, 12.0f);
			[NSGraphicsContext saveGraphicsState];
			CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(NSInsetRect(labelRect, -5.0f, -5.0f)), NULL);
			NSBezierPath *const labelDot = [NSBezierPath bezierPathWithOvalInRect:labelRect];
			[labelColor set];
			[labelDot fill];
			[[NSColor whiteColor] set];
			[labelDot setLineWidth:2.0f];
			[labelDot stroke];
			CGContextEndTransparencyLayer(context);
			[NSGraphicsContext restoreGraphicsState];
		}
	}
	[nilShadow set];
}

#pragma mark -

- (void)setFrameSize:(NSSize)oldSize
{
	[self sizeToFit];
}

#pragma mark -NSView(PGClipViewAdditions)

- (BOOL)PG_acceptsClicksInClipView:(PGClipView *)sender
{
	return NO;
}

#pragma mark -NSResponder

- (IBAction)moveUp:(id)sender
{
	NSUInteger i = 1;
	for(; i < [_items count]; i++) if([_selection containsObject:[_items objectAtIndex:i]]) {
		[self setSelection:[NSSet setWithObject:[_items objectAtIndex:i - 1]]];
		break;
	}
}
- (IBAction)moveDown:(id)sender
{
	NSUInteger const count = [_items count];
	if(!count) return;
	NSUInteger i = count - 1;
	while(i--) if([_selection containsObject:[_items objectAtIndex:i]]) {
		[self setSelection:[NSSet setWithObject:[_items objectAtIndex:i + 1]]];
		break;
	}
}
- (IBAction)moveUpAndModifySelection:(id)sender
{
	NSUInteger i = 1;
	for(; i < [_items count]; i++) if([_selection containsObject:[_items objectAtIndex:i]]) {
		NSMutableSet *const selection = [[[self selection] mutableCopy] autorelease];
		[selection addObject:[_items objectAtIndex:i - 1]];
		[self setSelection:selection];
		[self PG_scrollRectToVisible:[self frameOfItemAtIndex:i - 1 withMargin:YES] type:PGScrollLeastToRect];
		break;
	}
}
- (IBAction)moveDownAndModifySelection:(id)sender
{
	NSUInteger const count = [_items count];
	if(!count) return;
	NSUInteger i = count - 1;
	while(i--) if([_selection containsObject:[_items objectAtIndex:i]]) {
		NSMutableSet *const selection = [[[self selection] mutableCopy] autorelease];
		[selection addObject:[_items objectAtIndex:i + 1]];
		[self setSelection:selection];
		[self PG_scrollRectToVisible:[self frameOfItemAtIndex:i + 1 withMargin:YES] type:PGScrollLeastToRect];
		break;
	}
}
- (IBAction)selectAll:(id)sender
{
	[self setSelection:[NSSet setWithArray:_items]];
}

#pragma mark -

- (BOOL)acceptsFirstResponder
{
	return YES;
}
- (void)mouseDown:(NSEvent *)anEvent
{
	NSPoint const p = [self convertPoint:[anEvent locationInWindow] fromView:nil];
	NSUInteger const i = [self indexOfItemAtPoint:p];
	id const item = [self mouse:p inRect:[self bounds]] && i < [_items count] ? [_items objectAtIndex:i] : nil;
	BOOL const canSelect = !dataSource || [dataSource thumbnailView:self canSelectItem:item];
	BOOL const modifyExistingSelection = !!([anEvent modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask));
	if([_selection containsObject:item]) {
		if(!modifyExistingSelection) {
			[_selection removeAllObjects];
			[self setNeedsDisplay:YES];
			if(canSelect && item) [_selection addObject:item];
		} else if(item) [_selection removeObject:item];
	} else {
		if(!modifyExistingSelection) {
			[_selection removeAllObjects];
			[self setNeedsDisplay:YES];
		}
		if(canSelect && item) [_selection addObject:item];
	}
	NSRect const itemFrame = [self frameOfItemAtIndex:i withMargin:YES];
	[self setNeedsDisplayInRect:itemFrame];
	[self PG_scrollRectToVisible:itemFrame type:PGScrollLeastToRect];
	[[self delegate] thumbnailViewSelectionDidChange:self];
}
- (void)keyDown:(NSEvent *)anEvent
{
	[self interpretKeyEvents:[NSArray arrayWithObject:anEvent]];
}

#pragma mark -NSObject

- (void)dealloc
{
	[self PG_removeObserver];
	[representedObject release];
	[_items release];
	[_selection release];
	[super dealloc];
}

@end

@implementation NSObject(PGThumbnailViewDataSource)

- (NSArray *)itemsForThumbnailView:(PGThumbnailView *)sender
{
	return nil;
}
- (NSImage *)thumbnailView:(PGThumbnailView *)sender thumbnailForItem:(id)item
{
	return nil;
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender canSelectItem:(id)item;
{
	return YES;
}
- (NSString *)thumbnailView:(PGThumbnailView *)sender labelForItem:(id)item
{
	return nil;
}
- (NSColor *)thumbnailView:(PGThumbnailView *)sender labelColorForItem:(id)item
{
	return nil;
}
- (NSRect)thumbnailView:(PGThumbnailView *)sender highlightRectForItem:(id)item
{
	return NSMakeRect(0.0f, 0.0f, 1.0f, 1.0f);
}
- (BOOL)thumbnailView:(PGThumbnailView *)sender shouldRotateThumbnailForItem:(id)item
{
	return NO;
}

@end

@implementation NSObject(PGThumbnailViewDelegate)

- (void)thumbnailViewSelectionDidChange:(PGThumbnailView *)sender {}

@end
