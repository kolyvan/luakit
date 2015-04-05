###LuaKit

A Lua to Objective-C bridge

- Interop with ObjC
- iOS supports
- REPL (Lua Console)

![REPL](https://raw.github.com/kolyvan/luakit/master/docs/repl.png)

###Usage

    #import "LuaKit.h"
    LuaState *luaState = [LuaState new];
    [luaState runChunk:@"print('hello')" error:nil];

See Demo project with samples of creating buttons and a table propagation: (https://github.com/kolyvan/luakit/blob/master/Demo/lua/demo.lua)

###Limitation
- No support for using objc blocks in Lua

### Requirements
at least iOS 8 and lua-5.3