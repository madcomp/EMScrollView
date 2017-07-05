/*
 *  EMScrollView.h
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
 *  successors. We intend this dedication to be an overt act of
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

#import <SpriteKit/SpriteKit.h>

@class EMScrollView;

@protocol EMScrollViewDelegate <NSObject>

@optional
-(void)scrollViewDidScroll:(EMScrollView*)scrollView;
-(void)scrollViewWillBeginDragging:(EMScrollView*)scrollView;
-(void)scrollViewDidEndDragging:(EMScrollView*)scrollView willDecelerate:(BOOL)decelerate;
-(void)scrollViewWillBeginDecelerating:(EMScrollView *)scrollView;
-(void)scrollViewDidEndDecelerating:(EMScrollView *)scrollView;

@end

@interface EMScrollView : SKSpriteNode <UIGestureRecognizerDelegate>

+(instancetype)scrollViewWithContentNode:(SKNode*)contentNode Size:(CGSize)size;

-(instancetype)init __unavailable;
-(instancetype)initWithContentNode:(SKSpriteNode*)contentNode Size:(CGSize)size;
-(void)setHorizontalPage:(int)horizontalPage animated:(BOOL)animated;
-(void)setScrollPosition:(CGPoint)newPos animated:(BOOL)animated;
-(void)setVerticalPage:(int)verticalPage animated:(BOOL)animated;
-(void)update:(CFTimeInterval)currentTime;

@property (nonatomic,assign) BOOL bounces;
@property (nonatomic,strong) SKSpriteNode* contentNode;
@property (nonatomic, weak) id<EMScrollViewDelegate> delegate;
@property (nonatomic,assign) BOOL flipYCoordinates;
@property (nonatomic,assign) int horizontalPage;
@property (nonatomic,assign) BOOL horizontalScrollEnabled;
@property (nonatomic,readonly) float maxScrollX;
@property (nonatomic,readonly) float maxScrollY;
@property (nonatomic,readonly) float minScrollX;
@property (nonatomic,readonly) float minScrollY;
@property (nonatomic,readonly) int numHorizontalPages;
@property (nonatomic,readonly) int numVerticalPages;
@property (nonatomic,assign) BOOL pagingEnabled;
@property (nonatomic,assign) CGPoint scrollPosition;
@property (nonatomic,assign) int verticalPage;
@property (nonatomic,assign) BOOL verticalScrollEnabled;

@end
