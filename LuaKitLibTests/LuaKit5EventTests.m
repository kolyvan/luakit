//
//  LuaKit5EventTests.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 30.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "LuaKit.h"
#import "LuaState.h"
#import "FooObj.h"

@interface LuaKit5EventTests : XCTestCase

@end

@implementation LuaKit5EventTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testTargetSelector {

    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:
               @"fm = objc.create('FooManager')\n"
               @"foo = objc.create('FooObj')\n"
               @"fm:addTarget_action(foo, 'doAction:')\n"
               @"fm:fireAction('Moo')\n"
               @"return foo"
                         rvalues:&rval
                         options:0
                           error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj fooWithName:@"Moo"] ]);
    
}

- (void)testObserver {
    
    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:
               @"foo = objc.create('FooObj')\n"
               @"nc = objc.class('NSNotificationCenter'):defaultCenter()\n"
               @"nc:addObserver_selector_name_object(foo, 'doAction:', 'FooNotify', nil)\n"
               @"ui = objc.wrap{ name='Moo', number=42 }\n"
               @"nc:postNotificationName_object_userInfo('FooNotify', nil, ui)\n"
               @"nc:removeObserver(foo)\n"
               @"return foo\n"
                         rvalues:&rval
                         options:0
                           error:&err]);
    XCTAssertEqualObjects(rval, @[ [[FooObj alloc] initWithName:@"Moo" number:42] ]);
    
}

@end
