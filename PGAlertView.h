/* Copyright © 2007-2008 Ben Trask. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal with the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:
1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimers.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimers in the
   documentation and/or other materials provided with the distribution.
3. The names of its contributors may not be used to endorse or promote
   products derived from this Software without specific prior written
   permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
THE CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS WITH THE SOFTWARE. */
#import <Cocoa/Cocoa.h>

// Views
@class PGAlertGraphic;

enum {
	PGSingleImageGraphic,
	PGInterImageGraphic
};
typedef unsigned PGAlertGraphicType;

@interface PGAlertView : NSView
{
	@private
	NSMutableArray *_graphicStack;
	PGAlertGraphic *_currentGraphic;
	unsigned        _frameCount;
	NSTimer        *_frameTimer;
}

- (PGAlertGraphic *)currentGraphic;
- (void)pushGraphic:(PGAlertGraphic *)aGraphic;
- (void)popGraphic:(PGAlertGraphic *)aGraphic;
- (void)popGraphicIdenticalTo:(PGAlertGraphic *)aGraphic;
- (void)popGraphicsOfType:(PGAlertGraphicType)type;

- (unsigned)frameCount;
- (void)animateOneFrame:(NSTimer *)aTimer;

- (void)windowWillClose:(NSNotification *)aNotif;

@end

@interface PGAlertGraphic : NSObject

+ (id)cannotGoRightGraphic;
+ (id)cannotGoLeftGraphic;
+ (id)loopedRightGraphic;
+ (id)loopedLeftGraphic;

- (PGAlertGraphicType)graphicType;

- (void)drawInView:(PGAlertView *)anAlertView;
- (void)flipHorizontally;

- (NSTimeInterval)fadeOutDelay; // 0 means forever.

- (NSTimeInterval)animationDelay; // 0 means don't animate.
- (unsigned)frameMax;
- (void)animateOneFrame:(PGAlertView *)anAlertView;

@end

@interface PGLoadingGraphic : PGAlertGraphic
{
	@private
	float _progress;
}

+ (id)loadingGraphic;

- (float)progress;
- (void)setProgress:(float)progress;

@end
