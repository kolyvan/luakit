//
//  FooObj.m
//  LuaKit
//
//  Created by Kolyvan on 29.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import "FooObj.h"
#import "LuaKit.h"
#import "LuaState.h"

static NSInteger gFooCounter = 0;

@implementation FooObj

- (instancetype) init
{
    return [self initWithName:nil number:0];
}

- (instancetype) initWithName:(NSString *)name
{
    return [self initWithName:name number:0];
}

- (instancetype) initWithName:(NSString *)name
                       number:(NSInteger)number
{
    self = [super init];
    if (self) {
        gFooCounter += 1;
        _name = name;
        _number = number;
    }
    return self;
}

- (void) dealloc
{
    gFooCounter -= 1;
    NSLog(@"dealloc %@ %p %@ CNT: %ld", self.class, self, _name, (long)gFooCounter);
}

- (void) incrNumber
{
    _number += 1;
}

- (NSUInteger) mulLVal:(NSUInteger)l RVal:(NSUInteger)r
{
    return l*r;
}

- (NSRange) findInName:(NSString *)text
{
    return [_name rangeOfString:text];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"<%@ %p %@ #%ld>", self.class, self, _name, (long)_number];
}

- (BOOL) isEqual:(id)other
{
    if (self == other) {
        return YES;
    }
    
    if (!other) {
        return NO;
    }
    
    if (![other isKindOfClass:[FooObj class]]) {
        return NO;
    }
    
    return [self isEqualToFoo:other];
    
}

- (BOOL) isEqualToFoo:(FooObj *)other
{
    return
    _number == other->_number &&
    (_name == other->_name || [_name isEqualToString:other->_name]);
}

- (id) copyWithZone:(NSZone *)zone // NS_RETURNS_RETAINED
{    
    return [[FooObj allocWithZone:zone] initWithName:_name number:_number];
}

+ (NSInteger) fooCounter
{
    return gFooCounter;
}

+ (instancetype) fooWithName:(NSString *)name // NS_RETURNS_RETAINED
{
    return [[FooObj alloc] initWithName:name number:0];
}

- (void) doAction:(id)param
{
    NSLog(@"%s (%@) %p", __PRETTY_FUNCTION__, param, self);
    if ([param isKindOfClass:[NSString class]]) {
        _name = param;
    } else if ([param isKindOfClass:[NSNumber class]]) {
        _number = [param integerValue];
    } else if ([param isKindOfClass:[NSNotification class]]) {
        NSNotification *n = param;
        _name = n.userInfo[@"name"];
        _number = [n.userInfo[@"number"] integerValue];
    }
}

- (void) fooManager:(FooManager *)fm didFired:(id)param
{
    NSLog(@"%s %p", __PRETTY_FUNCTION__, self);
    [self doAction:param];
}

@end



@implementation FooManager

- (void) dealloc
{
    NSLog(@"dealloc %@ %p TRG:%@", self.class, self, _target);
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"<%@ %p TRG:%@>", self.class, self, _target];
}

- (void) addTarget:(id)target action:(SEL)action
{
    _target = target;
    _action = action;
}

- (void) setTarget:(id)target
{
    if (_target != target) {
        _target = target;
    }
}

- (void) setDelegate:(id)delegate
{
    if (_delegate != delegate) {
        _delegate = delegate;
    }
}

- (void) fireAction:(id)param
{
    NSLog(@"%s %p", __PRETTY_FUNCTION__, self);
    
    __strong id target = self.target;
    
    if (target &&
        _action &&
        [target respondsToSelector:_action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [target performSelector:_action withObject:param];
#pragma clang diagnostic pop
    }
    
    __strong id delegate = _delegate;
    if (delegate) {
        
        if ([delegate respondsToSelector:@selector(fooManager:floatValueOf:)]) {
            NSInteger f = (NSInteger)[delegate fooManager:self floatValueOf:42];
            if (param) {
                param = [NSString stringWithFormat:@"%@/%ld", param, (long)f];
            }
        }
        
        if ([delegate respondsToSelector:@selector(fooManager:didFired:)]) {
            [delegate fooManager:self didFired:param];        
        }
    }
    
}

- (void) fireTarget:(id)target
             action:(SEL)selector
              param:(id)param
{
    if ([target isKindOfClass:[LuaTableRef class]]) {
        
        LuaTableRef *table = target;
        NSError *err;
        NSString *selName = NSStringFromSelector(selector);
        NSString *name = luakit_luaNameFromObjcMethodName(selName);
        if (![table callMethod:name
                     arguments:@[ self, param ]
                       rvalues:nil
                       options:0
                         error:&err])
        {
            NSLog(@"%s %@", __PRETTY_FUNCTION__, err);
        }
    }
}

@end