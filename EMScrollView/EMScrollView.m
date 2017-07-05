/*
 *  EMScrollView.m
 *
 *  This is free and unencumbered software released into the public domain.
 *
 *  Anyone is free to copy, modify, publish, use, compile, sell, or
 *  distribute this software, either in source code form or as a compiled
 *  binary, for any purpose, commercial or non-commercial, and by any
 *  means.
 *
 *  In jurisdictions that recognize copyright laws, the author or authors
 *  of this software dedicate any and all copyright interest in the
 *  software to the public domain. We make this dedication for the benefit
 *  of the public at large and to the detriment of our heirs and
 *  suEMessors. We intend this dedication to be an overt act of
 *  relinquishment in perpetuity of all present and future rights to this
 *  software under copyright law.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 *  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 *  IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 *  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 *  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *  OTHER DEALINGS IN THE SOFTWARE.
 *
 *  For more information, please refer to <http: *unlicense.org>
 */

#import "EMScrollView.h"

#pragma mark -
#pragma mark Constants

#define kEMScrollViewActionXTag @"8080"
#define kEMScrollViewActionYTag @"8081"
#define kEMScrollViewAllowInteractionBelowVelocity 50.0
#define kEMScrollViewAutoPageSpeed 500.0
#define kEMScrollViewBoundsSlowDown 0.5
#define kEMScrollViewDeacceleration 0.95
#define kEMScrollViewMaxOuterDistBeforeBounceBack 50.0
#define kEMScrollViewMinVelocityBeforeBounceBack 100.0
#define kEMScrollViewSnapDuration 0.4
#define kEMScrollViewSnapDurationFallOff 100.0
#define kEMScrollViewVelocityLowerCap 20.0

@implementation EMScrollView
{
    BOOL _animatingX;
    BOOL _animatingY;
    BOOL _decelerating;
    BOOL _isPanning;
    CFTimeInterval _lastTime;
    UIPanGestureRecognizer* _panRecognizer;
    CGPoint _rawTranslationStart;
    CGPoint _startScrollPos;
    UITapGestureRecognizer* _tapRecognizer;
    CGPoint _velocity;
    UIView* _viewWithGestureRecognizers;
}

#pragma mark -
#pragma mark Class methods

+(instancetype)scrollViewWithContentNode:(SKSpriteNode*)contentNode Size:(CGSize)size
{
    return [[EMScrollView alloc] initWithContentNode:contentNode Size:size];
}

#pragma mark -
#pragma mark Public methods

-(instancetype)initWithContentNode:(SKSpriteNode*)contentNode Size:(CGSize)size
{
    self = [super initWithColor:[UIColor redColor] size:size];
    
    if (self)
    {
        self.contentNode = contentNode;
        self.userInteractionEnabled = YES;
        
        _bounces = YES;
        _horizontalScrollEnabled = YES;
        _lastTime = -1;
        _verticalScrollEnabled = YES;
        
        [self addGestureRecognizers];
    }
    
    return self;
}

-(void)setHorizontalPage:(int)horizontalPage animated:(BOOL)animated
{
    NSAssert(horizontalPage >= 0 && horizontalPage < self.numHorizontalPages, @"Setting invalid horizontal page");
    
    CGPoint pos = self.scrollPosition;
    pos.x = horizontalPage * self.size.width;
    
    [self setScrollPosition:pos animated:animated];
    _horizontalPage = horizontalPage;
}

-(void)setScrollPosition:(CGPoint)newPos animated:(BOOL)animated
{
    // Check bounds
    newPos.x = MAX(MIN(newPos.x, self.maxScrollX), self.minScrollX);
    newPos.y = MAX(MIN(newPos.y, self.maxScrollY), self.minScrollY);
    
    BOOL xMoved = (newPos.x != self.scrollPosition.x);
    BOOL yMoved = (newPos.y != self.scrollPosition.y);
    
    if (animated)
    {
        CGPoint oldPos = self.scrollPosition;
        float dist = sqrt(pow(newPos.x - oldPos.x, 2.0) + pow(newPos.y - oldPos.y, 2.0));
        
        float duration = MIN(MAX(dist / kEMScrollViewSnapDurationFallOff, 0), kEMScrollViewSnapDuration);
        
        if (xMoved)
        {
            // Animate horizontally
            
            _velocity.x = 0;
            _animatingX = YES;
            
            // Create animation action
            SKAction* actionMove = [SKAction moveToX:-newPos.x duration:duration];
            actionMove.timingMode = SKActionTimingEaseOut;
            SKAction* actionBlock = [SKAction runBlock:^{
                [self scrollViewDidScroll];
                [self xAnimationDone];
            }];
            [_contentNode runAction:[SKAction sequence:@[actionMove, actionBlock]] withKey:kEMScrollViewActionXTag];
        }
        if (yMoved)
        {
            // Animate vertically
            
            _velocity.y = 0;
            _animatingY = YES;
            
            // Create animation action
            SKAction* actionMove = [SKAction moveToY:-newPos.y duration:duration];
            actionMove.timingMode = SKActionTimingEaseOut;
            SKAction* actionBlock = [SKAction runBlock:^{
                [self scrollViewDidScroll];
                [self yAnimationDone];
            }];
            [_contentNode runAction:[SKAction sequence:@[actionMove, actionBlock]] withKey:kEMScrollViewActionYTag];
            
        }
    }
    else
    {
        [_contentNode removeActionForKey:kEMScrollViewActionXTag];
        [_contentNode removeActionForKey:kEMScrollViewActionYTag];
        _contentNode.position = CGPointMake(-newPos.x, -newPos.y);
    }
}

-(void)setVerticalPage:(int)verticalPage animated:(BOOL)animated
{
    NSAssert(verticalPage >= 0 && verticalPage < self.numVerticalPages, @"Setting invalid vertical page");
    
    CGPoint pos = self.scrollPosition;
    pos.y = verticalPage * self.size.height;
    
    [self setScrollPosition:pos animated:animated];
    _verticalPage = verticalPage;
}

-(void)update:(CFTimeInterval)currentTime
{
    if (_lastTime > 0)
    {
        [self updateWithDelta:currentTime - _lastTime];
    }
    _lastTime = currentTime;
}

#pragma mark Setting content node

-(void)setContentNode:(SKSpriteNode*)contentNode
{
    if (_contentNode == contentNode) return;
    
    // Replace content node
    if (_contentNode)
    {
        [self removeChildrenInArray:@[_contentNode]];
    }
    _contentNode = contentNode;
    if (contentNode)
    {
        [self addChild:contentNode];
        
        // Update coordinate flipping
        self.flipYCoordinates = self.flipYCoordinates;
    }
}

#pragma mark Min/Max size

-(float) minScrollX
{
    return 0;
}

-(float) maxScrollX
{
    if (!_contentNode) return 0;
    
    float maxScroll = _contentNode.size.width - self.size.width;
    maxScroll = MAX(0, maxScroll);
    
    return maxScroll;
}

-(float) minScrollY
{
    if (!_contentNode) return 0;
    
    if (_flipYCoordinates)
    {
        return 0;
    }
    
    float maxScroll = _contentNode.size.height - self.size.height;
    maxScroll = MAX(0, maxScroll);
    return -maxScroll;
}

-(float) maxScrollY
{
    if (!_contentNode) return 0;
    
    if (_flipYCoordinates)
    {
        float maxScroll = _contentNode.size.height - self.size.height;
        maxScroll = MAX(0, maxScroll);
        return maxScroll;
    }
    
    return 0;
}

#pragma mark Paging

-(void)setHorizontalPage:(int)horizontalPage
{
    [self setHorizontalPage:horizontalPage animated:NO];
}

-(void)setVerticalPage:(int)verticalPage
{
    [self setVerticalPage:verticalPage animated:NO];
}

-(int)numHorizontalPages
{
    if (!_pagingEnabled) return 0;
    if (!self.size.width || !_contentNode.size.width) return 0;
    
    return _contentNode.size.width / self.size.width;
}

-(int)numVerticalPages
{
    if (!_pagingEnabled) return 0;
    if (!self.size.height || !_contentNode.size.height) return 0;
    
    return _contentNode.size.height / self.size.height;
}

#pragma mark Panning and setting position

-(void)setScrollPosition:(CGPoint)newPos
{
    [self setScrollPosition:newPos animated:NO];
}

-(CGPoint)scrollPosition
{
    return CGPointMake(-_contentNode.position.x, -_contentNode.position.y);
}

#pragma mark -
#pragma mark Private methods

-(void)addGestureRecognizers
{
    _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    _panRecognizer.delegate = self;
    
    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapRecognizer.delegate = self;
    
    // Add recognizers to view
    _viewWithGestureRecognizers = [[[[UIApplication sharedApplication] keyWindow] subviews] lastObject];
    
    NSMutableArray* recognizers = [_viewWithGestureRecognizers.gestureRecognizers mutableCopy];
    if (!recognizers) recognizers = [NSMutableArray arrayWithCapacity:2];
    [recognizers insertObject:_panRecognizer atIndex:0];
    [recognizers insertObject:_tapRecognizer atIndex:0];
    
    _viewWithGestureRecognizers.gestureRecognizers = recognizers;
}

-(CGPoint)convertToGL:(CGPoint)point
{
//    return [dir convertToGL:rawTranslation];
    return point;
}

-(void)panLayerToTarget:(CGPoint)newPos
{
    if (_bounces)
    {
        // Scroll at half speed outside of bounds
        if (newPos.x > self.maxScrollX)
        {
            float diff = newPos.x - self.maxScrollX;
            newPos.x = self.maxScrollX + diff * kEMScrollViewBoundsSlowDown;
        }
        if (newPos.x < self.minScrollX)
        {
            float diff = self.minScrollX - newPos.x;
            newPos.x = self.minScrollX - diff * kEMScrollViewBoundsSlowDown;
        }
        if (newPos.y > self.maxScrollY)
        {
            float diff = newPos.y - self.maxScrollY;
            newPos.y = self.maxScrollY + diff * kEMScrollViewBoundsSlowDown;
        }
        if (newPos.y < self.minScrollY)
        {
            float diff = self.minScrollY - newPos.y;
            newPos.y = self.minScrollY - diff * kEMScrollViewBoundsSlowDown;
        }
    }
    else
    {
        if (newPos.x > self.maxScrollX) newPos.x = self.maxScrollX;
        if (newPos.x < self.minScrollX) newPos.x = self.minScrollX;
        if (newPos.y > self.maxScrollY) newPos.y = self.maxScrollY;
        if (newPos.y < self.minScrollY) newPos.y = self.minScrollY;
    }
    [self scrollViewDidScroll];
    _contentNode.position = CGPointMake(-newPos.x, -newPos.y);
}

-(void)removeFromParent
{
    [self removeGestureRecognizers];
    
    [super removeFromParent];
}

-(void)removeGestureRecognizers
{
    _panRecognizer.delegate = nil;
    _tapRecognizer.delegate = nil;
    
    // Remove recognizers from view
    NSMutableArray* recognizers = [_viewWithGestureRecognizers.gestureRecognizers mutableCopy];
    [recognizers removeObject:_panRecognizer];
    [recognizers removeObject:_tapRecognizer];
    
    _viewWithGestureRecognizers.gestureRecognizers = recognizers;
}

-(void)updateWithDelta:(CFTimeInterval)df
{
    float fps = 1.0/df;
    float p = 60/fps;
    
    if (! CGPointEqualToPoint(_velocity, CGPointZero) ) {
        [self scrollViewDidScroll];
    } else {
        
        if ( _decelerating && !(_animatingX || _animatingY)) {
            [self scrollViewDidEndDecelerating];
            _decelerating = NO;
        }
    }
    
    if (!_isPanning)
    {
        if (_velocity.x != 0 || _velocity.y != 0)
        {
            CGPoint delta = CGPointMake(df * _velocity.x, df * _velocity.y);
            
            _contentNode.position = CGPointMake(_contentNode.position.x + delta.x, _contentNode.position.y + delta.y);
            
            // Deaccelerate layer
            float deaccelerationX = kEMScrollViewDeacceleration;
            float deaccelerationY = kEMScrollViewDeacceleration;
            
            // Adjust for frame rate
            deaccelerationX = powf(deaccelerationX, p);
            
            // Update velocity
            _velocity.x *= deaccelerationX;
            _velocity.y *= deaccelerationY;
            
            // If velocity is low make it 0
            if (fabs(_velocity.x) < kEMScrollViewVelocityLowerCap) _velocity.x = 0;
            if (fabs(_velocity.y) < kEMScrollViewVelocityLowerCap) _velocity.y = 0;
        }
        
        if (_bounces)
        {
            // Bounce back to edge if layer is too far outside of the scroll area or if it is outside and moving slowly
            BOOL bounceToEdge = NO;
            CGPoint posTarget = self.scrollPosition;
            
            if (!_animatingX && !_pagingEnabled)
            {
                if ((posTarget.x < self.minScrollX && fabs(_velocity.x) < kEMScrollViewMinVelocityBeforeBounceBack) ||
                    (posTarget.x < self.minScrollX - kEMScrollViewMaxOuterDistBeforeBounceBack))
                {
                    bounceToEdge = YES;
                }
                
                if ((posTarget.x > self.maxScrollX && fabs(_velocity.x) < kEMScrollViewMinVelocityBeforeBounceBack) ||
                    (posTarget.x > self.maxScrollX + kEMScrollViewMaxOuterDistBeforeBounceBack))
                {
                    bounceToEdge = YES;
                }
            }
            if (!_animatingY && !_pagingEnabled)
            {
                if ((posTarget.y < self.minScrollY && fabs(_velocity.y) < kEMScrollViewMinVelocityBeforeBounceBack) ||
                    (posTarget.y < self.minScrollY - kEMScrollViewMaxOuterDistBeforeBounceBack))
                {
                    bounceToEdge = YES;
                }
                
                if ((posTarget.y > self.maxScrollY && fabs(_velocity.y) < kEMScrollViewMinVelocityBeforeBounceBack) ||
                    (posTarget.y > self.maxScrollY + kEMScrollViewMaxOuterDistBeforeBounceBack))
                {
                    bounceToEdge = YES;
                }
            }
            
            if (bounceToEdge)
            {
                // Setting the scroll position to the current position will force it to be in bounds
                [self setScrollPosition:posTarget animated:YES];
            }
        }
        else
        {
            if (!_pagingEnabled)
            {
                // Make sure we are within bounds
                [self setScrollPosition:self.scrollPosition animated:NO];
            }
        }
    }
}

-(void)xAnimationDone
{
    _animatingX = NO;
}

-(void)yAnimationDone
{
    _animatingY = NO;
}

#pragma mark Gesture recognizer

-(void)handlePan:(UIPanGestureRecognizer*)gestureRecognizer
{
    CGPoint rawTranslation = [gestureRecognizer translationInView:_viewWithGestureRecognizers];
    rawTranslation = [self convertToGL:rawTranslation];
    rawTranslation = [self convertPoint:rawTranslation toNode:self];
    
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan)
    {
        [self scrollViewWillBeginDragging];
        _animatingX = NO;
        _animatingY = NO;
        _rawTranslationStart = rawTranslation;
        _startScrollPos = self.scrollPosition;
        
        _isPanning = YES;
        
        [_contentNode removeActionForKey:kEMScrollViewActionXTag];
        [_contentNode removeActionForKey:kEMScrollViewActionYTag];
    }
    else if (gestureRecognizer.state == UIGestureRecognizerStateChanged)
    {
        // Calculate the translation in node space
        CGPoint translation = CGPointMake(_rawTranslationStart.x - rawTranslation.x, _rawTranslationStart.y - rawTranslation.y);
        
        // Check if scroll directions has been disabled
        if (!_horizontalScrollEnabled) translation.x = 0;
        if (!_verticalScrollEnabled) translation.y = 0;
        
        if (!_flipYCoordinates) translation.y = -translation.y;
        
        // Check bounds
        CGPoint newPos = CGPointMake(_startScrollPos.x + translation.x, _startScrollPos.y + translation.y);
        
        // Update position
        [self panLayerToTarget:newPos];
    }
    else if (gestureRecognizer.state == UIGestureRecognizerStateEnded)
    {
        
        // Calculate the velocity in node space
        CGPoint ref = [self convertToGL:CGPointZero];
        ref = [self convertPoint:ref toNode:self];
        
        CGPoint velocityRaw = [gestureRecognizer velocityInView:_viewWithGestureRecognizers];
        velocityRaw = [self convertToGL:velocityRaw];
        velocityRaw = [self convertPoint:velocityRaw toNode:self];
        
        _velocity = CGPointMake(velocityRaw.x - ref.x, velocityRaw.y - ref.y);
        if (!_flipYCoordinates) _velocity.y = -_velocity.y;
        
        // Check if scroll directions has been disabled
        if (!_horizontalScrollEnabled) _velocity.x = 0;
        if (!_verticalScrollEnabled) _velocity.y = 0;
        [self scrollViewDidEndDraggingAndWillDecelerate:!CGPointEqualToPoint(_velocity, CGPointZero)];
        
        // Setup a target if paging is enabled
        if (_pagingEnabled)
        {
            CGPoint posTarget = CGPointZero;
            
            // Calculate new horizontal page
            int pageX = roundf(self.scrollPosition.x / self.size.width);
            
            if (fabs(_velocity.x) >= kEMScrollViewAutoPageSpeed && _horizontalPage == pageX)
            {
                if (_velocity.x < 0) pageX += 1;
                else pageX -= 1;
            }
            
            pageX = MIN(MAX(pageX, 0), self.numHorizontalPages -1);
            _horizontalPage = pageX;
            
            posTarget.x = pageX * self.size.width;
            
            // Calculate new vertical page
            int pageY = roundf(self.scrollPosition.y / self.size.height);
            
            if (fabs(_velocity.y) >= kEMScrollViewAutoPageSpeed && _verticalPage == pageY)
            {
                if (_velocity.y < 0) pageY += 1;
                else pageY -= 1;
            }
            
            pageY = MIN(MAX(pageY, 0), self.numVerticalPages -1);
            _verticalPage = pageY;
            
            posTarget.y = pageY * self.size.height;
            
            [self setScrollPosition:posTarget animated:YES];
            
            _velocity = CGPointZero;
        }
        [self scrollViewWillBeginDecelerating];
        _decelerating = YES;
        _isPanning = NO;
    }
    else if (gestureRecognizer.state == UIGestureRecognizerStateCancelled)
    {
        _isPanning = NO;
        _velocity = CGPointZero;
        _animatingX = NO;
        _animatingY = NO;
        
        [self setScrollPosition:self.scrollPosition animated:NO];
    }
}

-(void)handleTap:(UIGestureRecognizer*)gestureRecognizer
{
    // Stop layer from moving
    _velocity = CGPointZero;
    
    // Snap to a whole position
    CGPoint pos = _contentNode.position;
    pos.x = roundf(pos.x);
    pos.y = roundf(pos.y);
    _contentNode.position = pos;
}

-(BOOL)isAncestor:(SKNode*)ancestor toNode:(SKNode*)node
{
    for (SKNode* child in node.children)
    {
        if (child == ancestor) return YES;
        if ([self isAncestor:ancestor toNode:child]) return YES;
    }
    return NO;
}

-(BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldReceiveTouch:(UITouch*)touch
{
    if (!_horizontalScrollEnabled && !_verticalScrollEnabled) return NO;
    if (!_contentNode) return NO;
    if (self.hidden) return NO;
    if (!self.userInteractionEnabled) return NO;
    
    // Check for responders above this scroll view (and not within it). If there are responders above touch should go to them instead.
    CGPoint touchWorldPos = [touch locationInView:nil];
    
    NSArray* responders = [self.scene nodesAtPoint:touchWorldPos];
    BOOL foundSelf = NO;
    for (int i = (int)responders.count - 1; i >= 0; i--)
    {
        SKNode* responder = responders[i];
        if (foundSelf)
        {
            if (![self isAncestor:responder toNode:self])
            {
                return NO;
            }
        }
        else if (responder == self)
        {
            foundSelf = YES;
        }
    }
    
    // Allow touches to children if view is moving slowly
    BOOL slowMove = (fabs(_velocity.x) < kEMScrollViewAllowInteractionBelowVelocity &&
                     fabs(_velocity.y) < kEMScrollViewAllowInteractionBelowVelocity);
    
    if (gestureRecognizer == _tapRecognizer && (slowMove || _isPanning))
    {
        return NO;
    }
    
    // Check that the gesture is in the scroll view
    return [self containsPoint:touchWorldPos];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer
{
    return (otherGestureRecognizer == _panRecognizer || otherGestureRecognizer == _tapRecognizer);
}

#pragma mark - CCScrollViewDelegate Helpers

-(void)scrollViewDidScroll
{
    if ( [self.delegate respondsToSelector:@selector(scrollViewDidScroll:)] )
    {
        [self.delegate scrollViewDidScroll:self];
    }
}

-(void)scrollViewWillBeginDragging
{
    if ( [self.delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)])
    {
        [self.delegate scrollViewWillBeginDragging:self];
    }
}
-(void)scrollViewDidEndDraggingAndWillDecelerate:(BOOL)decelerate
{
    if ([self.delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)])
    {
        [self.delegate scrollViewDidEndDragging:self
                                 willDecelerate:decelerate];
    }
}
-(void)scrollViewWillBeginDecelerating
{
    if ( !_pagingEnabled )
    {
        if ( [self.delegate respondsToSelector:@selector(scrollViewWillBeginDecelerating:)])
        {
            [self.delegate scrollViewWillBeginDecelerating:self];
        }
    }
    
}
-(void)scrollViewDidEndDecelerating
{
    if ( [self.delegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)])
    {
        [self.delegate scrollViewDidEndDecelerating:self];
    }
}

@end
