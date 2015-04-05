//
//  LuaConsoleInputAccessory.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 02.04.15.
//

/*
 Copyright (c) 2015 Konstantin Bukreev All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 - Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 - Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "LuaConsoleInputAccessory.h"
#import "LuaConsole.h"

@interface LuaConsoleInputAccessoryCell : UICollectionViewCell
@property (readonly, nonatomic, strong) UILabel *label;
@end

@implementation LuaConsoleInputAccessoryCell

- (id)initWithFrame:(CGRect)rect
{
    self = [super initWithFrame: rect];
    if (self) {
        
        self.backgroundColor = [UIColor whiteColor];
                
        self.selectedBackgroundView = [[UIView alloc] initWithFrame:rect];
        self.selectedBackgroundView.backgroundColor = [UIColor grayColor];
        self.selectedBackgroundView.opaque = YES;
        
        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.opaque = NO;
        _label.backgroundColor = [UIColor clearColor];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];
    }
    return self;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////

@interface LuaConsoleInputAccessory() <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>
@end

@implementation LuaConsoleInputAccessory {
    
    UICollectionView    *_collView;
    UIFont              *_cellFont;
}

- (instancetype) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor lightGrayColor];
        self.opaque = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void) setAppearance:(LuaConsoleAppearance *)appearance
{
    if (_appearance != appearance) {
        
        _appearance = appearance;
        
        self.backgroundColor = [_appearance.backColor colorWithAlphaComponent:0.7f];
        
        _cellFont = nil;
        if (_collView) {
            _collView.backgroundColor = self.backgroundColor;
            [_collView reloadItemsAtIndexPaths:_collView.indexPathsForVisibleItems];
        }
    }
}

- (void) setupSuggestions
{
    if (!_collView && _suggestions.count) {
        
        const CGFloat W = self.bounds.size.width;
        const CGFloat H = self.bounds.size.height - 2;
        const CGFloat xMargin = 2.f;
        
        UICollectionViewFlowLayout *flowLayout = [[UICollectionViewFlowLayout alloc] init];
        flowLayout.minimumLineSpacing = xMargin;
        flowLayout.minimumInteritemSpacing = xMargin;
        flowLayout.sectionInset = UIEdgeInsetsMake(0, xMargin, 0, xMargin);
        flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        
        _collView = [[UICollectionView alloc] initWithFrame:(CGRect){0, 1, W, H}
                     collectionViewLayout:flowLayout];
        
        _collView.delegate = self;
        _collView.dataSource = self;
        
        _collView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _collView.backgroundColor = self.backgroundColor;
        
        [_collView registerClass:[LuaConsoleInputAccessoryCell class]
      forCellWithReuseIdentifier:@"LuaConsoleInputAccessoryCell"];
        
        [self addSubview:_collView];
        
    } else {
        
        [_collView reloadData];
        [_collView.collectionViewLayout invalidateLayout];
        //[_collView reloadItemsAtIndexPaths:_collView.indexPathsForVisibleItems];
    }
}

- (void) setSuggestions:(NSArray *)suggestions
{
    if (![_suggestions isEqualToArray:suggestions]) {
        _suggestions = suggestions;
        [self setupSuggestions];
    }
}

- (UIFont *) cellFont
{
    if (!_cellFont) {
        
        const CGFloat size = roundf(self.bounds.size.height * 0.4f);
        _cellFont = [UIFont systemFontOfSize:size];
    }
    return _cellFont;
}

#pragma mark - UICollectionView

- (NSInteger)numberOfSectionsInCollectionView: (UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _suggestions.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    
    LuaConsoleInputAccessoryCell *cell;
    cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"LuaConsoleInputAccessoryCell"
                                                     forIndexPath:indexPath];
    
    cell.backgroundColor = _appearance.backColor;
    cell.label.textColor = _appearance.inputColor;
    cell.label.font = self.cellFont;
    cell.label.text = _suggestions[indexPath.item];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    
    id delegate = _delegate;
    if ([delegate respondsToSelector:@selector(luaConsoleInputAccessory:suggestion:)]) {
        
        NSString *suggestion = _suggestions[indexPath.item];
        [delegate luaConsoleInputAccessory:self suggestion:suggestion];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewFlowLayout*)layout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    const CGFloat wMax = collectionView.bounds.size.width;
    const CGFloat H = collectionView.bounds.size.height - layout.sectionInset.top  - layout.sectionInset.bottom;
    
    const BOOL isWide = wMax > 500.f;
    const CGFloat xMargin = isWide ? 12.f : 6.f;
    const CGFloat xMin = isWide ? 44.f : 30.f;
    
    NSString *s = _suggestions[indexPath.item];
    const CGFloat W = [s boundingRectWithSize:(CGSize){ wMax, H}
                                      options:NSStringDrawingUsesLineFragmentOrigin
                                   attributes:@{ NSFontAttributeName : self.cellFont }
                                      context:nil].size.width + xMargin;
    
    return (CGSize){ MAX(xMin, W), H };
}


@end
