//
//  LuaObjc.m
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

#import "LuaObjc.h"
#import "LuaUtils.h"
#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

const char *const luaobjc_kMetaTableKeyObject = "luakit.object";
const char *const luaobjc_kMetaTableKeyClass = "luakit.class";

#ifdef STORE_USERDATE_OBJECT
const char *const luaobjc_kUserdatasTable = "luakit.userdatas";
const char *const luaobjc_kUserdatasTableMeta = "luakit.userdatas.meta";
const char luaobjc_kUserDatumBridgeRetainedKey;
#endif

#ifdef DEBUG
#define ASSERT_STACK_IS_EMPTY(L)  assert(lua_gettop(L) == 0)
#else
#define ASSERT_STACK_IS_EMPTY(L)
#endif

#ifdef DEBUG
#define DebugLog(frmt, ...)  NSLog(frmt, __VA_ARGS__)
#else
#define DebugLog(frmt, ...)
#endif

static int lua_objc_object_finalize(lua_State *L);
static int lua_objc_object_index(lua_State *L);
static int lua_objc_object_newindex(lua_State *L);
static int lua_objc_object_callmethod(lua_State *L);
static int lua_objc_wrap(lua_State *L);
static int lua_objc_unwrap(lua_State *L);
static int lua_objc_tostring(lua_State *L);
static int lua_objc_pack(lua_State *L);
static int lua_objc_unpack(lua_State *L);
static int lua_objc_cgsize(lua_State *L);
static int lua_objc_cgpoint(lua_State *L);
static int lua_objc_cgrect(lua_State *L);
static int lua_objc_nsrange(lua_State *L);
static int lua_objc_uioffset(lua_State *L);
static int lua_objc_uiedgeinsets(lua_State *L);
static int lua_objc_class(lua_State *L);
static int lua_objc_create(lua_State *L);
static int lua_objc_alloc(lua_State *L);
static int lua_objc_mkref(lua_State *L);
static int lua_objc_sweep(lua_State *L);

static const struct luaL_Reg objc_functions [] = {
    {"wrap",    lua_objc_wrap},     // convert lua table to NSDictionary or NSArray
    {"unwrap",  lua_objc_unwrap},   // convert NSDictionary/NSArray to lua table
    {"tostring",lua_objc_tostring},
    {"pack",    lua_objc_pack},     // pack args as struct
    {"unpack",  lua_objc_unpack},   // unpack struct to multiple return values
    {"cgsize",  lua_objc_cgsize},
    {"cgpoint", lua_objc_cgpoint},
    {"cgrect",  lua_objc_cgrect},
    {"nsrange", lua_objc_nsrange},
    {"uioffset",lua_objc_uioffset},
    {"uiedgeinsets", lua_objc_uiedgeinsets},
    {"class",   lua_objc_class},  // returns Class by name
    {"create",  lua_objc_create}, // allocs an object and calls init method
    {"alloc",   lua_objc_alloc},  // allocs an object
    {"mkref",   lua_objc_mkref},  // makes lua table as LuaOjbRef object, useful in case of delegate
    {"sweep",   lua_objc_sweep},  // clean object's userdata
    {NULL, NULL}
};

//////////

@interface LuaObjectRef()
- (instancetype) initWithState:(lua_State *)L;
- (void) mkref:(int)idx;
- (BOOL) push;
@end

//////////

extern void luaobjc_loadModule(lua_State *L)
{
    // load objc funcs
    luaL_newlib(L, objc_functions);
    lua_setglobal(L, "objc");
    
    // register metatables
    
    if (luaL_newmetatable(L, luaobjc_kMetaTableKeyObject)) {
        
        lua_pushstring(L, "__gc");
        lua_pushcfunction(L, lua_objc_object_finalize);
        lua_settable(L, -3);
        
        lua_pushstring(L, "__newindex");
        lua_pushcfunction(L, lua_objc_object_newindex);
        lua_settable(L, -3);
        
        lua_pushstring(L, "__index");
        lua_pushcfunction(L, lua_objc_object_index);
        lua_settable(L, -3);
        
        lua_pop(L, 1);
    }
    
    if (luaL_newmetatable(L, luaobjc_kMetaTableKeyClass)) {
        
        lua_pushstring(L, "__newindex");
        lua_pushcfunction(L, lua_objc_object_newindex);
        lua_settable(L, -3);
        
        lua_pushstring(L, "__index");
        lua_pushcfunction(L, lua_objc_object_index);
        lua_settable(L, -3);
        
        lua_pop(L, 1);
    }
    
#ifdef STORE_USERDATE_OBJECT
    // create weak objects to userdata table
    lua_newtable(L);
    lua_pushstring(L, luaobjc_kUserdatasTable);
    lua_setfield(L, -2, "__name");
    
    if (luaL_newmetatable(L, luaobjc_kUserdatasTableMeta)) {
        
        lua_pushliteral(L, "__mode");
        lua_pushliteral(L, "v");
        lua_settable(L, -3);
    }
    
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, luaobjc_kUserdatasTable);
#endif
    
    ASSERT_STACK_IS_EMPTY(L);
}

#pragma mark - metatable functions

static int lua_objc_object_finalize(lua_State *L)
{
    void *p = lua_touserdata(L, 1);
    void **ptr = (void**)p;
    if (*ptr) {
        id obj = (__bridge_transfer id)*ptr;
        //CFBridgingRelease(*ptr);
        //DebugLog(@"lua finalize %@ %p", [obj class], obj);
        *ptr = NULL;
        
#ifdef STORE_USERDATE_OBJECT
        luaobjc_breakAssocUserdata(L, obj);
#endif
    }
    return 0;
}

static int lua_objc_object_newindex_impl(lua_State *L)
{
    id obj = luakit_valueWithIndex(L, -3, 0);
    id key = luakit_valueWithIndex(L, -2, 0);
    id val = luakit_valueWithIndex(L, -1, 0);
    
    if (!obj) {
        lua_pushliteral(L, "nil object");
        return -1;
    }
    
    if (![key isKindOfClass:[NSString class]]) {
        lua_pushliteral(L, "key is not string");
        return -1;
    }
    
    // create a selector's name for setMethod
    NSMutableString *setName = [NSMutableString stringWithString:@"set"];
    [setName appendString: [key substringToIndex:1].uppercaseString];
    if ([key length] > 1) {
        [setName appendString: [key substringFromIndex:1]];
    }
    [setName appendString:@":"];
    
    if (![obj respondsToSelector:NSSelectorFromString(setName)]) {
        
        if ([obj respondsToSelector:NSSelectorFromString(key)]) {
            lua_pushfstring(L, "readonly '%s'", [key UTF8String]);
        } else {
            lua_pushfstring(L, "not implemeted '%s'", [key UTF8String]);
        }
        
        return -1;
    }
    
    NSError *err;
    if (![obj validateValue:&val forKey:key error:&err]) {
        
        lua_pushfstring(L, "validation failed for '%s' (%s)",
                        [key UTF8String],
                        err.localizedDescription.UTF8String);
        return -1;
    }
    
    @try {
        [obj setValue:val forKey:key];
    } @catch (NSException *exception) {
#ifdef DEBUG
        NSLog(@"catch KVC exception: %@", exception);
#endif
        lua_pushstring(L, exception.reason.UTF8String);
        return -1;
    }
    
    return 0;
}

static int lua_objc_object_newindex(lua_State *L)
{
    const int top = lua_gettop(L);
    if (top != 3) {
        
        luaL_error(L, "internal failure");
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_object_newindex_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return 0;
}

static int lua_objc_object_index_impl(lua_State *L)
{
    id obj = luakit_valueWithIndex(L, -2, 0);
    id key = luakit_valueWithIndex(L, -1, 0);
    
    if (!obj) {
        lua_pushliteral(L, "nil object");
        return -1;
    }
    
    if (![key isKindOfClass:[NSString class]]) {
        lua_pushliteral(L, "key is not string");
        return -1;
    }
    
    objc_property_t property = class_getProperty([obj class], [key UTF8String]);
    if (property) {
        
        id rval = [obj valueForKey:key];
        if (luakit_pushValue(L, rval, 0)) {
            return 1;
        } else {
            lua_pushfstring(L, "bad value of '%s'", [key UTF8String]);
            return -1;
        }
        
    } else {
        
        // it's a method,
        // so push the closure (and the name as upvalue) for calling it later
        lua_pushvalue(L, -1);
        lua_pushcclosure(L, lua_objc_object_callmethod,1);
        return 1;
    }
}

static int lua_objc_object_index(lua_State *L)
{
    const int top = lua_gettop(L);
    if (top != 2) {
        luaL_error(L, "internal failure");
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_object_index_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_object_callmethod_impl(lua_State *L, id obj, NSString *key, int argIdx)
{
    NSString *selName = key;
    
    if ([selName rangeOfString:@"_"].location != NSNotFound) {
        selName = [selName stringByReplacingOccurrencesOfString:@"_" withString:@":"];
    }
    
    const int top = lua_gettop(L);
    if (top >= argIdx) {
        selName = [selName stringByAppendingString:@":"];
    }
    
    SEL sel = NSSelectorFromString(selName);
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig) {
        lua_pushfstring(L, "not impemented '%s'", selName.UTF8String);
        return -1;
    }
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    if (!invocation){
        lua_pushliteral(L, "unable to create NSInvocation");
        return -1;
    }
    
    [invocation retainArguments];
    
    const NSUInteger numArgs = [sig numberOfArguments];
    if (numArgs > 2) {
        
        if ((top - argIdx + 1) != (numArgs - 2)) {
            lua_pushfstring(L, "wrong number of arguments (%d expected)", (int)numArgs-2);
            return -1;
        }
        
#define CASE_NUMBER(C, T) case C: {                 \
T val;                                          \
if (lua_isboolean(L, argIdx)) {                 \
val = (T)(lua_toboolean(L, argIdx) ? 1 : 0);\
} else if (lua_isinteger(L, argIdx)) {          \
val = (T)lua_tointeger(L, argIdx);          \
} else if (lua_isnumber(L, argIdx)) {           \
val = (T)lua_tonumber(L, argIdx);           \
} else {                                        \
luakit_pushargerrmsg(L, argIdx, #T, key.UTF8String);  \
return -1;                                  \
}                                               \
[invocation setArgument:&val atIndex:i];        \
break;                                          \
}
        for (int i = 2; i < numArgs; ++i) {
            
            const char *T = [sig getArgumentTypeAtIndex:i];
            
            switch (*T) {
                    
                    CASE_NUMBER(_C_CHR, char)
                    CASE_NUMBER(_C_UCHR, unsigned char)
                    CASE_NUMBER(_C_INT, int)
                    CASE_NUMBER(_C_UINT, unsigned int)
                    CASE_NUMBER(_C_SHT, short)
                    CASE_NUMBER(_C_USHT, unsigned short)
                    CASE_NUMBER(_C_LNG, long)
                    CASE_NUMBER(_C_ULNG, unsigned long)
                    CASE_NUMBER(_C_LNG_LNG, long long)
                    CASE_NUMBER(_C_ULNG_LNG, unsigned long long)
                    CASE_NUMBER(_C_FLT, float)
                    CASE_NUMBER(_C_DBL, double)
                    
                case _C_BOOL: {
                    
                    _Bool val;
                    if (lua_isboolean(L, argIdx)) {
                        val = (_Bool)(lua_toboolean(L, argIdx) ? 1 : 0);
                    } else if (lua_isinteger(L, argIdx)) {
                        val = (_Bool)(lua_tointeger(L, argIdx) ? 1 : 0);
                    } else if (lua_isnumber(L, argIdx)) {
                        val = (_Bool)(lua_tonumber(L, argIdx) ? 1 : 0);
                    } else {
                        luakit_pushargerrmsg(L, argIdx, "_Bool", key.UTF8String);
                        return -1;
                    }
                    [invocation setArgument:&val atIndex:i];
                    break;
                }
                    
                case _C_STRUCT_B: {
                    
                    id obj = luakit_valueWithIndex(L, argIdx, 0);
                    if ([obj isKindOfClass:[NSValue class]]) {
                        
                        NSValue *val = obj;
                        
                        NSUInteger valSize, argSize;
                        NSGetSizeAndAlignment(val.objCType, &valSize, NULL);
                        NSGetSizeAndAlignment(T, &argSize, NULL);
                        
                        if (valSize != argSize) {
                            
                            luakit_pushargerrmsg(L, argIdx, T, key.UTF8String);
                            return -1;
                        }
                        
                        void *buffer = malloc(argSize);
                        
                        if (buffer) {
                            
                            bzero(buffer, argSize);
                            [val getValue:buffer];
                            [invocation setArgument:buffer atIndex:i];
                            free(buffer);
                            
                        } else {
                            
                            lua_pushliteral(L, "out of memory");
                            return -1;
                        }
                        
                    } else {
                        
                        luakit_pushargerrmsg(L, argIdx, T, key.UTF8String);
                        return -1;
                    }
                    
                    break;
                }
                    
                case _C_ID: {
                    
                    id obj = luakit_valueWithIndex(L, argIdx, 0);
                    [invocation setArgument:&obj atIndex:i];
                    break;
                }
                    
                case _C_SEL: {
                    
                    id obj = luakit_valueWithIndex(L, argIdx, 0);
                    if ([obj isKindOfClass:[NSString class]]) {
                        
                        SEL sel = sel_getUid([obj UTF8String]);
                        [invocation setArgument:&sel atIndex:i];
                    } else {
                        
                        luakit_pushargerrmsg(L, argIdx, "string", key.UTF8String);
                        return -1;
                    }
                    break;
                }
                    
                default:
                    luakit_pushargerrmsg(L, argIdx, T, key.UTF8String);
                    return -1;
            }
            
            argIdx += 1;
        }
        
#undef CASE_NUMBER
    }
    
    invocation.selector = sel;
    invocation.target = obj;
    
    @try {
        [invocation invoke];
    }
    @catch (NSException *exception) {
        
        lua_pushstring(L, exception.reason.UTF8String);
        return -1;
    }
    
    const char *rType = [sig methodReturnType];
    if (!rType || *rType == _C_VOID) {
        return 0;
    }
    
    const size_t size = [sig methodReturnLength];
    if (!size) {
        return 0;
    }
    
    int result = 1;
    
#define CASE_NUMBER(C, T, Func, LF) case C: {   \
T val = 0;                                  \
[invocation getReturnValue:&val];           \
Func(L, (LF)val);                           \
break;                                      \
}
    
    switch (*rType) {
            
            CASE_NUMBER(_C_CHR, char, lua_pushboolean, int)
            CASE_NUMBER(_C_UCHR, unsigned char, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_INT, int, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_UINT, unsigned int, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_LNG, long, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_ULNG, unsigned long, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_LNG_LNG, long long, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_ULNG_LNG, unsigned long long, lua_pushinteger, lua_Integer)
            CASE_NUMBER(_C_FLT, float, lua_pushnumber, lua_Number)
            CASE_NUMBER(_C_DBL, double, lua_pushnumber, lua_Number)
            CASE_NUMBER(_C_BOOL, _Bool, lua_pushboolean, int)
            
        case _C_STRUCT_B: {
            
            void *buffer = malloc(size);
            if (!buffer) {
                lua_pushliteral(L, "out of memory");
                return -1;
            }
            
            bzero(buffer, size);
            
            [invocation getReturnValue:buffer];
            
            NSValue *val = [[NSValue alloc] initWithBytes:buffer objCType:rType];
            result = luakit_pushObject(L, val);
            
            free(buffer);
            
            break;
        }
            
        case _C_ID: {
            
            id obj; CFTypeRef ref = NULL;
            [invocation getReturnValue:&ref];
            if (ref) {
                if ([key hasPrefix:@"alloc"] ||
                    [key hasPrefix:@"new"] ||
                    [key hasPrefix:@"copy"] ||
                    [key hasPrefix:@"mutableCopy"])
                {
                    obj = (__bridge_transfer id)ref;
                } else {
                    obj = (__bridge id)ref;
                }
            }
            
            result = luakit_pushValue(L, obj, 0);
            break;
        }
            
        case _C_CLASS: {
            
            id obj;
            [invocation getReturnValue:&obj];
            result = luakit_pushValue(L, obj, 0);
            break;
        }
            
        case _C_SEL: {
            
            SEL sel;
            [invocation getReturnValue:&sel];
            id obj = sel ? NSStringFromSelector(sel) : nil;
            result = luakit_pushValue(L, obj, 0);
            break;
        }
            
        default:
            lua_pushfstring(L, "unsupported rval for '%s' (%s)", key.UTF8String, rType);
            result = -1;
            break;
    }
    
#undef CASE_NUMBER
    
    return result;
}

static int lua_objc_object_callmethod(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        luaL_error(L, "internal failure");
        return 0;
    }
    
    const int upval = lua_upvalueindex(1);
    if (!lua_isstring(L, upval)) {
        luaL_error(L, "bad value of method's name");
        return 0;
    }
    
    int r;
    @autoreleasepool {
        
        id obj = luakit_valueWithIndex(L, 1, 0);
        if (obj) {
            
            const char *s = lua_tostring(L, upval);
            NSString *key = [NSString stringWithUTF8String:s];
            r = lua_objc_object_callmethod_impl(L, obj, key, 2);
            
        } else {
            
            lua_pushliteral(L, "bad callee");
            r = -1;
        }
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

////////////////////////////////////////////////////////////////////////////////////////////////////

#pragma mark - objc functions

static int lua_objc_wrap_impl(lua_State *L)
{
    // table -> userdata (nsdictionary or nsarray)
    // other -> pass
    
    const int T = lua_type(L, -1);
    
    switch(T){
            
        case LUA_TTABLE: {
            
            id obj = luakit_tableWithIndex(L, -1);
            if (luakit_pushObject(L, obj)) {
                return 1;
            } else {
                lua_pushliteral(L, "unable wrap table");
                return -1;
            }
            
            break;
        }
            
        default:
            break;
    }
    
    // pass
    lua_pushvalue(L, -1);
    return 1;
}

static int lua_objc_wrap(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_wrap_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_unwrap_impl(lua_State *L)
{
    // userdata
    //    nsdictionary/nsarray -> table
    //    LuaObjectRef -> get reference
    //    null -> nil
    
    const int T = lua_type(L, -1);
    
    switch(T){
            
        case LUA_TUSERDATA: {
            
            void *p = luaL_testudata(L, -1, luaobjc_kMetaTableKeyObject);
            if (p) {
                
                void **ptr = (void**)p;
                id obj = (__bridge id)*ptr;
                
                if ([obj isKindOfClass:[NSDictionary class]]) {
                    if (luakit_pushTable(L, obj)) {
                        return 1;
                    }
                } else if ([obj isKindOfClass:[NSArray class]]) {
                    if (luakit_pushSequence(L, obj)) {
                        return 1;
                    }
                    
                } else if ([obj isKindOfClass:[LuaObjectRef class]]) {
                    if ([(LuaObjectRef *)obj push]) {
                        return 1;
                    }
                } else if (!obj || [obj isKindOfClass:[NSNull class]]) {
                    lua_pushnil(L);
                    return 1;
                }
                
            } else {
                
                luakit_pushargerrmsg(L, -1, "object", "objc.unwrap");
                return -1;
            }
            
            break;
        }
            
        default:
            break;
    }
    
    // pass
    lua_pushvalue(L, -1);
    return 1;
}

static int lua_objc_unwrap(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_unwrap_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_tostring_impl(lua_State *L)
{
    const int top = lua_gettop(L);
    if (top) {
        
        NSString *string;
        const int T = lua_type(L, -1);
        switch(T) {
                
            case LUA_TNUMBER:
            case LUA_TBOOLEAN:
            case LUA_TSTRING:
            case LUA_TTABLE: {
                id val = luakit_valueWithIndex(L, -1, LuaKitOptionsTable);
                string = [val description];
                break;
            }
                
            case LUA_TUSERDATA: {
                
                void *p = luaL_testudata(L, -1, luaobjc_kMetaTableKeyObject);
                if (p) {
                    
                    void **ptr = (void**)p;
                    id val = (__bridge id)*ptr;
                    string = [val description];
                    
                } else {
                    
                    void *p = luaL_testudata(L, -1, luaobjc_kMetaTableKeyClass);
                    if (p) {
                        
                        void **ptr = (void**)p;
                        id val = (__bridge id)*ptr;
                        string = [val description];
                        
                    } else {
                        string = @"userdata";
                        //luakit_pushargerrmsg(L, -1, "object", "objc.tostring");
                        //return -1;
                    }
                }
                break;
            }
                
            case LUA_TFUNCTION:
                string = @"function";
                break;
                
            case LUA_TTHREAD:
                string = @"thread";
                break;
                
            case LUA_TLIGHTUSERDATA:
                string = @"lightuserdata";
                break;
                
            case LUA_TNIL:
                string = @"nil";
                break;
                
            default:
                break;
        }
        
        if (string) {
            lua_pushstring(L, string.UTF8String);
            return 1;
        }
    }
    
    return 0;
}

static int lua_objc_tostring(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_tostring_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_pack_impl(lua_State *L,
                              int index,
                              int top,
                              const char *objCType)
{
    NSString *fields = luakit_fieldsOfObjCType(objCType);
    
    if (!fields ||
        fields.length != (top - index + 1)) {
        lua_pushfstring(L, "bad encoded type (%s)", objCType);
        return -1;
    }
    
    NSUInteger size;
    NSGetSizeAndAlignment(objCType, &size, NULL);
    if (!size) {
        return 0;
    }
    
    void *buffer = malloc(size);
    if (!buffer) {
        lua_pushliteral(L, "out of memory");
        return -1;
    }
    
    int result = 0;
    int num = 0;
    char *pbuf = (char *)buffer;
    
#define CASE_NUMBER(C, T) case C: {     \
T val;                              \
if (lua_isboolean(L, i)) {          \
val = (T)lua_toboolean(L, i);   \
} else if (lua_isinteger(L, i)) {   \
val = (T)lua_tointeger(L, i);   \
} else if (lua_isnumber(L, i)) {    \
val = (T)lua_tonumber(L, i);    \
} else {                            \
luakit_pushargerrmsg(L, i, #T, "objc.pack"); \
result = -1;                    \
goto cleanup;                   \
}                                   \
*(T *)pbuf = val;                   \
pbuf += sizeof(T);                  \
++num;                              \
break;                              \
}
    
    for (int i = index; i <= top; ++i) {
        
        const char t = (char)[fields characterAtIndex:i-index];
        
        switch (t) {
                
                CASE_NUMBER(_C_CHR, char)
                CASE_NUMBER(_C_UCHR, unsigned char)
                CASE_NUMBER(_C_INT, int)
                CASE_NUMBER(_C_UINT, unsigned int)
                CASE_NUMBER(_C_SHT, short)
                CASE_NUMBER(_C_USHT, unsigned short)
                CASE_NUMBER(_C_LNG, long)
                CASE_NUMBER(_C_ULNG, unsigned long)
                CASE_NUMBER(_C_LNG_LNG, long long)
                CASE_NUMBER(_C_ULNG_LNG, unsigned long long)
                CASE_NUMBER(_C_FLT, float)
                CASE_NUMBER(_C_DBL, double)
                
            case _C_BOOL: {
                
                _Bool val;
                if (lua_isboolean(L, i)) {
                    val = (_Bool)(lua_toboolean(L, i) ? 1 : 0);
                } else if (lua_isinteger(L, i)) {
                    val = (_Bool)(lua_tointeger(L, i)  ? 1 : 0);
                } else if (lua_isnumber(L, i)) {
                    val = (_Bool)(lua_tonumber(L, i)  ? 1 : 0);
                } else {
                    luakit_pushargerrmsg(L, i, "_Bool", "objc.pack");
                    result = -1;
                    goto cleanup;
                }
                *(_Bool *)pbuf = val;
                pbuf += sizeof(_Bool);
                ++num;
                break;
            }
                
            default:
                lua_pushfstring(L, "bad encoded type (%s)", objCType);
                result = -1;
                goto cleanup;
        }
    }
    
#undef CASE_NUMBER
    
    if (num) {
        NSValue *val = [NSValue valueWithBytes:buffer objCType:objCType];
        if (val && luakit_pushObject(L, val)) {
            result = 1;
        }
    }
    
cleanup:
    free(buffer);
    
    return result;
}

static int lua_objc_pack(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    const char *objCType = NULL;
    if (lua_isstring(L, 1)) {
        objCType = lua_tostring(L, 1);
    }
    
    if (!objCType) {
        luaL_error(L, "bad encoded type");
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_pack_impl(L, 2, top, objCType);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_type_impl(lua_State *L, const char *objCType)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_pack_impl(L, 1, top, objCType);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_cgsize(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(CGSize));
}

static int lua_objc_cgpoint(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(CGPoint));
}

static int lua_objc_cgrect(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(CGRect));
}

static int lua_objc_nsrange(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(NSRange));
}

static int lua_objc_uioffset(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(UIOffset));
}

static int lua_objc_uiedgeinsets(lua_State *L)
{
    return lua_objc_type_impl(L, @encode(UIEdgeInsets));
}

static int lua_objc_unpack_impl(lua_State *L, void *p)
{
    // unpacks nsvalue to multiple returns
    
    void **ptr = (void**)p;
    id obj = (__bridge id)*ptr;
    if (![obj isKindOfClass:[NSValue class]]) {
        luakit_pushargerrmsg(L, 1, "nsvalue", "objc.unpack");
        return -1;
    }
    
    NSValue *val = obj;
    
    NSString *fields = luakit_fieldsOfObjCType(val.objCType);
    if (!fields.length) {
        return 0;
    }
    
    NSUInteger size;
    NSGetSizeAndAlignment(val.objCType, &size, NULL);
    
    void *buffer = malloc(size);
    if (!buffer) {
        lua_pushliteral(L, "out of memory");
        return -1;
    }
    
    bzero(buffer, size);
    [val getValue:buffer];
    
    int num = 0;
    char *pbuf = (char *)buffer;
    
#define CASE_NUMBER(C, T, Func, LF) case C: {       \
Func(L, (LF)(*(T *)pbuf));                      \
pbuf += sizeof(T);                              \
++num;                                          \
break;                                          \
}
    
    for (NSUInteger i = 0; i < fields.length; ++i) {
        
        const char c = (char)[fields characterAtIndex:i];
        
        switch (c) {
                
                CASE_NUMBER(_C_UCHR, unsigned char, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_INT, int, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_UINT, unsigned int, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_SHT, short, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_USHT, unsigned short, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_LNG, long, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_ULNG, unsigned long, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_LNG_LNG, long long, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_ULNG_LNG, unsigned long long, lua_pushinteger, lua_Integer)
                CASE_NUMBER(_C_FLT, float, lua_pushnumber, lua_Number)
                CASE_NUMBER(_C_DBL, double, lua_pushnumber, lua_Number)
                
            case _C_CHR:
                lua_pushboolean(L, (*(char *)pbuf) ? 1 : 0);
                pbuf += sizeof(char);
                ++num;
                break;
                
            case _C_BOOL:
                lua_pushboolean(L, (*(_Bool *)pbuf) ? 1 : 0);
                pbuf += sizeof(_Bool);
                ++num;
                break;
                
            default:
                break;
        }
    }
    
#undef CASE_NUMBER
    
    free(buffer);
    
    return num;
}

static int lua_objc_unpack(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    void *p = luaL_checkudata(L, top, luaobjc_kMetaTableKeyObject);
    if (!p) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_unpack_impl(L, p);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_class(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    const char *name = luaL_checkstring(L, -1);
    if (!name) {
        return 0;
    }
    
    Class klass = objc_lookUpClass(name);
    if (!klass) {
        lua_pushnil(L);
        lua_pushfstring(L, "bad classname '%s'", name);
        return 2;
    }
    
    if (luakit_pushObject(L, (id)klass)) {
        return 1;
    }
    
    return 0;
}

static int lua_objc_create(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    const char *name = luaL_checkstring(L, 1);
    if (!name) {
        return 0;
    }
    
    Class klass = objc_lookUpClass(name);
    if (!klass) {
        lua_pushnil(L);
        lua_pushfstring(L, "bad classname '%s'", name);
        return 2;
    }
    
    id p = [klass alloc];
    if (!p) {
        luaL_error(L, "out of memory");
        return 0;
    }
    
    if (top > 1) {
        
        const char *s = luaL_checkstring(L, 2);
        if (!s) {
            return 0;
        }
        NSString *key = [NSString stringWithUTF8String:s];
        
        int r;
        @autoreleasepool {
            r = lua_objc_object_callmethod_impl(L, p, key, 3);
        }
        if (r < 0) {
            lua_error(L);
        }
        return r;
        
    }
    
    p = [p init];
    if (!p) {
        lua_pushnil(L);
        lua_pushfstring(L, "initialization failed");
        return 2;
    }
    
    if (luakit_pushObject(L, p)) {
        return 1;
    } else {
        luaL_error(L, "unsupported class '%s'", name);
        return 0;
    }
}

static int lua_objc_alloc(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    const char *name = luaL_checkstring(L, 1);
    if (!name) {
        return 0;
    }
    
    Class klass = objc_lookUpClass(name);
    if (!klass) {
        lua_pushnil(L);
        lua_pushfstring(L, "bad class '%s'", name);
        return 2;
    }
    
    id p = [klass alloc];
    if (!p) {
        luaL_error(L, "out of memory");
        return 0;
    }
    
    if (luakit_pushObject(L, p)) {
        return 1;
    } else {
        luaL_error(L, "unsupported class '%s'", name);
        return 0;
    }
}

static int lua_objc_mkref_impl(lua_State *L)
{
    // table -> luatableref
    // other -> pass
    
    const int T = lua_type(L, -1);
    
    switch(T){
            
        case LUA_TTABLE: {
            
            LuaTableRef *p = [[LuaTableRef alloc] initWithState:L];
            [p mkref:-1];
            
            if (luakit_pushRawObject(L, p)) {
                return 1;
            } else {
                lua_pushliteral(L, "unable mkref table");
                return -1;
            }
        }
            
        default:
            break;
    }
    
    // pass
    lua_pushvalue(L, -1);
    return 1;
}

static int lua_objc_mkref(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    int r;
    @autoreleasepool {
        r = lua_objc_mkref_impl(L);
    }
    if (r < 0) {
        lua_error(L);
    }
    return r;
}

static int lua_objc_sweep(lua_State *L)
{
    const int top = lua_gettop(L);
    if (!top) {
        return 0;
    }
    
    const void *userdata = luaL_testudata(L, -1, luaobjc_kMetaTableKeyObject);
    if (!userdata) {
        return 0;
    }
    
    void **ptr = (void **)userdata;
    if (!*ptr) {
        return 0;
    }
    
    id obj = (__bridge_transfer id)*ptr;
    *ptr = NULL;
    
#ifdef STORE_USERDATE_OBJECT
    luaobjc_breakAssocUserdata(L, obj);
#endif
    
    // clear metatable
    lua_pushnil(L);
    lua_setmetatable(L, -2);
    
    lua_pop(L, 1); // pop userdate
    lua_pushnil(L);
    
    return 1;
}

#ifdef STORE_USERDATE_OBJECT

// break association of the object and the userdata
void luaobjc_breakAssocUserdata(lua_State *L, id obj)
{
    NSNumber *num = objc_getAssociatedObject(obj, &luaobjc_kUserDatumBridgeRetainedKey);
    if (num) {
        
        //DebugLog(@"remove assoc userdata (%d) %@ %p", num.intValue, [obj class], obj);
        
        objc_setAssociatedObject(obj, &luaobjc_kUserDatumBridgeRetainedKey, nil, OBJC_ASSOCIATION_ASSIGN);
        
        lua_getfield(L, LUA_REGISTRYINDEX, luaobjc_kUserdatasTable); // push table
        if (lua_istable(L, -1)) {
            
            // remove from table
            lua_pushinteger(L, num.intValue);
            lua_pushnil(L);
            lua_rawset(L, -3);
            
            lua_pop(L, 1);
        }
    }
}

void luaobjc_sweepObject(lua_State *L, id obj)
{
    NSNumber *num = objc_getAssociatedObject(obj, &luaobjc_kUserDatumBridgeRetainedKey);
    if (!num) {
        return;
    }
    
    const int top = lua_gettop(L);
    
    lua_getfield(L, LUA_REGISTRYINDEX, luaobjc_kUserdatasTable);
    if (lua_istable(L, -1)) {
        // table
        lua_pushinteger(L, num.intValue);   // key
        lua_rawget(L, -2);
        
        if (lua_isuserdata(L, -1)) {
            
            void *userdata = lua_touserdata(L, -1);
            void **ptr = (void **)userdata;
            id p = (__bridge_transfer id)*ptr;
            *ptr = NULL;
            if (p != obj) {
                DebugLog(@"!!! bad assoc %p (%d) %@ %p", userdata, num.intValue, [obj class], obj);
            }
            
            // clear metatable
            lua_pushnil(L);
            lua_setmetatable(L, -2);
            
            lua_pop(L, 1);
        }
    }
    
    luaobjc_breakAssocUserdata(L, obj);
    
    lua_settop(L, top);
}
#endif