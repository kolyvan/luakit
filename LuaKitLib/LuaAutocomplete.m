//
//  LuaAutocomplete.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 03.04.15.
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

#import "LuaAutocomplete.h"
#import "LuaState.h"
#import "lua.h"
#import <objc/runtime.h>

/////

static NSString *const kAnyVar = @"_ANYVAR_";

@interface LuaTokenVar : NSObject
@property (readonly, nonatomic, strong) NSString *name;
@property (readonly, nonatomic) int luaType;
@end

@implementation LuaTokenVar

- (instancetype) initWithName:(NSString *)name
                      luaType:(int)luaType
{
    self = [super init];
    if (self) {
        _name = name;
        _luaType = luaType;
    }
    return self;
}

- (BOOL) isEqual:(id)other
{
    if (self == other) {
        return YES;
    }
    
    if (!other) {
        return NO;
    }
    
    if (![other isKindOfClass:[LuaTokenVar class]]) {
        return NO;
    }
    
    return  _luaType == ((LuaTokenVar *)other).luaType &&
            [_name isEqualToString:((LuaTokenVar *)other).name];
}

@end


static BOOL probeRelatedToken(NSArray *tokens, NSString *start, NSString *end)
{
    const NSUInteger p0 = [tokens indexOfObject:start];
    if (p0 != NSNotFound) {
        const NSUInteger p1 = [tokens indexOfObject:end];
        return (p1 == NSNotFound || p1 > p0);
    }
    return NO;
}

static BOOL probeUnpairedToken(NSArray *tokens, NSString *op)
{
    NSUInteger i = 0;
    for (id p in tokens) {
        if ([p isEqual:op]) {
            i += 1;
        }
    }
    return (i && (i%2));
}

static BOOL probeUnpairedToken2(NSArray *tokens, NSString *start, NSString *end)
{
    NSUInteger n0 = 0, n1 = 0;
    for (id p in tokens) {
        if ([p isEqual:start]) {
            n0 += 1;
        } else if ([p isEqual:end]) {
            n1 += 1;
        }
    }
    return n1 < n0;
}

/////

@interface LuaAutocomplete()
@end

@implementation LuaAutocomplete {
    
    LuaState *_luaState;
    NSMutableArray *_keywords;
    NSMutableArray *_predefined;
    NSMutableArray *_variables;
    NSMutableArray *_operators;
    NSMutableArray *_brackets;
    NSDictionary *_globals;
}

+ (NSCharacterSet *) delimitersCharset
{
    static NSCharacterSet *charset;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        charset = [NSCharacterSet characterSetWithCharactersInString:@" +-*/%^#=~<>(){}[];:,.'\""];
    });
    return charset;
}

+ (NSSet *) luaKeywords
{
    static NSSet *luaKeywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        luaKeywords = [NSSet setWithArray:@[@"and", @"break", @"do", @"else", @"elseif", @"end", @"false", @"for", @"function", @"if", @"in", @"local", @"nil", @"not", @"or", @"repeat", @"return", @"then", @"true", @"until", @"while" ]];
        
    });
    return luaKeywords;
}

+ (NSSet *) luaTokens
{
    static NSSet *tokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
         tokens = [NSSet setWithArray:@[@"+", @"-", @"*", @"/", @"%", @"^", @"#", @"==", @"~=", @"<=", @"=>", @"<", @">", @"=", @"(", @")", @"{", @"}", @"[", @"]", @";", @":", @",", @".", @"..", @"...", @"'", @"\"" ]];
    });
    return tokens;
}

+ (NSArray *) luaConditionalOperators
{
    static NSArray *operators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        operators = @[@"and", @"or", @"==", @"~=", @"<", @">", @"<=", @"=>"];
    });
    
    return operators;
}

+ (NSArray *) luaArithmeticOperators
{
    static NSArray *operators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        operators = @[@"+", @"-", @"*", @"/", @"%", @"^", @".."];
    });
    
    return operators;
}

+ (NSSet *) luaPredefined
{
    static NSSet *predefined;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        predefined = [NSSet setWithArray:@[
                                           @"assert", @"collectgarbage", @"coroutine", @"debug", @"dofile",
                                           @"error", @"getmetatable", @"io", @"ipairs", @"load", @"loadfile",
                                           @"math", @"next", @"os", @"package", @"pairs", @"pcall", @"print",
                                           @"rawequal", @"rawget", @"rawlen", @"rawset", @"require", @"select",
                                           @"setmetatable", @"string", @"table", @"tonumber", @"tostring", @"type",
                                           @"utf8", @"xpcall"]];
    });
    return predefined;
}

- (void) addKeyword:(NSString *)value
{
    if (_keywords) {
        if (![_keywords containsObject:value]) {
            [_keywords addObject:value];
        }
    } else {
        _keywords = [NSMutableArray arrayWithObject:value];
    }
}

- (void) addPredefined:(NSString *)value
{
    if (_predefined) {
        if (![_predefined containsObject:value]) {
            [_predefined addObject:value];
        }
    } else {
        _predefined = [NSMutableArray arrayWithObject:value];
    }
}

- (void) addVariable:(NSString *)value
{
    if (_variables) {
        if (![_variables containsObject:value]) {
            [_variables addObject:value];
        }
    } else {
        _variables = [NSMutableArray arrayWithObject:value];
    }
}

- (void) addOperator:(NSString *)value
{
    if (_operators) {
        if (![_operators containsObject:value]) {
            [_operators addObject:value];
        }
    } else {
        _operators = [NSMutableArray arrayWithObject:value];
    }
}

- (void) addBracket:(NSString *)value
{
    if (_brackets) {
        if (![_brackets containsObject:value]) {
            [_brackets addObject:value];
        }
    } else {
        _brackets = [NSMutableArray arrayWithObject:value];
    }
}

+ (NSArray *) suggestionForInput:(NSString *)input
                            word:(NSString *)word
                        luaState:(LuaState *)luaState
{
    LuaAutocomplete * p = [LuaAutocomplete new];
    if (p) {
        p->_luaState = luaState;
        p->_globals = luakit_fieldsInTable(luaState.state, @"_G");
        return [p suggestionForInput:input word:word];
    }
    return nil;
}

- (NSArray *) suggestionForInput:(NSString *)input
                            word:(NSString *)word
{
    NSMutableArray *revTokens;
    
    if (input.length) {
        
        NSMutableArray *tokens = [self tokensFromInput:input];
        if (tokens) {
            
            revTokens = [NSMutableArray arrayWithCapacity:tokens.count];
            for (id p in tokens.reverseObjectEnumerator) {
                [revTokens addObject:p];
                if ([@"end" isEqual:p]) {
                    break; // drop before end
                }
            }
        }
    }
    
    if (revTokens.count) {
        
        // first need check for some special cases like quotes and table/userdata fields
        
        if (probeUnpairedToken(revTokens, @"\"")) {
            
            return @[@"\""];
            
        } else if (probeUnpairedToken(revTokens, @"'")) {
            
            return @[@"'"];
        
        } else if (revTokens.count > 1) {
            
            NSArray *results = [self caseOfTableOrUserdataField:revTokens word:word];
            if (results) {
                return results;
            }
        }
    }
    
    if (word.length) {
        
        [self collectForWord:word];
    }
    
    if (revTokens.count) {
        
        [self collectRevTokens:revTokens];
    }

    NSMutableArray *result = [NSMutableArray array];
    
    if (_variables) {
        [result addObjectsFromArray:_variables];
    }
    if (_brackets) {
        [result addObjectsFromArray:_brackets];
    }
    if (_keywords) {
        [result addObjectsFromArray:_keywords];
    }
    if (_operators) {
        [result addObjectsFromArray:_operators];
    }
    if (_predefined) {
        [result addObjectsFromArray:_predefined];
    }

    return result.count ? [result copy] : nil;
}

- (NSArray *) caseOfTableOrUserdataField:(NSArray *)revTokens
                                    word:(NSString *)word
{
    if (revTokens.count > 1) {
        
        id last = revTokens[0];
        id penult = revTokens[1];
        
        if (([last isEqual:@"."] || [last isEqual:@":"]) &&
            [penult isKindOfClass:[LuaTokenVar class]]) {
            
            LuaTokenVar *var = (LuaTokenVar *)penult;
            
            // var: or var.
            
            if (var.luaType == LUA_TTABLE) {
                
                NSDictionary *fields = luakit_fieldsInTable(_luaState.state, var.name);
                if (fields) {
                    return fields.allKeys;
                }
                
            } else if (var.luaType == LUA_TUSERDATA) {
                
                id obj = luakit_objectForUserdata(_luaState.state, var.name);
                if (obj) {
                    
                    const BOOL isMethodCall = [last isEqual:@":"];
                    NSArray *names = luakit_luaNamesForObject(obj, isMethodCall);
                    if (names) {
                        return names;
                    }
                }
            }
            
        } else if (revTokens.count > 2) {
            
            id beforepenult = revTokens[2];
            
            if (([penult isEqual:@"."] || [penult isEqual:@":"]) &&
                [beforepenult isKindOfClass:[LuaTokenVar class]]) {
                
                // var:a or var.a
                
                LuaTokenVar *var = (LuaTokenVar *)beforepenult;
                
                if (word) {
                    
                    NSArray *keys;
                    
                    if (var.luaType == LUA_TTABLE) {
                        
                        keys = luakit_fieldsInTable(_luaState.state, var.name).allKeys;
                        
                    } else if (var.luaType == LUA_TUSERDATA) {
                        
                        id obj = luakit_objectForUserdata(_luaState.state, var.name);
                        if (obj) {
                            
                            const BOOL isMethodCall = [last isEqual:@":"];
                            keys = luakit_luaNamesForObject(obj, isMethodCall);
                        }
                    }
                    
                    if (keys) {
                        
                        NSMutableArray *ma = [NSMutableArray array];
                        for (NSString *key in keys) {
                            
                            if (![key isEqualToString:word] &&
                                [key hasPrefix:word])
                            {
                                [ma addObject:key];
                            }
                        }
                        if (ma.count) {
                            return [ma copy];
                        }
                    }
                }
                
                return @[@"(", @"="];
            }
        }
    }
    
    return nil;
}

- (void) collectRevTokens:(NSArray *)revTokens
{
    NSString *last = revTokens.firstObject;
    
    if (probeUnpairedToken2(revTokens, @"(", @")")) {
        
        [self addBracket:@")"];
        
        if ([last isEqual:kAnyVar] ||
            [last isKindOfClass:[LuaTokenVar class]])
        {
            [self addOperator:@","];
        }
    }
    
    if (probeUnpairedToken2(revTokens, @"{", @"}")) {
        
        [self addBracket:@"}"];
        
        if ([last isEqual:kAnyVar] ||
            [last isKindOfClass:[LuaTokenVar class]])
        {
            [self addOperator:@"="];
            [self addOperator:@","];
        }
    }
    
    if (probeUnpairedToken2(revTokens, @"[", @"]")) {
        [self addBracket:@"]"];
    }
    
    if ([last isEqual:kAnyVar]) {
        
        if (revTokens.count > 1) {
            
            id penult = revTokens[1];
            
            if ([penult isEqual:@"function"]) {
                
                [self addBracket:@"("];
                [self addBracket:@"{"];
                
            } else if ([penult isEqual:@"if"] ||
                       [penult isEqual:@"while"] ||
                       [penult isEqual:@"until"] ||
                       [penult isEqual:@"for"])
            {
                for (NSString *s in self.class.luaConditionalOperators) {
                    [self addOperator:s];
                }
                
            } else  {
                
                [self addOperator:@"="];                
                for (NSString *s in self.class.luaArithmeticOperators) {
                    [self addOperator:s];
                }
                [self addOperator:@";"];
            }
            
        } else {
            
            [self addOperator:@"="];
        }
        
    } else if ([last isKindOfClass:[LuaTokenVar class]]) {
        
        if (((LuaTokenVar *)last).luaType == LUA_TTABLE) {
            
            [self addOperator:@"."];
            [self addOperator:@":"];
            [self addOperator:@"["];
            
        } else if (((LuaTokenVar *)last).luaType == LUA_TUSERDATA) {
            
            [self addOperator:@"."];
            [self addOperator:@":"];
        }
        
    } else if ([last isEqual:@"function"]) {
        
        [self addBracket:@"("];
        [self addBracket:@"{"];
        
    } else if ([last isEqual:@"if"] ||
               [last isEqual:@"elseif"]) {
        
        [self addKeyword:@"not"];
        
    } else if ([last isEqual:@"="]) {
        
        [self addBracket:@"{"];
        [self addKeyword:@"function"];
    }
    
    ///
    
    if (probeRelatedToken(revTokens, @"if", @"then")) {
        [self addKeyword:@"then"];
    }
    
    if (probeRelatedToken(revTokens, @"then", @"else")) {
        [self addKeyword:@"else"];
    }
    
    if (probeRelatedToken(revTokens, @"while", @"do") ||
        probeRelatedToken(revTokens, @"for", @"do"))
    {
        [self addKeyword:@"do"];
    }
    
    if (probeRelatedToken(revTokens, @"repeat", @"until")) {
        [self addKeyword:@"until"];
    }
    
    if (probeRelatedToken(revTokens, @"function", @"return")) {
        [self addKeyword:@"return"];
    }
    
    if (probeRelatedToken(revTokens, @"function", @"end") ||
        probeRelatedToken(revTokens, @"do", @"end") ||
        probeRelatedToken(revTokens, @"if", @"end") ||
        probeRelatedToken(revTokens, @"elseif", @"end") ||
        probeRelatedToken(revTokens, @"while", @"end") ||
        probeRelatedToken(revTokens, @"return", @"end"))
    {
        [self addKeyword:@"end"];
    }
}

- (void) collectForWord:(NSString *)word
{
    NSNumber *t = _globals[word];
    
    if (t) {
        
        if (t.intValue == LUA_TTABLE) {
            
            [self addOperator:@"."];
            [self addOperator:@":"];
            [self addOperator:@"["];
            
        } else if (t.intValue == LUA_TFUNCTION) {

            [self addOperator:@"("];
            [self addOperator:@"{"];
            
        } else if (t.intValue == LUA_TNUMBER) {
            
            for (NSString *s in self.class.luaArithmeticOperators) {
                [self addOperator:s];
            }
            
        } else if (t.intValue == LUA_TBOOLEAN) {
            
            for (NSString *s in self.class.luaConditionalOperators) {
                [self addOperator:s];
            }
            
        } else if (t.intValue == LUA_TSTRING) {
            
            [self addOperator:@".."];
            
        } else if (t.intValue == LUA_TUSERDATA) {

            [self addOperator:@"."];
            [self addOperator:@":"];
        }
    }
    
    for (NSString *key in _globals.keyEnumerator) {
        
        if (![key isEqualToString:word] &&
            [key hasPrefix:word])
        {
            if ([self.class.luaPredefined containsObject:key]) {
                [self addPredefined:key];
            } else {
                [self addVariable:key];
            }
        }
    }
    
    for (NSString *key in self.class.luaKeywords) {
        
        if (![key isEqualToString:word] &&
            [key hasPrefix:word])
        {
            [self addKeyword:key];
        }
    }
}

- (NSMutableArray *) tokensFromInput:(NSString *) input
{
    NSMutableArray *ma = [NSMutableArray array];
    
    NSScanner *scanner = [NSScanner scannerWithString:input];
    
    while (!scanner.isAtEnd) {
        
        NSString *t;
        [scanner scanCharactersFromSet:self.class.delimitersCharset intoString:&t];
        if (t) {
            
            if (t.length > 1) {
            
                for (NSUInteger i = 0; i < t.length; ++i) {
                    const unichar ch = [t characterAtIndex:i];
                    if (ch != ' ') {
                        [ma addObject:[NSString stringWithFormat:@"%C", ch]];
                    }
                }
                
            } else {
                
                [ma addObject:t];
            }
        }
        
        NSString *k;
        if ([scanner scanUpToCharactersFromSet:self.class.delimitersCharset intoString:&k]) {
            
            if (![self.class.luaKeywords containsObject:k]) {

                id t = _globals[k];
                if (t &&
                    ([t intValue] == LUA_TTABLE ||
                     [t intValue] == LUA_TUSERDATA))
                {
                    [ma addObject:[[LuaTokenVar alloc] initWithName:k luaType:[t intValue]]];
                    k = nil;
                    
                } else {
                    k = kAnyVar;
                }
            }
            
            if (k) {
                [ma addObject:k];
            }
        }
    }
    
    return ma.count ? ma : nil;
}

@end
