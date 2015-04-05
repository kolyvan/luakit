//
//  LuaKit2MetatableTests.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 29.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "LuaState.h"
#import "FooObj.h"

@interface LuaKit2MetatableTests : XCTestCase
@end

@implementation LuaKit2MetatableTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testObjectFinalize1 {
    
    XCTAssertTrue([FooObj fooCounter] == 0);
    
    LuaState *luaState = [LuaState new];
    
    @autoreleasepool {
        
        FooObj * foo = [FooObj new];
        foo.name = @"Alica";
        [luaState setNamed:@"foo" withValue:foo options:0];
    }
    
    XCTAssertTrue([FooObj fooCounter] == 1);
    [luaState tearDown];
    XCTAssertTrue([FooObj fooCounter] == 0);
}

- (void)testObjectFinalize2 {
    
    XCTAssertTrue([FooObj fooCounter] == 0);
    
    LuaState *luaState = [LuaState new];
    
    @autoreleasepool {
        
        FooObj * foo = [FooObj new];
        foo.name = @"Alica";
        [luaState setNamed:@"foo" withValue:foo options:0];
        
        NSArray *rval; NSError *err;
        XCTAssert([luaState runChunk:@"return foo:copy()" rvalues:&rval options:0 error:&err]);
        XCTAssertEqualObjects(rval, @[foo]);
        XCTAssertTrue(rval[0] != foo);
        
        //[luaState setNamed:@"foo" withValue:nil options:0];
        //[luaState collectGarbage];
    }
    
    //XCTAssertTrue([FooObj fooCounter] == 0); // if foo=nil and collectgarbage
    XCTAssertTrue([FooObj fooCounter] == 2);
    [luaState tearDown];
    XCTAssertTrue([FooObj fooCounter] == 0);
}

- (void)testObjectMethods {
 
    LuaState *luaState = [LuaState new];
    
    FooObj * foo = [FooObj new];
    foo.name = @"Alica";
    
    [luaState setNamed:@"foo" withValue:foo options:0];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:@"return foo" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[foo]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return foo.name" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@"Alica"]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"foo.name='Bob'; return foo.name" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@"Bob"]);

    XCTAssertFalse([luaState runChunk:@"foo.number=42" rvalues:&rval options:0 error:&err]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"foo:incrNumber() return foo.number" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@1]);
    
    rval = nil;
    XCTAssert([luaState runChunk:@"return foo:mulLVal_RVal(3,4)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@12]);
    
}

- (void)testObjectAsArg {
    
    LuaState *luaState = [LuaState new];
    XCTAssert([luaState runChunk:@"function f1(x) return x.name; end" error:nil]);
    
    FooObj * foo = [FooObj new];
    foo.name = @"Alica";
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runFunctionNamed:@"f1" arguments:@[foo] rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@"Alica"]);
}


@end
