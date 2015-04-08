//
//  LuaConsole.m
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

#import "LuaConsole.h"
#import "LuaState.h"
#import "LuaConsoleInputAccessory.h"
#import "LuaAutocomplete.h"

typedef enum {
    LuaConsoleTextKindNone,
    LuaConsoleTextKindInput,
    LuaConsoleTextKindIncomplete,
    LuaConsoleTextKindResult,
    LuaConsoleTextKindPrint,
    LuaConsoleTextKindError,
} LuaConsoleTextKind;

///

@interface LuaConsoleTextView : UITextView
@end

///

@interface LuaConsole() <UITextViewDelegate, LuaStateDelegate, LuaConsoleInputAccessoryDelegate>
@property (readonly, nonatomic, strong) LuaConsoleTextView *textView;
@property (readonly, nonatomic, strong) UIView *borderView;
@end

@implementation LuaConsole {

    BOOL            _didInit;
    BOOL            _didObserve;
    NSString        *_buffer;
    NSUInteger      _inputLoc;
    UITextRange     *_completeRange;
}

- (instancetype) initWithLuaState:(LuaState *)luaState
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _luaState = luaState;
        _appearance = [LuaConsoleAppearance new];
    }
    return self;
}

- (void) dealloc
{
    _luaState.delegate = nil;
    
    if (_didObserve) {
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    }
}

- (void)loadView
{
    const CGRect frame = [[UIScreen mainScreen] bounds];
    self.view = ({
        UIView *v = [[UIView alloc] initWithFrame:frame];
        v.backgroundColor = [UIColor clearColor];
        v.opaque = YES;
        v;
    });
    
    _textView = ({
        
        NSTextStorage *textStorage = [NSTextStorage new];
        NSLayoutManager *layoutManager = [NSLayoutManager new];
        [textStorage addLayoutManager:layoutManager];
        NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:self.view.bounds.size];
        [layoutManager addTextContainer:textContainer];
        
        LuaConsoleTextView *v = [[LuaConsoleTextView alloc] initWithFrame:self.view.bounds
                                                            textContainer:textContainer];
        v.delegate = self;
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        v.font = _appearance.font;
        v.backgroundColor = _appearance.backColor;
        v.opaque = YES;
        v.editable = YES;
        v.selectable = YES;
        v.autocorrectionType = UITextAutocorrectionTypeNo;
        v.autocapitalizationType = UITextAutocapitalizationTypeNone;
        v.spellCheckingType = UITextSpellCheckingTypeNo;
        v.dataDetectorTypes = UIDataDetectorTypeNone;
        v.showsHorizontalScrollIndicator = NO;
        v.indicatorStyle = UIScrollViewIndicatorStyleWhite;
        v.keyboardAppearance = _appearance.keyboardAppearance;
        v.typingAttributes = [self attributesForTextKind:LuaConsoleTextKindInput];
        v.contentInset = UIEdgeInsetsMake(0, 0, v.font.pointSize, 0);
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            UIEdgeInsets insets = v.textContainerInset;
            insets.left += 10.f; insets.right += 10.f;
            v.textContainerInset = insets;
        }
        v;
    });
    
    [self.view addSubview:_textView];

    [self setupInputAccessory];
}

- (void) viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    if (!_didInit) {
        
        _didInit = YES;
        [self appendText:[LuaState versionString] kind:LuaConsoleTextKindNone];
        _luaState.delegate = self;
    }
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!_didObserve) {
        
        _didObserve = YES;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
}

- (void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (_didObserve) {
        
        _didObserve = NO;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    }
    
    [self.view.window endEditing:YES];
}

- (void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        [self.view.window endEditing:YES];
    }
}

- (void) didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self setupInputAccessory];
}

#pragma mark - public

- (void) setAppearance:(LuaConsoleAppearance *)appearance
{
    if (_appearance != appearance) {
    
        _appearance = appearance;
        if (self.isViewLoaded) {         
            _textView.backgroundColor = _appearance.backColor;
            _textView.typingAttributes = [self attributesForTextKind:LuaConsoleTextKindInput];
        }
    }
}

- (void) printText:(NSString *)text
{
    [self appendText:text kind:LuaConsoleTextKindPrint];
}

- (void) clearConsole
{
    _buffer = nil;
    _inputLoc = 0;
    _completeRange = nil;
    _textView.attributedText = nil;
}

#pragma mark - keyboard

- (void)keyboardWillShow:(NSNotification *)notification
{
    CGRect frame = [[notification.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat duration = [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    UIViewAnimationCurve curve = [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    frame = [self.view.window convertRect:frame fromWindow:nil];
    frame = [self.view convertRect:frame fromView:nil];
    
    const CGFloat topKeyboard = frame.origin.y;
    const CGFloat bottomView = CGRectGetMaxY(_textView.frame);
    
    if (topKeyboard < bottomView) {
    
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:duration];
        [UIView setAnimationCurve:curve];
        
        CGRect frame = _textView.frame;
        frame.size.height = topKeyboard - frame.origin.y;
        _textView.frame = frame;
        
        [UIView commitAnimations];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    CGFloat duration = [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    UIViewAnimationCurve curve = [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    
    _textView.frame = self.view.frame;
    
    [UIView commitAnimations];
}

#pragma mark - private

- (void) runChunk:(NSString *)chunk
    secondAttempt:(BOOL)secondAttempt
{
    BOOL oneMoreAttemp = NO;
    
    if (_buffer) {
        
        _buffer = [_buffer stringByAppendingFormat:@"\n%@", chunk];
        
    } else {
        
        if ([chunk hasPrefix:@"="]) {
            
            chunk = [chunk substringFromIndex:1];
            _buffer = [@"return " stringByAppendingString:chunk];
            
        } else if (!secondAttempt &&
                   [chunk rangeOfString:@"="].location == NSNotFound &&
                   ![chunk hasPrefix:@"return"])
        {
            _buffer = [@"return " stringByAppendingString:chunk];
            oneMoreAttemp = YES;
            
        } else {
            
            _buffer = chunk;
        }
    }
    
    NSError *error;
    NSArray *rvalues;
    
    if ([_luaState runChunk:_buffer
                    rvalues:&rvalues
                    options:0
                      error:&error])
    {
        _buffer = nil;
        
        if (rvalues) {
            
            NSMutableString *ms = [NSMutableString string];
            
            BOOL firstLine = YES;
            for (id p in rvalues) {
                
                if (firstLine) {
                    firstLine = NO;
                } else {
                    [ms appendString:@","];
                }
                
                if ([p isKindOfClass:[LuaObjectRef class]]) {
                    
                    LuaObjectRef *obj = p;
                    [ms appendString:[obj typeName]];
                } else {
                    [ms appendString:[p description]];
                }
            }
            
            [self appendText:ms kind:LuaConsoleTextKindResult];
            
        } else {
            
            [self appendText:nil kind:LuaConsoleTextKindNone];
        }
        
    } else {
        
        if ([error.domain isEqualToString:LuaKitErrorDomain] &&
            error.code == LuaKitErrorSyntaxIncomplete)
        {
            [self appendText:nil
                        kind:LuaConsoleTextKindIncomplete];
            
        } else {
            
            _buffer = nil;
            if (oneMoreAttemp) {
                NSLog(@"NEXT TRY!");
                [self runChunk:chunk secondAttempt:YES];
                return;
            }
            
            NSString *errMsg = error.localizedFailureReason;
            if (!errMsg) {
                errMsg = error.localizedDescription;
            }
            
            [self appendText:errMsg ?: @"error"
                        kind:LuaConsoleTextKindError];
        }
    }
}

- (void) appendText:(NSString *)text
              kind:(LuaConsoleTextKind)kind
{
    if (!text &&
        kind == LuaConsoleTextKindNone &&
        _inputLoc == _textView.textStorage.length)
    {
        [self restoreTypingPosition];
        return;
    }
    
    NSMutableAttributedString *mas = _textView.textStorage;
    [_textView.textStorage beginEditing];
    
    if (mas.length && ![mas.string hasSuffix:@"\n"]) {
        NSDictionary *attrs = [self attributesForTextKind:LuaConsoleTextKindInput];
        NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:@"\n"attributes:attrs];
       [mas appendAttributedString:newLine];
    }
    
    if (text.length) {
        
        NSDictionary *attrs = [self attributesForTextKind:kind];
        
        __block BOOL firstLine = YES;
        
        [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            
            if (firstLine) {
                firstLine = NO;
            } else {
                NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:@"\n" attributes:attrs];
                [mas appendAttributedString:newLine];
            }
            
            NSAttributedString *as = [self promtpStringForTextKind:kind];
            if (as) {
                [mas appendAttributedString:as];
            }
            
            if (line.length) {
                NSAttributedString *as = [[NSAttributedString alloc] initWithString:line attributes:attrs];
                [mas appendAttributedString:as];
            }
        }];
        
        if (![mas.string hasSuffix:@"\n"]) {
            
            NSDictionary *attrs = [self attributesForTextKind:LuaConsoleTextKindInput];
            NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:@"\n"attributes:attrs];
            [mas appendAttributedString:newLine];
        }
    }
    
    if (kind != LuaConsoleTextKindIncomplete) {
        kind = LuaConsoleTextKindInput;
    }
    
    NSAttributedString *as = [self promtpStringForTextKind:kind];
    if (as) {
        [mas appendAttributedString:as];
    }
    
    [_textView.textStorage endEditing];
    _inputLoc = _textView.textStorage.length;
    [self restoreTypingPosition];
    
    ((LuaConsoleInputAccessory *)_textView.inputAccessoryView).suggestions = nil;
}

- (BOOL) isIncompleteStatement
{
    return _buffer != nil;
}

- (UIColor *) textColorForTextKind:(LuaConsoleTextKind)kind
{
    switch (kind) {
        case LuaConsoleTextKindNone:        return _appearance.printColor;
        case LuaConsoleTextKindInput:       return _appearance.inputColor;
        case LuaConsoleTextKindIncomplete:  return _appearance.inputColor;
        case LuaConsoleTextKindResult:      return _appearance.resultColor;
        case LuaConsoleTextKindError:       return _appearance.errorColor;
        case LuaConsoleTextKindPrint:       return _appearance.printColor;
    }
}

- (NSDictionary *) attributesForTextKind:(LuaConsoleTextKind)kind
{
    UIColor *color = [self textColorForTextKind:kind];
    
    return @{
             NSForegroundColorAttributeName : (color ?: [UIColor darkTextColor]),
             NSFontAttributeName : _appearance.font,
             };
}

- (NSString *) promtpForTextKind:(LuaConsoleTextKind)kind
{
    switch (kind) {
        case LuaConsoleTextKindNone:        return nil;
        case LuaConsoleTextKindInput:       return nil;
        case LuaConsoleTextKindIncomplete:  return @"  ";
        case LuaConsoleTextKindResult:      return @"= ";
        case LuaConsoleTextKindError:       return @"E ";
        case LuaConsoleTextKindPrint:       return @"* ";
    }
}

- (NSAttributedString *) promtpStringForTextKind:(LuaConsoleTextKind)kind
{
    NSString *promtp = [self promtpForTextKind:kind];
    if (promtp) {
        
        NSDictionary *attrs = [self attributesForTextKind:kind];
        return [[NSAttributedString alloc] initWithString:promtp attributes:attrs];
    }
    return nil;
}

- (void) runCommand
{
    if (_inputLoc > _textView.textStorage.length) {
        _inputLoc = _textView.textStorage.length;
        return;
    }
    
    NSString *command;
    
    UITextPosition *textPos = [_textView positionFromPosition:_textView.beginningOfDocument offset:_inputLoc];
    UITextRange *textRange = [_textView textRangeFromPosition:textPos toPosition:_textView.endOfDocument];
    command = [_textView textInRange:textRange];
    
    if (!command) {
    
        // fallback
        NSString *text = _textView.textStorage.string;
        command = [text substringWithRange:NSMakeRange(_inputLoc, text.length - _inputLoc)];
    }
    
    if (command.length > 1 &&
        self.isIncompleteStatement &&
        [command hasPrefix:[self promtpForTextKind:LuaConsoleTextKindIncomplete]])
    {
        command = [command substringFromIndex:2];
    }
    
    command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (command.length) {
        [self runChunk:command secondAttempt:NO];
    } else {
        [self restoreTypingPosition];
    }
}

- (void) restoreTypingPosition
{
    const NSUInteger length = _textView.textStorage.length;
    
    const CGFloat yOff = _textView.contentSize.height - _textView.bounds.size.height;
    if (yOff > _textView.contentOffset.y) {
       [_textView setContentOffset:(CGPoint){0, yOff} animated:NO];
    }
    
    _textView.selectedRange = NSMakeRange(length, 0);
}

- (void) setupInputAccessory
{
    const BOOL isPhone = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone;
    
    if (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
        
        _textView.inputAccessoryView = nil;
        
    } else if (!_textView.inputAccessoryView) {
        
        _textView.inputAccessoryView = ({
            
            const CGRect bounds = (CGRect){0, 0, self.view.bounds.size.width, isPhone ? 40.f : 60.f};
            LuaConsoleInputAccessory *v = [[LuaConsoleInputAccessory alloc] initWithFrame:bounds];
            v.appearance = self.appearance;
            v.delegate = self;
            v;
        });
    }
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        
        if (range.location == _textView.textStorage.length) {
            [self runCommand];
        } else {
            [self restoreTypingPosition];
        }
        return NO;
    }
    
    if (range.location < _inputLoc) {
        
        [self restoreTypingPosition];
        return NO;
    }
    
    return YES;
}

- (void)textViewDidChange:(UITextView *)textView
{
    _completeRange = nil;
    
    LuaConsoleInputAccessory *inpv = (LuaConsoleInputAccessory *)_textView.inputAccessoryView;
    
    if (textView.hasText &&
        !textView.selectedRange.length &&
        textView.isFirstResponder)
    {
        NSString *input;
        
        UITextPosition *textPos = [_textView positionFromPosition:_textView.beginningOfDocument offset:_inputLoc];
        UITextRange *textRange = [_textView textRangeFromPosition:textPos toPosition:_textView.endOfDocument];
        input = [_textView textInRange:textRange];
        
        UITextRange *wordRange;
        NSString *word;
        
        textPos = [textView positionWithinRange:textView.selectedTextRange
                            farthestInDirection:UITextLayoutDirectionLeft];
        if (textPos) {
            
            wordRange = [textView.tokenizer rangeEnclosingPosition:textPos
                                                   withGranularity:UITextGranularityWord
                                                       inDirection:UITextWritingDirectionNatural];
            
            if (wordRange) {
                word = [textView textInRange:wordRange];
                _completeRange = wordRange;
            }
        }

        if (input || word) {
            
            inpv.suggestions = [LuaAutocomplete suggestionForInput:input
                                                              word:word
                                                          luaState:_luaState];
        } else {
            
            inpv.suggestions = nil;
        }
        
        return;
    }
    
    inpv.suggestions = nil;
}

#pragma mark - LuaStateDelegate

- (void) luaState:(LuaState *)state printText:(NSString *)text
{
    [self appendText:text kind:LuaConsoleTextKindPrint];
}

#pragma mark - autocompletion


- (void) luaConsoleInputAccessory:(LuaConsoleInputAccessory *)v suggestion:(NSString *)suggestion
{
    if ([[LuaAutocomplete luaTokens] containsObject:suggestion]) {
        
        [_textView insertText:suggestion];
        
    }  else if (_completeRange) {
        
        [_textView replaceRange:_completeRange withText:suggestion];
        
    } else {
        
        UITextPosition *textPos = [_textView positionFromPosition:_textView.endOfDocument offset:-1];
        if (textPos) {
            UITextRange *textRange = [_textView textRangeFromPosition:textPos toPosition:_textView.endOfDocument];
            NSString *tail = [_textView textInRange:textRange];
            if (tail &&
                ![tail isEqualToString:@" "] &&
                ![tail isEqualToString:@"."] &&
                ![tail isEqualToString:@":"])
            {
                suggestion = [@" " stringByAppendingString:suggestion];
            }
        }
        
        [_textView insertText:suggestion];
    }

    _completeRange = nil;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation LuaConsoleTextView
@end

////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation LuaConsoleAppearance

- (id) init
{
    self = [super init];
    if (self) {
        
        _keyboardAppearance = UIKeyboardAppearanceDefault;
        _backColor = [UIColor whiteColor];
        _inputColor = [UIColor darkTextColor];
        _resultColor = [UIColor blueColor];
        _printColor = [UIColor darkGrayColor];
        _errorColor = [UIColor redColor];
        
        NSString *textStyle = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? UIFontTextStyleBody : UIFontTextStyleSubheadline;
        
        const CGFloat size = [UIFontDescriptor preferredFontDescriptorWithTextStyle:textStyle].pointSize;
        
        _font = [UIFont fontWithName:@"Menlo" size:size];
        if (!_font) {
            _font = [UIFont fontWithName:@"Courier New" size:size];
        }
    }
    return self;
}

@end