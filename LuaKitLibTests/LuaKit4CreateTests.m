//
//  LuaKit4CreateTests.m
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

@interface LuaKit4CreateTests : XCTestCase

@end

@implementation LuaKit4CreateTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testClass {

    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:@"return objc.class('FooObj')" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj class] ]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.create('FooObj'):class()" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj class] ]);
}

- (void) testCreate
{
    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:@"return objc.class('FooObj'):fooWithName('Moo')"
                         rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj fooWithName:@"Moo"] ]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.create('FooObj')" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj new] ]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.create('FooObj', 'initWithName', 'Moo')"
                         rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj fooWithName:@"Moo"] ]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.alloc('FooObj'):init()"
                         rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj new] ]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.alloc('FooObj'):initWithName('Moo')"
                         rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[ [FooObj fooWithName:@"Moo"] ]);

}


@end
