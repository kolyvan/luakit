//
//  LuaState.h
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 05.04.15.
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

#import "LuaUtils.h"

@protocol LuaStateDelegate;

@interface LuaState : NSObject

@property (readwrite, nonatomic, weak) id<LuaStateDelegate> delegate;
@property (readwrite, nonatomic, strong) NSArray *packagePaths;

+ (LuaState *) lookupLuaState:(lua_State *)L;

- (lua_State *) state;

- (void) tearDown;

- (BOOL) runChunk:(NSString *)chunk
            error:(NSError **)outError;

- (BOOL) runChunk:(NSString *)chunk
          rvalues:(NSArray **)rvalues
          options:(LuaKitOptions)options
            error:(NSError **)outError;

- (BOOL) runFunctionNamed:(NSString *)name
                    error:(NSError **)outError;

- (BOOL) runFunctionNamed:(NSString *)name
                arguments:(NSArray *)arguments
                  rvalues:(NSArray **)rvalues
                  options:(LuaKitOptions)options
                    error:(NSError **)outError;

- (BOOL) runFile:(NSString *)path
        binCache:(NSString *)binCache
         rvalues:(NSArray **)rvalues
         options:(LuaKitOptions)options
           error:(NSError **)outError;

- (NSNumber *) numberNamed:(NSString *)name;
- (NSString *) stringNamed:(NSString *)name;
- (id) tableNamed:(NSString *)name; // dictionary or array

- (id) valueNamed:(NSString *)name
          options:(LuaKitOptions)options;

- (void) setNamed:(NSString *)name
        withValue:(id)val
          options:(LuaKitOptions)options;

+ (NSString *) versionString;
- (NSUInteger) memoryUsedInKB;
- (void) collectGarbage;
- (void) setPackagePaths:(NSArray *)paths;

@end

//////////

@protocol LuaStateDelegate <NSObject>

@optional

- (void) luaState:(LuaState *)state printText:(NSString *)text;

@end
