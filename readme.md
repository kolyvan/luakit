##LuaKit

A Lua to Objective-C bridge

- Interop with ObjC
- iOS supports
- REPL (Lua Console)

[REPL](https://raw.github.com/kolyvan/luakit/master/docs/repl.png)

##Usage

  #import "LuaKit.h"
  LuaState *luaState = [LuaState new];
  [luaState runChunk:@"print('hello')" error:nil];

See Demo project with samples of creating buttons and a table propagation: (https://raw.github.com/kolyvan/luakit/master/Demo/lua/demo.lua)


### Requirements
at least iOS 8 and lua-5.3