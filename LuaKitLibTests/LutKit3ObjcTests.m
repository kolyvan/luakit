//
//  LutKit3ObjcTests.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 29.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "LuaState.h"
#import "FooObj.h"

@interface LutKit3ObjcTests : XCTestCase

@end

@implementation LutKit3ObjcTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testToString {
    
    LuaState *luaState = [LuaState new];
    
    FooObj * foo = [FooObj new];
    foo.name = @"Alica";
    
    [luaState setNamed:@"foo" withValue:foo options:0];
    
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:@"return objc.tostring(foo)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[foo.description]);
}

- (void)testPack {
    
    LuaState *luaState = [LuaState new];
    
    //FooObj * foo = [FooObj new];
    //foo.name = @"Red Fox";
    
    NSValue *val = [NSValue valueWithRange:NSMakeRange(7, 42)];
    NSArray *rval; NSError *err;
    XCTAssert([luaState runChunk:@"return objc.nsrange(7, 42)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[val]);
    
    val = [NSValue valueWithCGSize:(CGSize){10.f, 20.f}];
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.cgsize(10, 20)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[val]);
    
    val = [NSValue valueWithCGPoint:(CGPoint){10.f, 20.f}];
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.cgpoint(10, 20)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[val]);
    
    val = [NSValue valueWithCGRect:(CGRect){10.f, -10.f, 80.f, 40.f}];
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.cgrect(10, -10, 80, 40)" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[val]);
    
    
    FooObj * foo = [FooObj new];
    foo.name = @"Red Fox";
    
    [luaState runChunk:@"f1 = function(x, s) return x:findInName(s); end" error:nil];
    [luaState runChunk:@"f2 = function(x, s) i = objc.unpack(x:findInName(s)); return i; end" error:nil];
    
    val = [NSValue valueWithRange:NSMakeRange(4, 3)];
    rval = nil;
    NSArray *args = @[foo, @"Fox"];
    XCTAssert([luaState runFunctionNamed:@"f1" arguments:args rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[val]);
    
    rval = nil;
    XCTAssert([luaState runFunctionNamed:@"f2" arguments:args rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@4]);
}

- (void)testWrap {
    
    NSArray *rval; NSError *err; id obj;
    NSDictionary *dict = @{ @"a":@42 };
    
    LuaState *luaState = [LuaState new];
    
    // gets the lua table as dictionary
    rval = nil;
    XCTAssert([luaState runChunk:@"return {a=42}" rvalues:&rval options:LuaKitOptionsTable error:&err]);
    XCTAssertEqualObjects(rval, @[dict]);
    
    // gets the lua table as wrapped obj
    rval = nil;
    XCTAssert([luaState runChunk:@"return {a=42}" rvalues:&rval options:0 error:&err]);
    obj = rval.firstObject;
    XCTAssertTrue([obj isKindOfClass:[LuaObjectRef class]]); // unwrap
    XCTAssertEqualObjects([obj takeValue], dict);
    
     // sets as wrapped obj and gets back the dictionary
    [luaState setNamed:@"t" withValue:dict options:0];
    rval = nil;
    XCTAssert([luaState runChunk:@"return t" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[dict]);
    
    //set as lua table and gets back the dictionary
    [luaState setNamed:@"t" withValue:dict options:LuaKitOptionsTable];
    rval = nil;
    XCTAssert([luaState runChunk:@"return t" rvalues:&rval options:LuaKitOptionsTable error:&err]);
    XCTAssertEqualObjects(rval, @[dict]);
    
    //set as lua table and gets as wrapped obj
    [luaState setNamed:@"t" withValue:dict options:LuaKitOptionsTable];
    rval = nil;
    XCTAssert([luaState runChunk:@"return t" rvalues:&rval options:0 error:&err]);
    obj = rval.firstObject;
    XCTAssertTrue([obj isKindOfClass:[LuaObjectRef class]]); // unwrap
    XCTAssertEqualObjects([obj takeValue], dict);
    
    //set as wrapped, unwrap to lua table and gets the 'a' index
    [luaState setNamed:@"t" withValue:dict options:0];
    rval = nil;
    XCTAssert([luaState runChunk:@"return objc.unwrap(t).a" rvalues:&rval options:0 error:&err]);
    XCTAssertEqualObjects(rval, @[@42]);    

}

@end
