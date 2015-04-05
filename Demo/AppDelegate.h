//
//  AppDelegate.h
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 24.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import <UIKit/UIKit.h>

@class LuaState;
@class LuaConsole;
@class LuaConsoleAppearance;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (readonly, nonatomic, strong) LuaState *luaState;
@property (readonly, nonatomic, strong) LuaConsole *luaConsole;
@property (readonly, nonatomic, strong) LuaConsoleAppearance *luaAppearance;

@end

