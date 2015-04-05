//
//  FooObj.h
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 29.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FooObj : NSObject<NSCopying>
@property (readonly, nonatomic) NSInteger number;
@property (readwrite, nonatomic, strong) NSString *name;

- (instancetype) initWithName:(NSString *)name
                       number:(NSInteger)number;

- (void) incrNumber;
- (NSUInteger) mulLVal:(NSUInteger)l RVal:(NSUInteger)r;
- (NSRange) findInName:(NSString *)text;

+ (NSInteger) fooCounter;
+ (instancetype) fooWithName:(NSString *)name;

@end

@protocol FooManagerDelegate;

@interface FooManager : NSObject

@property (readwrite, nonatomic, weak) id target;
@property (readwrite, nonatomic) SEL action;
@property (readwrite, nonatomic, weak) id delegate;

- (void) addTarget:(id)target action:(SEL)action;
- (void) fireAction:(id)param;

@end


@protocol FooManagerDelegate <NSObject>
- (void) fooManager:(FooManager *)fm didFired:(id)param;
- (float) fooManager:(FooManager *)fm floatValueOf:(NSInteger)number;
@end