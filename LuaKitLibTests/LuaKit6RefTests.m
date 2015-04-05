//
//  LuaKit6RefTests.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 30.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "LuaState.h"
#import "FooObj.h"

@interface LuaKit6RefTests : XCTestCase

@end

@implementation LuaKit6RefTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testCallFunc {
    
    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    
    [luaState runChunk: @"t = {}\n"
                        @"t.a='Foo'\n"
                        @"t.f1 = function() return t.a; end;\n"
                        @"t.f2 = function(x) return x*2; end;\n"
                        @"return t"
               rvalues:&rval
               options:0
                 error:&err];
    
    XCTAssertTrue(rval.count && [rval.firstObject isKindOfClass:[LuaTableRef class]]);
    
    LuaTableRef *table = rval.firstObject;
    XCTAssertEqualObjects([table valueNamed:@"a" options:0], @"Foo");
    
    [table setNamed:@"a" withValue:@77 options:0];
    XCTAssertEqualObjects([table valueNamed:@"a" options:0], @77);
    
    [table callMethod:@"f2" arguments:@[ @42 ] rvalues:&rval options:0 error:&err];
    XCTAssertEqualObjects(rval, @[ @84 ]);
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id val = [table performSelector:sel_getUid("f2:") withObject:@4];
    XCTAssertEqualObjects(val, @8);
    val = [table performSelector:sel_getUid("f1")];
    XCTAssertEqualObjects(val, @77);
#pragma clang diagnostic pop
    
}

- (void)testDelegate {
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"
    @protocol(FooManagerDelegate); // force to register protocol
#pragma clang diagnostic pop
    
    LuaState *luaState = [LuaState new];
    
    NSArray *rval; NSError *err;
    
    [luaState runChunk:
     @"fm = objc.create('FooManager')"
     @"t = {}\n"
     @"t.a='Foo'\n"
     @"t.fooManager_didFired = function(fm, a) t.a=a; end\n"
     @"t.fooManager_floatValueOf = function(fm, a) return a*2; end\n"
     @"r = objc.mkref(t)\n"
     @"if r:adoptsProtocol('FooManagerDelegate') then\n"
     @"  fm:setDelegate(r)\n"
     @"  fm:fireAction('Lomo')\n"
     @"end\n"
     @"return t"
               rvalues:&rval
               options:LuaKitOptionsTable
                 error:&err];
    

    XCTAssertTrue(rval.count && [rval.firstObject isKindOfClass:[NSDictionary class]]);
    
    NSDictionary *ditc = rval.firstObject;
    XCTAssertEqualObjects(ditc[@"a"], @"Lomo/84");
    
}

@end
