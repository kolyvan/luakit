//
//  AppDelegate.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 24.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import "FooObj.h"
#import "LuaKit.h"

@interface AppDelegate () <LuaStateDelegate>
@end

@implementation AppDelegate {
    LuaState                *_luaState;
    LuaConsole              *_luaConsole;
    LuaConsoleAppearance    *_luaAppearance;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.tintColor = self.luaAppearance.resultColor;
    
    //UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:_luaConsole];
    ViewController *mainVC = [ViewController new];
    UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:mainVC];
    
    navVC.navigationBar.barTintColor = self.luaAppearance.backColor;
    navVC.navigationBar.titleTextAttributes = @{ NSForegroundColorAttributeName : self.luaAppearance.printColor };
    
    self.window.rootViewController = navVC;
    [self.window makeKeyAndVisible];

    //[self testLua];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
}

- (void) actionClearConsole:(id)sender
{
   [_luaConsole clearConsole];   
}

- (void) actionCollectGarbage:(id)sender
{
    const NSUInteger kbytes = _luaState.memoryUsedInKB;
    
    [_luaState collectGarbage];
    
    NSString *msg = [NSString stringWithFormat:@"collected garbage, memory used: %uKB now: %uKB",
                     (unsigned)kbytes, (unsigned)_luaState.memoryUsedInKB];
    
    [_luaConsole printText:msg];
}

- (LuaConsoleAppearance *) luaAppearance
{
    if (!_luaAppearance) {
    
        _luaAppearance = [LuaConsoleAppearance new];
        _luaAppearance.keyboardAppearance = UIKeyboardAppearanceDark;
        _luaAppearance.backColor    = [UIColor colorWithRed:0x39/255.f green:0x3f/255.f blue:0x45/255.f alpha:1.f];
        _luaAppearance.inputColor   = [UIColor colorWithRed:0xC7/255.f green:0xAE/255.f blue:0x95/255.f alpha:1.f];
        _luaAppearance.resultColor  = [UIColor colorWithRed:0x95/255.f green:0xAE/255.f blue:0xC7/255.f alpha:1.f];
        _luaAppearance.printColor   = [UIColor colorWithRed:0xAE/255.f green:0xC7/255.f blue:0x95/255.f alpha:1.f];
        _luaAppearance.errorColor   = [UIColor colorWithRed:0xC7/255.f green:0x95/255.f blue:0x95/255.f alpha:1.f];
    }
    return _luaAppearance;
}

- (LuaState *) luaState
{
    if (!_luaState) {
        
        _luaState = [LuaState new];
        
        NSString *docsFolder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask,
                                                                    YES) lastObject];
        
        NSString *resFolder = [[NSBundle mainBundle] resourcePath];
        
        _luaState.packagePaths = @[docsFolder, resFolder];
        NSLog(@"%@", _luaState.packagePaths);
    }
    return _luaState;
}

- (LuaConsole *) luaConsole
{
    if (!_luaConsole) {
        
        _luaConsole = [[LuaConsole alloc] initWithLuaState:self.luaState];
        _luaConsole.title = @"Console";
        _luaConsole.appearance = self.luaAppearance;
        
        _luaConsole.navigationItem.rightBarButtonItems =
        @[
          [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(actionClearConsole:)],
        
            [[UIBarButtonItem alloc] initWithTitle:@"CG" style:UIBarButtonItemStylePlain target:self action:@selector(actionCollectGarbage:)],
          ];
    }
    return _luaConsole;
}

#pragma mark - LuaStateDelegate

- (void) luaState:(LuaState *)state printText:(NSString *)text
{
    NSLog(@"lua: %@", text);
}

#pragma mark - test

- (void) testLua
{
    Protocol *protocol = @protocol(FooManagerDelegate); // register protocol
    NSLog(@"Protocol regsitered: %@", protocol);
    
    NSString *cacheFolder = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                                 NSUserDomainMask,
                                                                 YES) lastObject];
    cacheFolder = [cacheFolder stringByAppendingPathComponent:@"luabin"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:cacheFolder]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cacheFolder
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    
    NSString *resourceFolder = [[NSBundle mainBundle] resourcePath];
    NSString *luaPath = [resourceFolder stringByAppendingPathComponent:@"test.lua"];
    
    NSError *error;
    NSArray *rvalues;
    
    @autoreleasepool {
        
        if (![self.luaState runFile:luaPath
                           binCache:cacheFolder
                            rvalues:&rvalues
                            options:0
                              error:&error]) {
            NSLog(@"%@", error);
            return;
        }
    }
    
    NSLog(@"rvalues: %@", rvalues);
}

@end
