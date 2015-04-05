//
//  LuaUtils.h
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 24.03.15.
//  Copyright (c) 2015 Konstantin Bukreev. All rights reserved.
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
#import "LuaObjc.h"
#import "LuaState.h"
#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString * const LuaKitErrorDomain = @"com.kolyvan.luakit";
NSString * const LuaKitExceptionBadRVal = @"com.kolyvan.exception.badrval";

#ifdef DEBUG
#define DebugLog(frmt, ...)  NSLog(frmt, __VA_ARGS__)
#else
#define DebugLog(frmt, ...)
#endif

//////////

@interface LuaObjectRef()
@property (readonly, nonatomic) int reference;
@property (readonly, nonatomic) int objtype;
- (instancetype) initWithState:(lua_State *)L;
- (void) mkref:(int)idx;
- (void) unref;
- (BOOL) push;      // pushes lua reference on top of stack
@end

//////////

// copy of luaxlib typeerror/luaL_argerror functions

void luakit_pushargerrmsg(lua_State *L,
                          int arg,
                          const char *tname,
                          const char *funcname)
{
    if (arg < 0){
        arg = lua_gettop(L) + arg + 1;
    }
    
    const char *typearg;
    if (luaL_getmetafield(L, arg, "__name") == LUA_TSTRING) {
        typearg = lua_tostring(L, -1);
    } else if (lua_type(L, arg) == LUA_TLIGHTUSERDATA) {
        typearg = "light userdata";
    } else {
        typearg = luaL_typename(L, arg);
    }
    
    lua_Debug ar;
    if (lua_getstack(L, 0, &ar)) {
        
        lua_getinfo(L, "n", &ar);
        if (strcmp(ar.namewhat, "method") == 0) {
            arg--;  // do not count 'self'
            if (arg == 0)  { // error is in the self argument itself?
                
                lua_pushfstring(L, "calling '%s' on bad self (%s expected, got %s)",
                                ar.name, tname, typearg);
                return;
                
            }
        }
    }
    
    lua_pushfstring(L, "bad argument #%d to '%s' (%s expected, got %s)",
            arg, (ar.name ?: (funcname ?: "?")), tname, typearg);
}

NSString *luakit_fieldsOfObjCType(const char *objCType)
{
    // for arg '{CGRect={CGPoint=dd}{CGSize=dd}}' will return 'dddd'
    // error-prone, TODO: need improve and test
    
    if (!objCType) {
        return nil;
    }
    
    const char *ptr = strchr(objCType, '=');
    if (!ptr) {
        return nil;
    }
    ++ptr;
    
    const size_t len = strlen(ptr);
    char buffer[len];
    bzero(buffer, len);
    char *pbuf = buffer;
    
    while (ptr) {
        
        const char *p0 = strchr(ptr, '{');
        const char *p1 = strchr(ptr, '}');
        
        if (p0 && p0 < p1) {
            
            ptr = p0 + 1;
            
        } else if (p1) {
            
            const size_t len = p1-ptr;
            memcpy(pbuf, ptr, len);
            pbuf += len;
            ptr = p1 + 1;
        }
        
        ptr = strchr(ptr, '=');
        if (ptr) { ++ptr; }
    }
    
    if (pbuf == buffer) {
        return nil;
    }
    
    return [[NSString alloc] initWithBytes:buffer
                                    length:pbuf-buffer
                                  encoding:NSASCIIStringEncoding];;
    
}

NSString * luakit_luaNameFromObjcMethodName(NSString *name)
{
    if ([name hasPrefix:@"_"] ||
        [name hasSuffix:@"_"])
    {
        return nil; // skip private
    }
        
    if ([name hasSuffix:@":"]) {
        name = [name substringToIndex:name.length - 1];
    }
    return [name stringByReplacingOccurrencesOfString:@":" withString:@"_"];
}

static BOOL luakit_isProperArgumentOfObjcType(char type)
{
    switch (type) {
        case _C_ID: case _C_CLASS: case _C_SEL:
        case _C_CHR: case _C_UCHR: case _C_SHT: case _C_USHT:
        case _C_INT: case _C_UINT: case _C_LNG: case _C_ULNG:
        case _C_LNG_LNG: case _C_ULNG_LNG: case _C_FLT: case _C_DBL:
        case _C_BOOL: case _C_STRUCT_B:
            return YES;
        default:
            return NO;
    }
}

static BOOL luakit_verifyObjcMethod(Method method)
{
    char buffer[16];
    unsigned count = method_getNumberOfArguments(method);
    for (unsigned i = 0; i < count; ++i) { // self, _cmd skip
        
        bzero(buffer, sizeof(buffer));
        method_getArgumentType(method, i, buffer, sizeof(buffer) - 1);
        if (!luakit_isProperArgumentOfObjcType(buffer[0])) {
            return NO;
        }
    }
    return YES;
}

static BOOL luakit_verifyObjcProperty(objc_property_t property)
{
    const char *attrs = property_getAttributes(property);
    if (!attrs) {
        return NO;
    }
    
    const char *p0 = strchr(attrs, 'T');
    if (p0) {
        const char *p1 = strchr(p0, ',');
        if (p1 > p0) {
            const char type = *(p0 + 1);
            return luakit_isProperArgumentOfObjcType(type);
        }
    }
    return NO;
}

static void luakit_luaNamesForClass(Class klass, BOOL isMethods, NSMutableSet *result)
{
    static NSSet *blacklist;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blacklist = [NSSet setWithArray:@[@"dealloc", @"hash", @"isEqual", @"compare", @"description", @"descriptionWithLocale", @"encodeWithCoder", @"initWithCoder", @"classForCoder", @".cxx_destruct", @"retain", @"release", @"retainCount", @"allowsWeakReference", @"autorelease", @"copy", @"retainWeakReference", @"superclass"]];
        
    });
    
    if (isMethods) {
        
        unsigned count = 0;
        Method *methods = class_copyMethodList(klass, &count);
        if (methods) {
            
            for (unsigned int i = 0; i < count; ++i) {
                Method method = methods[i];
                if (luakit_verifyObjcMethod(method)) {
                    SEL sel = method_getName(method);
                    if (sel) {
                        NSString *name = NSStringFromSelector(sel);
                        name = luakit_luaNameFromObjcMethodName(name);
                        if (name && ![blacklist containsObject:name]) {
                            [result addObject:name];
                        }
                    }
                }
            }
            
            free(methods);
        }
        
    } else {
        
        unsigned count = 0;
        objc_property_t *properties = class_copyPropertyList(klass, &count);
        if (properties) {
            
            for (unsigned int i = 0; i < count; ++i) {
                
                objc_property_t property = properties[i];
                if (luakit_verifyObjcProperty(property)) {
                    const char *propname = property_getName(property);
                    if (propname) {
                        NSString *name = [NSString stringWithUTF8String:propname];
                        if (name &&
                            ![name hasPrefix:@"_"] &&
                            ![blacklist containsObject:name])
                        {
                            [result addObject:name];
                        }
                    }
                }
            }
            
            free(properties);
        }
    }
}

NSArray *luakit_luaNamesForObject(id object, BOOL isMethods)
{
    static NSMutableDictionary *cachedMethods;
    static NSMutableDictionary *cachedProperties;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedMethods = [NSMutableDictionary dictionary];
        cachedProperties = [NSMutableDictionary dictionary];
    });
    
    const BOOL isClass = object_isClass(object);
    Class klass = object_getClass(object); // class methods is case of object is class
    
    NSString *className = NSStringFromClass(klass);
    if (isClass) {
        className = [@"class_" stringByAppendingString:className];
    }
    
    id cachedResult;
    if (isMethods) {
        cachedResult = cachedMethods[className];
    } else {
        cachedResult = cachedProperties[className];
    }
    
    if (cachedResult) {
        return cachedResult;
    }
    
    NSMutableSet *mset = [NSMutableSet set];
    
    while (klass) {
    
        luakit_luaNamesForClass(klass, isMethods, mset);
        
        if (isClass) {
            break;
        }
        
        // take superclass methods
        klass = class_getSuperclass(klass);
        if (klass == [NSObject class]) {
            break;
        }
    }
    
    NSArray *result = mset.allObjects;
    
    if (isMethods) {
        cachedMethods[className] = result;
    } else {
        cachedProperties[className] = result;
    }
    
    return result.count ? result : nil;
}


NSString * luakit_getErrorMessage(lua_State *L, int errCode)
{
    const char *errMsg = NULL;
    if (lua_isstring(L, -1)) {
        errMsg = lua_tostring(L, -1);
    }
    
    if (errMsg) {
        
        if (errCode) {
            return [NSString stringWithFormat:@"%s #%d", errMsg, errCode];
        } else {
            return [NSString stringWithUTF8String:errMsg];
        }
        
    } else if (errCode) {
        
        return [NSString stringWithFormat:@"Lua Err #%d", errCode];
    }
    
    return nil;
}

NSError *luakit_errorWithCode(NSUInteger code, NSString *reason)
{
    NSString *desc;
    switch (code) {
        case LuaKitErrorCompile:
            desc = NSLocalizedString(@"unable compile chunk", nil);
            break;
        case LuaKitErrorSyntaxIncomplete:
            desc = NSLocalizedString(@"incomplete statements", nil);
            break;
        case LuaKitErrorRunChunk:
            desc = NSLocalizedString(@"unable run chunk", nil);
            break;
        case LuaKitErrorRunFunction:
            desc = NSLocalizedString(@"unable run function", nil);
            break;
        case LuaKitErrorBadName:
            desc = NSLocalizedString(@"bad name", nil);
            break;
        case LuaKitErrorBadArgument:
            desc = NSLocalizedString(@"bad argument", nil);
            break;
        case LuaKitErrorNotTable:
            desc = NSLocalizedString(@"not table", nil);
            break;
        case LuaKitErrorBadState:
            desc = NSLocalizedString(@"bad lua state", nil);
            break;
            
        default:
            break;
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    
    if (desc) {
        userInfo[NSLocalizedDescriptionKey] = desc;
    }
    
    if (reason) {
        userInfo[NSLocalizedFailureReasonErrorKey] = reason;
    }
    
    return [NSError errorWithDomain:LuaKitErrorDomain
                               code:code
                           userInfo:userInfo.copy];
}

id luakit_valueWithIndex(lua_State *L, int index, LuaKitOptions options)
{
    if (index < 0){
        index = lua_gettop(L) + index + 1;
    }
    
    const int T = lua_type(L, index);
    
    id result;
    switch(T){
            
        case LUA_TNUMBER:
            if (lua_isinteger(L, index)) {
                result = @(lua_tointeger(L, index));
            } else {
                result = @(lua_tonumber(L, index));
            }
            break;
            
        case LUA_TBOOLEAN:
            result = @((_Bool)(lua_toboolean(L, index) ? true : false));
            break;
            
        case LUA_TSTRING:
            result = [NSString stringWithUTF8String:lua_tostring(L, index)];
            break;
            
        case LUA_TTABLE: {
            
            if (options & LuaKitOptionsTable) {
                
                NSMutableArray *keys = [NSMutableArray array];
                NSMutableArray *vals = [NSMutableArray array];
                BOOL isArray = YES;
                int nKey = 1;
                
                lua_pushnil(L);
                while (lua_next(L, index)) {
                    
                    id val = luakit_valueWithIndex(L, -1, options);
                    id key = luakit_valueWithIndex(L, -2, options);
                    
                    if (key && val) {
                        
                        if (![key isKindOfClass:[NSNumber class]] ||
                            !((NSNumber *)key).intValue == nKey)
                        {
                            isArray = NO;
                        }
                        
                        [keys addObject:key];
                        [vals addObject:val];
                    }
                    
                    lua_pop(L,1);
                    ++nKey;
                }
                
                if (vals.count) {
                    if (isArray) {
                        result = [vals copy];
                    } else {
                        result = [NSMutableDictionary dictionaryWithObjects:vals forKeys:keys];
                    }
                } else {
                    result = @{};
                }
                
            } else {
                
                LuaTableRef *p = [[LuaTableRef alloc] initWithState:L];
                [p mkref:index];
                result = p;
            }
            
            break;
        }
            
        case LUA_TUSERDATA: {
            
            void *p = luaL_testudata(L, index, luaobjc_kMetaTableKeyObject);
            if (p) {
                
                void **ptr = (void**)p;
                result = (__bridge id)*ptr;
                
            } else {
                
                void *p = luaL_testudata(L, index, luaobjc_kMetaTableKeyClass);
                if (p) {
                    
                    void **ptr = (void**)p;
                    result = (__bridge id)*ptr;
                    
                } else {
                    
                    // foreign userdatum (like socket)
                    LuaObjectRef *p = [[LuaObjectRef alloc] initWithState:L];
                    [p mkref:index];
                    result = p;
                }
            }
            break;
        }
            
        case LUA_TFUNCTION: case LUA_TTHREAD: {
            
            LuaObjectRef *p = [[LuaObjectRef alloc] initWithState:L];
            [p mkref:index];
            result = p;
            break;
        }
            
        case LUA_TLIGHTUSERDATA:
        case LUA_TNIL:
        default:
            break;
    }
    
    return result;
}

BOOL luakit_pushValue(lua_State *L, id obj, LuaKitOptions options)
{
    if ([obj isKindOfClass:[NSNumber class]]) {
        
        NSNumber *n = obj;
        
        const char *objType = n.objCType;
        if (!objType) {
            return NO;
        }
        
        switch (*objType) {
            case _C_CHR:        lua_pushboolean(L, (int)(n.boolValue ? 1 : 0)); break;
            case _C_UCHR:       lua_pushinteger(L, (lua_Integer)n.unsignedCharValue); break;
            case _C_INT:        lua_pushinteger(L, (lua_Integer)n.intValue); break;
            case _C_UINT:       lua_pushinteger(L, (lua_Integer)n.unsignedIntValue); break;
            case _C_SHT:        lua_pushinteger(L, (lua_Integer)n.shortValue); break;
            case _C_USHT:       lua_pushinteger(L, (lua_Integer)n.unsignedShortValue); break;
            case _C_LNG:        lua_pushinteger(L, (lua_Integer)n.longValue); break;
            case _C_ULNG:       lua_pushinteger(L, (lua_Integer)n.unsignedLongValue); break;
            case _C_LNG_LNG:    lua_pushinteger(L, (lua_Integer)n.longLongValue); break;
            case _C_ULNG_LNG:   lua_pushinteger(L, (lua_Integer)n.unsignedLongLongValue); break;
            case _C_FLT:        lua_pushnumber (L, (lua_Number)n.floatValue); break;
            case _C_DBL:        lua_pushnumber (L, (lua_Number)n.doubleValue); break;
            case _C_BOOL:       lua_pushboolean(L, (int)(n.boolValue ? 1 : 0)); break;
            default:
                return NO;
        }
        
    } else if ([obj isKindOfClass:[NSString class]]) {
        
        lua_pushstring(L, ((NSString *)obj).UTF8String);
        
    } else {
        
        if (options & LuaKitOptionsTable) {
            
            if ([obj isKindOfClass:[NSDictionary class]]) {
                
                return luakit_pushTable(L, obj);
                
            } else if ([obj isKindOfClass:[NSArray class]]) {
                
                return luakit_pushSequence(L, obj);
            }
        }
        
        return luakit_pushObject(L, obj);
    }
    
    return YES;
}

BOOL luakit_pushTable(lua_State *L, NSDictionary *dict)
{
    lua_newtable(L);
    const int table = lua_gettop(L);
    if (!table) {
        return NO;
    }
    
    for (id key in dict.keyEnumerator) {
        
        id val = dict[key];
        
        if (luakit_pushValue(L, key, LuaKitOptionsTable) &&
            luakit_pushValue(L, val, LuaKitOptionsTable))
        {
            lua_rawset(L,table);
            
        } else {
            
            return NO;
        }
    }
    
    return YES;
}

BOOL luakit_pushSequence(lua_State *L, NSArray *array)
{
    lua_newtable(L);
    const int table = lua_gettop(L);
    if (!table) {
        return NO;
    }
    
    int i = 1;  // 1-based index
    for (id val in array) {
        
        lua_pushinteger(L, i);
        if (luakit_pushValue(L, val, LuaKitOptionsTable)) {
            lua_rawset(L,table);
        } else {
            return NO;
        }
        ++i;
    }
    
    // set count
    lua_pushliteral(L, "n");
    lua_pushnumber(L, i - 1);
    lua_rawset(L, table);
    
    return YES;
}

BOOL luakit_pushObject(lua_State *L, id obj)
{
    if (!obj || [obj isKindOfClass:[NSNull class]]) {
        
        lua_pushnil(L);
        return YES;
    }
    
    if ([obj isKindOfClass:[LuaObjectRef class]]) {
        
        [((LuaObjectRef *)obj) push];
        return YES;
    }
    
    return luakit_pushRawObject(L, obj);
}

BOOL luakit_pushRawObject(lua_State *L, id obj)
{
#ifdef STORE_USERDATE_OBJECT
    if (!object_isClass(obj)) {
        
        // check if object already has been wrapped into lua userdata
        NSNumber *num = objc_getAssociatedObject(obj, &luaobjc_kUserDatumBridgeRetainedKey);
        if (num) {
            
            lua_getfield(L, LUA_REGISTRYINDEX, luaobjc_kUserdatasTable);
            if (lua_istable(L, -1)) {
                // table
                lua_pushinteger(L, num.intValue);   // key
                lua_rawget(L, -2);
                if (lua_isuserdata(L, -1)) {
                    
                    // DebugLog(@"got assoc userdata %p (%d) %@ %p", lua_touserdata(L, -1), num.intValue, [obj class], obj);
                    lua_remove(L, -2); // remove table from stack
                    return YES;
                }
                lua_pop(L, 2); // pop table and result
            }
        }
    }
#endif
    
    void *userdata = lua_newuserdata(L, sizeof(void*));
    if (!userdata) {
        return NO;
    }
    
    void **ptr = (void **)userdata;
    
    if (object_isClass(obj)) {
        
        *ptr = (__bridge void *)(obj);
        luaL_getmetatable(L, luaobjc_kMetaTableKeyClass);
        
    } else {
        
#ifdef STORE_USERDATE_OBJECT
        if (![obj isKindOfClass:[LuaObjectRef class]] &&
            
            // exclude common (trivial) objects
            ![obj isKindOfClass:[NSValue class]] &&
            ![obj isKindOfClass:[NSNumber class]] &&
            ![obj isKindOfClass:[NSString class]] &&
            ![obj isKindOfClass:[NSDictionary class]] &&
            ![obj isKindOfClass:[NSArray class]] &&
            ![obj isKindOfClass:[NSDate class]] &&
            ![obj isKindOfClass:[NSIndexPath class]] &&
            ![obj isKindOfClass:[UIColor class]] &&
            ![obj isKindOfClass:[UIFont class]])
        {
            // assoc userdata and object
            
            lua_getfield(L, LUA_REGISTRYINDEX, luaobjc_kUserdatasTable);
            if (lua_istable(L, -1)) {
                
                static int gkey = 0;
                const int key = ++gkey;
                // table
                lua_pushinteger(L, key);  // key
                lua_pushvalue(L, -3);     // userdatum
                lua_rawset(L, -3);
                lua_pop(L, 1);            // pop table
                
                objc_setAssociatedObject(obj, &luaobjc_kUserDatumBridgeRetainedKey, @(key), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                
                // DebugLog(@"store assoc userdata %p (%d) %@ %p", userdata, key, [obj class], obj);
            }
        }
#endif
        
        *ptr = (__bridge_retained void *)(obj);
        //*ptr = (void *)CFBridgingRetain(obj);
        
        luaL_getmetatable(L, luaobjc_kMetaTableKeyObject);
    }
    
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return NO;
    }
    
    lua_setmetatable(L, -2);
    
    return YES;
}

BOOL luakit_callFunction(lua_State *L,
                         NSArray *arguments,
                         NSArray **rvalues,
                         LuaKitOptions options,
                         NSError **outError)
{
    const int top = lua_gettop(L);
    
    NSUInteger i = 0;
    for (id p in arguments) {
        
        if (!luakit_pushValue(L, p, options)) {
            
            if (outError) {
                NSString *reason = [NSString stringWithFormat:@"#%u %@", (unsigned)i, [p class]];
                *outError = luakit_errorWithCode(LuaKitErrorBadArgument, reason);
            }
            return NO;
        }
        ++i;
    }
    
    const int err = lua_pcall(L, arguments ? (int)arguments.count : 0, rvalues ? LUA_MULTRET : 0, 0);
    if (err) {
        if (outError) {
            NSString *reason = luakit_getErrorMessage(L, err);
            *outError = luakit_errorWithCode(LuaKitErrorRunFunction, reason);
        }
        return NO;
    }
    
    if (rvalues) { // copy rvalues
        
        const int ntop = lua_gettop(L);
        if (ntop) {
            NSMutableArray *ma = [NSMutableArray array];
            for (int i = top; i <= ntop; ++i) {
                id val = luakit_valueWithIndex(L, i, options);
                if (val) {
                    [ma addObject:val];
                } else {
                    [ma addObject:[NSNull null]];
                }
            }
            *rvalues = [ma copy];
        }
    }
    
    lua_gc(L, LUA_GCSTEP, 4);
    
    return YES;
}

id luakit_tableWithIndex(lua_State *L, int index)
{
    if (index < 0){
        index = lua_gettop(L) + index + 1;
    }
    
    if (!lua_istable(L, index)) {
        return nil;
    }
    
    NSMutableArray *keys = [NSMutableArray array];
    NSMutableArray *vals = [NSMutableArray array];
    BOOL isArray = YES;
    int nKey = 1;
    
    lua_pushnil(L);
    while (lua_next(L, index)) {
        
        id val = luakit_valueWithIndex(L, -1, LuaKitOptionsTable);
        id key = luakit_valueWithIndex(L, -2, LuaKitOptionsTable);
        
        if (key && val) {
            
            if (![key isKindOfClass:[NSNumber class]] ||
                !((NSNumber *)key).intValue == nKey)
            {
                isArray = NO;
            }
            
            [keys addObject:key];
            [vals addObject:val];
        }
        
        lua_pop(L,1);
        ++nKey;
    }
    
    if (!vals.count) {
        return @{};
    }
    
    if (isArray) {
        return [vals copy];
    }
    
    return [NSMutableDictionary dictionaryWithObjects:vals forKeys:keys];
}

NSDictionary *luakit_fieldsInTable(lua_State *L, NSString *name)
{
    NSDictionary *result;
    const int top = lua_gettop(L);
    const int t = lua_getglobal(L, name.UTF8String);
    if (t == LUA_TTABLE) {
        
        const int tblidx = lua_gettop(L);
        
        NSMutableDictionary *md = [NSMutableDictionary dictionary];
        
        lua_pushnil(L);
        while (lua_next(L, tblidx)) {
            
            const int t = lua_type(L, -1); //value
            if (t != LUA_TNONE) {
                
                const char *key = lua_tostring(L, -2);
                if (key && (key != strstr(key, "_"))) {
                    
                    NSString *nsKey =
                    [NSString stringWithUTF8String:key];
                    md[nsKey] = @(t);
                }
            }
            
            lua_pop(L,1);
        }
        
        if (md.count) {
            result = [md copy];
        }
    }
    
    lua_settop(L,top);
    return result;
}

id luakit_objectForUserdata(lua_State *L, NSString *name)
{
    id result;
    const int top = lua_gettop(L);
    const int t = lua_getglobal(L, name.UTF8String);
    if (t == LUA_TUSERDATA) {
        
        void *userdata = luaL_testudata(L, -1, luaobjc_kMetaTableKeyObject);
        if (!userdata) {
            userdata = luaL_testudata(L, -1, luaobjc_kMetaTableKeyClass);
        }
        if (userdata) {
            void **ptr = (void **)userdata;
            result = (__bridge id)*ptr;
        }
    }
    lua_settop(L,top);
    return result;
}

//////////

@implementation LuaObjectRef {
 @protected
    lua_State *_L;
}

- (instancetype) initWithState:(lua_State *)L
{
    self = [super init];
    if (self) {
        _L = L;
    }
    return self;
}

- (void)dealloc
{
    [self unref];
}

- (NSString *) description
{
    [self checkLuaState];
    const char *typename = _L ? lua_typename(_L, _objtype) : "?";
    return [NSString stringWithFormat:@"<%@ %p #%d %s>", self.class, self, _reference, typename];
}

- (void) mkref:(int)idx
{
    [self checkLuaState];
    if (_L) {
    
        if (_reference) {
            luaL_unref(_L, LUA_REGISTRYINDEX, _reference);
            _reference = 0;
        }
        
        _objtype = lua_type(_L, idx);
        lua_pushvalue(_L, idx);
        _reference = luaL_ref(_L, LUA_REGISTRYINDEX);
    }
}

- (void) unref
{
    if (_L && _reference) {
        
        [self checkLuaState];
        if (_L) {
            luaL_unref(_L, LUA_REGISTRYINDEX, _reference);
        }
        _reference = 0;
    }
}

- (BOOL) push
{
    [self checkLuaState];
    if (_L && _reference) {
        lua_rawgeti(_L, LUA_REGISTRYINDEX, _reference);
        return YES;
    }
    return NO;
}

- (id) takeValue
{
    id result;
    if ([self push]) {
        result = luakit_valueWithIndex(_L, -1, LuaKitOptionsTable);
        lua_pop(_L, 1);
    }
    return result;
}

- (NSString *) typeName
{
    [self checkLuaState];
    if (_L) {
        return [NSString stringWithUTF8String:lua_typename(_L, _objtype)];
    }
    return nil;
}

- (void) checkLuaState
{
    if (_L && ![LuaState lookupLuaState:_L]) {
        _L = 0;
    }
}

@end

//////////

@implementation LuaTableRef {
    
    NSSet *_protocols;
}

- (BOOL) isValidFuncName:(NSString *)name
{
    [self checkLuaState];
    if (!_L || !self.reference) {
        return NO;
    }
    
    const int top = lua_gettop(_L);

    lua_rawgeti(_L, LUA_REGISTRYINDEX, self.reference);
    
    const BOOL result =
        lua_istable(_L, -1) &&
        lua_getfield(_L, -1, name.UTF8String) &&
        lua_isfunction(_L, -1);
    
    lua_settop(_L, top);
    return result;
}

- (BOOL) callMethod:(NSString *)name
          arguments:(NSArray *)arguments
            rvalues:(NSArray **)rvalues
            options:(LuaKitOptions)options
              error:(NSError **)outError
{
    [self checkLuaState];
    if (!_L || !self.reference) {
        return NO;
    }
    
    const int top = lua_gettop(_L);
    
    lua_rawgeti(_L, LUA_REGISTRYINDEX, self.reference);    
    if (!lua_istable(_L, -1)) {
        
        lua_settop(_L, top);
        
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorNotTable, nil);
        }
        return NO;
    }
    
    lua_getfield(_L, -1, name.UTF8String);
    if (!lua_isfunction(_L, -1)) {
        
        lua_settop(_L, top);
        
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorBadName, name);
        }
        return NO;
    }
    
    const BOOL result = luakit_callFunction(_L, arguments, rvalues, options, outError);
    lua_settop(_L, top);
    return result;
}

- (id) valueNamed:(NSString *)name
          options:(LuaKitOptions)options
{
    [self checkLuaState];
    if (!_L || !self.reference) {
        return nil;
    }
    
    const int top = lua_gettop(_L);
    lua_rawgeti(_L, LUA_REGISTRYINDEX, self.reference);
    
    id val;
    if (lua_istable(_L, -1) &&
        lua_getfield(_L, -1, name.UTF8String))
    {
         val = luakit_valueWithIndex(_L, -1, options);
    }
    
    lua_settop(_L, top);
    return val;
}

- (void) setNamed:(NSString *)name
        withValue:(id)val
          options:(LuaKitOptions)options
{
    [self checkLuaState];
    if (!_L || !self.reference) {
        return;
    }
    
    lua_rawgeti(_L, LUA_REGISTRYINDEX, self.reference);
    
    if (lua_istable(_L, -1) &&
        luakit_pushValue(_L, val, options))
    {
        lua_setfield(_L, -2, name.UTF8String);
    }
    
    lua_pop(_L, 1);
}

- (BOOL)respondsToSelector:(SEL)selector
{
    if ([super respondsToSelector:selector]) {
        return YES;
    }
    
    NSString *luaName = [self.class luaNameFromSelector:selector];
    if (luaName && [self isValidFuncName:luaName]) {
        return YES;
    }
    
    /*
    for (NSString *name in _protocols) {
        
        Protocol *protocol = objc_getProtocol(name.UTF8String);
        if (protocol) {
            struct objc_method_description desc;
            desc = protocol_getMethodDescription(protocol, selector, YES, YES);
            if (!desc.name) {
                desc = protocol_getMethodDescription(protocol, selector, NO, YES);
            }
            if (desc.name) {
                return YES;
            }
        }
    }
    */
     
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *sig = [super methodSignatureForSelector:selector];
    if (sig) {
        return sig;
    }
    
    NSString *luaName = [self.class luaNameFromSelector:selector];
    if (!luaName || ![self isValidFuncName:luaName]) {
        return nil;
    }
    
    for (NSString *name in _protocols) {
        
        Protocol *protocol = objc_getProtocol(name.UTF8String);
        if (protocol) {
            struct objc_method_description desc;
            desc = protocol_getMethodDescription(protocol, selector, YES, YES);
            if (!desc.name) {
                desc = protocol_getMethodDescription(protocol, selector, NO,YES);
            }
            if (desc.name) {
                return [NSMethodSignature signatureWithObjCTypes:desc.types];
            }
        }
    }
   
    NSMutableString *objcType = [NSMutableString stringWithString:@"@@:"];

    NSString *selName = NSStringFromSelector(selector);
    for (NSUInteger i = 0; i < selName.length; ++i) {
        if ([selName characterAtIndex:i] == ':') {
            [objcType appendString:@"@"];
        }
    }
    
    return [NSMethodSignature signatureWithObjCTypes:objcType.UTF8String];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    NSString *luaName = [self.class luaNameFromSelector:invocation.selector];

    NSMutableArray *args;
    
    [invocation retainArguments];
    
    NSMethodSignature *sig = invocation.methodSignature;
    const NSUInteger numArgs = sig.numberOfArguments;
    if (numArgs > 2) {
    
#define CASE_NUMBER(C, T) case C: { \
        T val = 0; \
        [invocation getArgument:&val atIndex:i]; \
        [args addObject:@(val)]; \
        break; \
    }
        
        args = [NSMutableArray array];
        for (NSUInteger i = 2;  i < numArgs; ++i) {
            
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
                    CASE_NUMBER(_C_LNG_LNG,long long)
                    CASE_NUMBER(_C_ULNG_LNG, unsigned long long)
                    CASE_NUMBER(_C_FLT, float)
                    CASE_NUMBER(_C_DBL, double)
                    CASE_NUMBER(_C_BOOL, _Bool)
                    
                case _C_STRUCT_B: {
                    
                    NSValue *val;
                    NSUInteger argSize = 0;
                    NSGetSizeAndAlignment(T, &argSize, NULL);
                    if (argSize) {
                        void *buffer = malloc(argSize);
                        if (buffer) {
                            [invocation getArgument:buffer atIndex:i];
                            val = [[NSValue alloc] initWithBytes:buffer objCType:T];
                            free(buffer);
                        }
                    }
                    [args addObject:val ?: [NSNull null]];                    
                    break;
                }
                    
                case _C_ID: case _C_CLASS: {
                    
                    __unsafe_unretained id obj;
                    [invocation getArgument:&obj atIndex:i];
                    [args addObject:obj ?: [NSNull null]];
                    break;
                }
                    
                case _C_SEL: {
                    
                    SEL sel;
                    [invocation getArgument:&sel atIndex:i];
                    [args addObject:sel ? NSStringFromSelector(sel) : @""];
                    break;
                }
                    
                default:
                    [args addObject:[NSNull null]];
                    break;
            }
        }
        
#undef CASE_NUMBER
    }
    
    NSArray *rvalues;
    NSError *error;
    const BOOL result = [self callMethod:luaName
                               arguments:args
                                 rvalues:&rvalues
                                 options:0
                                   error:&error];
    if (!result) {
        
        DebugLog(@"%s callMethod failed: %@", __PRETTY_FUNCTION__, error);
        
        //[[NSException exceptionWithName:error.localizedDescription
        //                         reason:error.localizedFailureReason
        //                       userInfo:error.userInfo] raise];
    }
    
    const char *rType = [sig methodReturnType];
    if (!rType || *rType == _C_VOID) {
        return;
    }
    
    id rval = rvalues.count ? rvalues.firstObject : nil;
    
#define CASE_NUMBER(C, T, prop) case C: { \
    T val = 0; \
    if (rval && [rval isKindOfClass:[NSNumber class]]) { \
        val = ((NSNumber *)rval).prop; \
    } \
    [invocation setReturnValue:&val]; \
    return; \
}

    switch (*rType) {
            
            CASE_NUMBER(_C_CHR, char, charValue)
            CASE_NUMBER(_C_UCHR, unsigned char, unsignedCharValue)
            CASE_NUMBER(_C_INT, int, intValue)
            CASE_NUMBER(_C_UINT, unsigned int, unsignedIntValue)
            CASE_NUMBER(_C_SHT, short, shortValue)
            CASE_NUMBER(_C_USHT, unsigned short, unsignedShortValue)
            CASE_NUMBER(_C_LNG, long, longValue)
            CASE_NUMBER(_C_ULNG, unsigned long, unsignedLongValue)
            CASE_NUMBER(_C_LNG_LNG,long long, longLongValue)
            CASE_NUMBER(_C_ULNG_LNG, unsigned long long, unsignedLongLongValue)
            CASE_NUMBER(_C_FLT, float, floatValue)
            CASE_NUMBER(_C_DBL, double, doubleValue)
            CASE_NUMBER(_C_BOOL, _Bool, boolValue)
            
        case _C_STRUCT_B: {
            
            if ([rval isKindOfClass:[NSValue class]]) {
                
                NSValue *val = rval;
                NSUInteger valSize, argSize;
                NSGetSizeAndAlignment(val.objCType, &valSize, NULL);
                NSGetSizeAndAlignment(rType, &argSize, NULL);
                
                if (valSize == argSize) {
                    
                    void *buffer = malloc(argSize);
                    if (buffer) {
                        bzero(buffer, argSize);
                        [val getValue:buffer];
                        [invocation setReturnValue:buffer];
                        free(buffer);
                        return;
                    }
                }
            }
            break;
        }
            
        case _C_ID: case _C_CLASS: {
            
            [invocation setReturnValue:&rval];
            return;
        }
            
        case _C_SEL: {
            if ([rval isKindOfClass:[NSString class]]) {
                SEL sel = sel_getUid([rval UTF8String]);
                [invocation setReturnValue:&sel];
                return;
            }
            break;
        }
            
        default:
            break;
    }
    
#undef CASE_NUMBER
    
    [NSException raise:LuaKitExceptionBadRVal format:@"bad return type '%s'", rType];
}

+ (NSString *) luaNameFromSelector:(SEL)sel
{
    NSString *selName = NSStringFromSelector(sel);
    return luakit_luaNameFromObjcMethodName(selName);
}

- (BOOL) adoptsProtocol:(NSString *)name
{
    Protocol *protocol = objc_getProtocol(name.UTF8String);
    if (!protocol) {
        NSLog(@"Must register Protocol before using! Just place @protocol(%@) anywhere in your code.", name);
        return NO;
    }
    
    if (_protocols) {
        _protocols = [_protocols setByAddingObject:name];
    } else {
        _protocols = [NSSet setWithObject:name];
    }
    
    return YES;
}

@end

#ifdef DEBUG
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
void luakit_debugDumpStack(lua_State *L)
{
    NSLog(@"\n");
    for (int i = 1; i <= lua_gettop(L); ++i) {
        
        const int type = lua_type(L, i);
        
        NSMutableString *ms = [NSMutableString string];
        [ms appendFormat:@"%d: (%s) ", i, lua_typename(L, type)];
        
        switch (type) {
                
            case LUA_TNIL:
                [ms appendString:@"nil"];
                break;
                
            case LUA_TBOOLEAN:
                [ms appendString:(lua_toboolean(L, i) ? @"true" : @"false")];
                break;
                
            case LUA_TLIGHTUSERDATA:
                [ms appendFormat:@"%p", lua_topointer(L, i)];
                break;
                
            case LUA_TNUMBER:
                if (lua_isinteger(L, i)) {
                    [ms appendFormat:@"%.f", lua_tonumber(L, i)];
                } else {
                    [ms appendFormat:@"%lld", lua_tointeger(L, i)];
                }
                break;
                
            case LUA_TSTRING:
                [ms appendFormat:@"%s", lua_tostring(L, i)];
                break;
                
            case LUA_TTABLE: {
                
                lua_getfield(L, i, "__name");
                const char *name = lua_tostring(L, -1);
                lua_pop(L, 1);
                
                [ms appendFormat:@"%p %s", lua_topointer(L, i), name ? name : ""];
                break;
            }
                
            case LUA_TFUNCTION:
                [ms appendFormat:@"%p", lua_topointer(L, i)];
                break;
                
            case LUA_TUSERDATA: {
             
                const char *name = NULL;
                if (lua_getmetatable(L, i)) {
                    
                    lua_getfield(L, -1, "__name");
                    name = lua_tostring(L, -1);
                    lua_pop(L, 2);
                }
                
                [ms appendFormat:@"%p %s", lua_topointer(L, i), name ? name : ""];
                break;
            }
                
            case LUA_TTHREAD:
                [ms appendFormat:@"%p", lua_topointer(L, i)];
                break;
                
            default:
                break;
        }
        
        NSLog(@"%@", ms);
    }
}
#pragma clang diagnostic pop
#endif