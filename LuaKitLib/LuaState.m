//
//  LuaState.m
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

#import "LuaState.h"
#import "LuaObjc.h"
#import "lua.h"
#import "lualib.h"
#import "lauxlib.h"

#ifdef DEBUG
#define DebugLog(frmt, ...)  NSLog(frmt, __VA_ARGS__)
#else
#define DebugLog(frmt, ...)
#endif

static int luakit_print_hook(lua_State *L);
static int luakit_binWriter(lua_State *L, const void* p, size_t sz, void* ud);
static NSHashTable *gLuaStates;

//////////

@implementation LuaState {
    
    lua_State *_L;
    lua_CFunction _printFunc;
}

+ (LuaState *) lookupLuaState:(lua_State *)L
{
    for (LuaState *p in gLuaStates) {
        if (p.state == L) {
            return p;
        }
    }
    return nil;
}

- (instancetype) init
{
    self = [super init];
    if (self) {
        [self setupState];
    }
    return self;
}

- (void) dealloc
{
    [self tearDown];
}

- (void) tearDown
{
    if (_L) {
        DebugLog(@"%s", __PRETTY_FUNCTION__);
        lua_close(_L);
        _L = 0;
        [gLuaStates removeObject:self];
    }
}

- (void) setupState
{
    _L = luaL_newstate();
    if (_L) {
        
        luaL_openlibs(_L);
        luaobjc_loadModule(_L);
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gLuaStates = [NSHashTable weakObjectsHashTable];
        });
        
        [gLuaStates addObject:self];
    }
}

- (lua_State *) state
{
    return _L;
}

- (BOOL) runChunk:(NSString *)chunk
            error:(NSError **)outError
{
    return [self runChunk:chunk rvalues:nil options:0 error:outError];
}

- (BOOL) runChunk:(NSString *)chunk
          rvalues:(NSArray **)rvalues
          options:(LuaKitOptions)options
            error:(NSError **)outError
{
    if (!_L) {
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorBadState, nil);
        }
        return NO;
    }
    
    const int top = lua_gettop(_L);
    
    const int err = luaL_loadstring(_L, chunk.UTF8String);
    if (err) {
        
        if (outError) {
            
            NSUInteger code = 0;
            
            if (err == LUA_ERRSYNTAX) {
                
#define EOFMARK		"<eof>"
#define marklen		(sizeof(EOFMARK)/sizeof(char) - 1)
                size_t lmsg;
                const char *msg = lua_tolstring(_L, -1, &lmsg);
                if (lmsg >= marklen && strcmp(msg + lmsg - marklen, EOFMARK) == 0) {
                    code = LuaKitErrorSyntaxIncomplete;
                }
                
                //code = LuaKitErrorSyntaxIncomplete;
            }
            
            *outError = luakit_errorWithCode(code ?: LuaKitErrorCompile,
                                             luakit_getErrorMessage(_L, err));
        }
        lua_settop(_L, top);
        return NO;
    }
    
    const BOOL result = luakit_callFunction(_L, nil, rvalues, options, outError);
    lua_settop(_L, top);
    return result;
    
}

- (BOOL) runFunctionNamed:(NSString *)name
                    error:(NSError **)outError
{
    return [self runFunctionNamed:name arguments:nil rvalues:nil options:0 error:outError];
}

- (BOOL) runFunctionNamed:(NSString *)name
                arguments:(NSArray *)arguments
                  rvalues:(NSArray **)rvalues
                  options:(LuaKitOptions)options
                    error:(NSError **)outError
{
    if (!_L) {
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorBadState, nil);
        }
        return NO;
    }
    
    const int top = lua_gettop(_L);
    
    const int t = lua_getglobal(_L, name.UTF8String);
    if (t != LUA_TFUNCTION) {
        
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorBadName, name);
        }
        lua_settop(_L, top);
        return NO;
    }
    
    const BOOL result = luakit_callFunction(_L, arguments, rvalues, options, outError);
    lua_settop(_L, top);
    return result;
}

- (BOOL) runFile:(NSString *)path
        binCache:(NSString *)binCache
         rvalues:(NSArray **)rvalues
         options:(LuaKitOptions)options
           error:(NSError **)outError
{
    if (!_L) {
        if (outError) {
            *outError = luakit_errorWithCode(LuaKitErrorBadState, nil);
        }
        return NO;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        return NO;
    }
    
    NSData *data;
    NSString *cachedPath;
    
    if (binCache) {
        
        NSString *filename = [NSString stringWithFormat:@"%@_%@.bin",
                              path.stringByDeletingLastPathComponent.lastPathComponent,
                              path.lastPathComponent];
        cachedPath = [binCache stringByAppendingPathComponent:filename];

        if ([fm fileExistsAtPath:cachedPath]) {
            
            NSDate *srcDate = [fm attributesOfItemAtPath:path error:nil].fileModificationDate;
            NSDate *binDate = [fm attributesOfItemAtPath:cachedPath error:nil].fileModificationDate;
            
            if ([srcDate compare:binDate] != NSOrderedDescending) {
                data = [NSData dataWithContentsOfFile:cachedPath options:0 error:nil];
            }
            
            if (data) {
                cachedPath = nil;
            }
        }
    }
    
    if (!data) {
        data = [NSData dataWithContentsOfFile:path options:0 error:outError];
    }
    
    if (!data) {
        return NO;
    }
    
    const int top = lua_gettop(_L);
    
    const int err = luaL_loadbufferx(_L,
                                     data.bytes,
                                     data.length,
                                     path.lastPathComponent.UTF8String,
                                     NULL);
    if (err) {
        
        if (outError) {
            
            NSUInteger code = 0;
            
            if (err == LUA_ERRSYNTAX) {
                
#define EOFMARK		"<eof>"
#define marklen		(sizeof(EOFMARK)/sizeof(char) - 1)
                size_t lmsg;
                const char *msg = lua_tolstring(_L, -1, &lmsg);
                if (lmsg >= marklen && strcmp(msg + lmsg - marklen, EOFMARK) == 0) {
                    code = LuaKitErrorSyntaxIncomplete;
                }
                
                //code = LuaKitErrorSyntaxIncomplete;
            }
            
            *outError = luakit_errorWithCode(code ?: LuaKitErrorCompile,
                                             luakit_getErrorMessage(_L, err));
        }
        lua_settop(_L, top);
        return NO;
    }
    
    if (cachedPath) {
        
        // dump function into cache
        NSMutableData *data = [NSMutableData data];
        if (!lua_dump(_L, luakit_binWriter, (__bridge void *)data, 0)) {
            [data writeToFile:cachedPath options:0 error:nil];
        }
    }
    
    const BOOL result = luakit_callFunction(_L, nil, rvalues, options, outError);
    lua_settop(_L, top);
    return result;
}

#pragma mark - access to global variables

- (NSNumber *) numberNamed:(NSString *)name
{
    if (!_L) {
        return nil;
    }
    
    id result;
    const int t = lua_getglobal(_L, name.UTF8String);
    if (t == LUA_TNUMBER) {
        
        if (lua_isinteger(_L, -1)) {
            
            const lua_Integer val = lua_tointeger(_L, -1);
            result = @(val);
            
        } else {
            
            const lua_Number val = lua_tonumber(_L, -1);
            result = @(val);
        }
        
    } else if (t == LUA_TBOOLEAN) {
        
        const _Bool val = lua_toboolean(_L, -1) ? true : false;
        result = @(val);
    }
    
    lua_pop(_L, 1);
    return result;
}

- (NSString *) stringNamed:(NSString *)name
{
    if (!_L) {
        return nil;
    }
    
    id result;
    const int t = lua_getglobal(_L, name.UTF8String);
    if (t == LUA_TSTRING) {
        const char *s = lua_tostring(_L, -1);
        if (s) {
            result = [NSString stringWithUTF8String:s];
        }
    }
    lua_pop(_L, 1);
    return result;
}

- (id) tableNamed:(NSString *)name
{
    if (!_L) {
        return nil;
    }
    
    id result;
    const int t = lua_getglobal(_L, name.UTF8String);
    if (t == LUA_TTABLE) {
        result = luakit_valueWithIndex(_L, -1, LuaKitOptionsTable);
    }
    lua_pop(_L, 1);
    return result;
}

- (id) valueNamed:(NSString *)name
          options:(LuaKitOptions)options
{
    if (!_L) {
        return nil;
    }
    
    id result;
    const int t = lua_getglobal(_L, name.UTF8String);
    if (t) {
        result = luakit_valueWithIndex(_L, -1, options);
    }
    lua_pop(_L, 1);
    return result;
}

- (void) setNamed:(NSString *)name
        withValue:(id)val
          options:(LuaKitOptions)options
{
    if (!_L) {
        return;
    }
    
    if (luakit_pushValue(_L, val, options)) {
        lua_setglobal(_L, name.UTF8String);
    }
}

#pragma mark - public

+ (NSString *) versionString
{
    const char *v = LUA_COPYRIGHT;
    return [NSString stringWithUTF8String:v];
}

- (NSUInteger) memoryUsedInKB
{
    if (!_L) {
        return 0;
    }
    
    return lua_gc(_L, LUA_GCCOUNT, 0);
}

- (void) collectGarbage
{
    if (!_L) {
        return;
    }
    
    lua_gc(_L, LUA_GCCOLLECT, 0);
}

@dynamic packagePaths;

- (NSArray *) packagePaths
{
    NSArray *paths;
    lua_getglobal(_L, "package");
    lua_getfield(_L, -1, "path");
    const char *s = lua_tostring(_L, -1);
    if (s) {
        NSString *ns = [NSString stringWithUTF8String:s];
        paths = [ns componentsSeparatedByString:@";"];
    }
    lua_pop(_L, 2);
    NSAssert(!lua_gettop(_L), @"");
    return paths;
}

- (void) setPackagePaths:(NSArray *)paths
{
    NSMutableString *ms = [NSMutableString string];
    for (NSString *path in paths) {
        
        NSString *s = [path stringByStandardizingPath];
        if (![s.lastPathComponent isEqualToString:@"?.lua"]) {
            s = [s stringByAppendingPathComponent:@"?.lua"];
        }
        [ms appendFormat:@";%s", [s fileSystemRepresentation]];
    }
    
    lua_getglobal(_L, "package");
    lua_pushstring(_L, ms.UTF8String);
    lua_setfield(_L, -2, "path");
    lua_pop(_L, 1);
    NSAssert(!lua_gettop(_L), @"");
}

- (void) setDelegate:(id<LuaStateDelegate>)delegate
{
    if (_delegate != delegate) {
        
        _delegate = delegate;
        
        if (_delegate &&
            [_delegate respondsToSelector:@selector(luaState:printText:)]) {
            
            [self _installPrintHook:YES];
        } else {
            [self _installPrintHook:NO];
        }
    }
}

#pragma mark - private

- (void) _redirectPrintText:(NSString *)text
{
    id<LuaStateDelegate> delegate = _delegate;
    if (delegate &&
        [delegate respondsToSelector:@selector(luaState:printText:)])
    {
        [delegate luaState:self printText:text];
    } else {
        [self _installPrintHook:NO];
    }
}

- (void) _installPrintHook:(BOOL)install
{
    if (!_L) {
        return;
    }
    
    if (install && !_printFunc) {
        
        lua_getglobal(_L, "print");
        if (lua_iscfunction(_L, -1)) {
            _printFunc = lua_tocfunction(_L, -1);
        }
        lua_pop(_L, 1);
        
        const struct luaL_Reg printlib [] = {
            {"print", luakit_print_hook},
            {NULL, NULL}
        };
        
        lua_getglobal(_L, "_G");
        luaL_setfuncs(_L, printlib, 0);
        lua_pop(_L, 1);
        
        DebugLog(@"install the hook to print function: %p", _printFunc);
        
    } else if (!install && _printFunc) {
        
        DebugLog(@"remove the hook to print function: %p", _printFunc);
        
        const struct luaL_Reg printlib [] = {
            {"print", _printFunc},
            {NULL, NULL}
        };
        
        lua_getglobal(_L, "_G");
        luaL_setfuncs(_L, printlib, 0);
        lua_pop(_L, 1);
        
        _printFunc = NULL;
    }
}

@end

//////////

static int luakit_print_hook(lua_State *L)
{
    LuaState *luaState = [LuaState lookupLuaState:L];
    if (luaState) {
        
        const int top = lua_gettop(L);
        
        NSMutableString *ms = [NSMutableString string];
        
        for (int i = 1; i <= top; ++i) {
            
            size_t len = 0;
            const char *s = luaL_tolstring(L, i, &len);
            if (!s) {
                return luaL_error(L, "'tostring' must return a string to 'print'");
            }
            
            if (i > 1) {
                [ms appendString:@"\t"];
            }
            
            NSString *ns = [NSString stringWithUTF8String:s];
            [ms appendString:ns];
            
            lua_pop(L, 1);
        }
        
        [ms appendString:@"\n"];
        
        [luaState _redirectPrintText:ms];
        
    } else {
        
        // copy of luaB_print from lbaselib.c
        
        int n = lua_gettop(L);  /* number of arguments */
        int i;
        lua_getglobal(L, "tostring");
        for (i=1; i<=n; i++) {
            const char *s;
            size_t l;
            lua_pushvalue(L, -1);  /* function to be called */
            lua_pushvalue(L, i);   /* value to print */
            lua_call(L, 1, 1);
            s = lua_tolstring(L, -1, &l);  /* get result */
            if (s == NULL)
                return luaL_error(L, "'tostring' must return a string to 'print'");
            if (i>1) lua_writestring("\t", 1);
            lua_writestring(s, l);
            lua_pop(L, 1);  /* pop result */
        }
        lua_writeline();
    }
    
    return 0;
    
}

static int luakit_binWriter (lua_State *L,
                             const void* p,
                             size_t sz,
                             void* ud)
{
    NSMutableData *data = (__bridge NSMutableData *)ud;
    [data appendBytes:p length:sz];
    return 0;
}
