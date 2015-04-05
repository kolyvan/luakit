//
//  LuaUtils.h
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 24.03.15.

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

#import <Foundation/Foundation.h>

extern NSString * const LuaKitErrorDomain;
extern NSString * const LuaKitExceptionBadRVal;

enum {
    
    LuaKitErrorCompile = 1,
    LuaKitErrorSyntaxIncomplete,
    LuaKitErrorRunChunk,
    LuaKitErrorRunFunction,
    LuaKitErrorBadName,
    LuaKitErrorBadArgument,
    LuaKitErrorNotTable,
    LuaKitErrorBadState,
};

typedef NS_OPTIONS(NSUInteger, LuaKitOptions) {
    
    LuaKitOptionsNone  = 0,
    LuaKitOptionsTable = 1 << 0,  // convert lua table into NSDictionay or NSArray
};

typedef struct lua_State lua_State;

////////////////////////////////////////////////////////////////////////////////////////////////////

@interface LuaObjectRef : NSObject
- (NSString *) typeName;
- (id) takeValue;
@end

@interface LuaTableRef : LuaObjectRef

- (BOOL) callMethod:(NSString *)name
          arguments:(NSArray *)arguments
            rvalues:(NSArray **)rvalues
            options:(LuaKitOptions)options
              error:(NSError **)outError;

- (id) valueNamed:(NSString *)name
          options:(LuaKitOptions)options;

- (void) setNamed:(NSString *)name
        withValue:(id)val
          options:(LuaKitOptions)options;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////

extern NSString *luakit_fieldsOfObjCType(const char *objCType);
extern NSString *luakit_luaNameFromObjcMethodName(NSString *name);
extern NSArray *luakit_luaNamesForObject(id object, BOOL isMethods);

extern NSString * luakit_getErrorMessage(lua_State *L, int errCode);
extern NSError *luakit_errorWithCode(NSUInteger code, NSString *reason);
extern id luakit_valueWithIndex(lua_State *L, int index, LuaKitOptions options);
extern BOOL luakit_pushValue(lua_State *L, id obj, LuaKitOptions options);
extern BOOL luakit_pushTable(lua_State *L, NSDictionary *dict);
extern BOOL luakit_pushSequence(lua_State *L, NSArray *array);
extern BOOL luakit_pushObject(lua_State *L, id obj);
extern BOOL luakit_pushRawObject(lua_State *L, id obj);
extern BOOL luakit_callFunction(lua_State *L, NSArray *arguments, NSArray **rvalues, LuaKitOptions options, NSError **outError);
extern id luakit_tableWithIndex(lua_State *L, int index);
extern void luakit_pushargerrmsg(lua_State *L, int arg, const char *tname, const char *funcname);
extern NSDictionary *luakit_fieldsInTable(lua_State *L, NSString *name);
extern id luakit_objectForUserdata(lua_State *L, NSString *name);

#ifdef DEBUG
extern void luakit_debugDumpStack(lua_State *L);
#endif