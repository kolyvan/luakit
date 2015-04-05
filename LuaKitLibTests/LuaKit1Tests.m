//
//  LuaKit1Tests.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 29.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "LuaState.h"

@interface LuaKit1Tests : XCTestCase

@end

@implementation LuaKit1Tests {
}

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testRunChunk {

    LuaState *state = [LuaState new];
    
    XCTAssert([state runChunk:@"print('Hello')" error:nil]);
    
    NSArray *rval;
    XCTAssert([state runChunk:@"return 2*4" rvalues:&rval options:0 error:nil]);
    XCTAssertEqualObjects(rval, @[@8]);
}

- (void)testGlobalVars {
    
    LuaState *state = [LuaState new];
    [state runChunk:@"ivar=42\n svar='Lua'\ntvar={a=1; b=2}\navar={1,2,3}" error:nil];
    
    XCTAssertEqualObjects(@42, [state numberNamed:@"ivar"]);
    XCTAssertEqualObjects(@"Lua", [state stringNamed:@"svar"]);
    
    NSDictionary *d = @{@"a":@1, @"b": @2 };
    XCTAssertEqualObjects(d, [state tableNamed:@"tvar"]);
    
    NSArray *a = @[@1, @2, @3 ];
    XCTAssertEqualObjects(a, [state tableNamed:@"avar"]);
}

- (void)testGlobalVarsSet {
    
    LuaState *state = [LuaState new];
    
    [state setNamed:@"ivar" withValue:@777 options:0];
    XCTAssertEqualObjects(@777, [state numberNamed:@"ivar"]);
    
    NSDictionary *d = @{@"a":@1, @"b": @2 };
    [state setNamed:@"tvar" withValue:d options:LuaKitOptionsTable];
    XCTAssertEqualObjects(d, [state tableNamed:@"tvar"]);
}

- (void) testRunFunction {
    
    LuaState *state = [LuaState new];
    [state runChunk:@"f1 = function() testF=77; end" error:nil];
    [state runChunk:@"f2 = function() return 42; end" error:nil];
    [state runChunk:@"f3 = function(a) return 2*a; end" error:nil];
    [state runChunk:@"f4 = function(a,b) return a+b, a-b; end" error:nil];
    [state runChunk:@"f5 = function(a,b) return f3(a) + f3(b); end" error:nil];
    
    XCTAssert([state runFunctionNamed:@"f1" error:nil]);
    XCTAssertEqualObjects(@77, [state numberNamed:@"testF"]);
    
    NSArray *rval;
    XCTAssert([state runFunctionNamed:@"f2" arguments:nil rvalues:&rval options:0 error:nil]);
    XCTAssertEqualObjects(rval, @[@42]);
    
    rval = nil;
    XCTAssert([state runFunctionNamed:@"f3" arguments:@[@21] rvalues:&rval options:0 error:nil]);
    XCTAssertEqualObjects(rval, @[@42]);
    
    rval = nil;
    NSArray *args = @[@7, @3], *result = @[@10, @4];
    XCTAssert([state runFunctionNamed:@"f4" arguments:args rvalues:&rval options:0 error:nil]);
    XCTAssertEqualObjects(rval, result);

    rval = nil;
    args = @[@7, @3];
    XCTAssert([state runFunctionNamed:@"f5" arguments:args rvalues:&rval options:0 error:nil]);
    XCTAssertEqualObjects(rval, @[@20]);
}


@end
