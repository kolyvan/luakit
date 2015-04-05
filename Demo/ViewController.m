//
//  ViewController.m
//  https://github.com/kolyvan/luakit
//
//  Created by Kolyvan on 24.03.15.
//  Copyright (c) 2015 Kolyvan. All rights reserved.
//

#import "ViewController.h"
#import "AppDelegate.h"
#import "LuaKit.h"
#import "LuaState.h"
#import "LuaConsole.h"

@interface ChildTableViewController : UITableViewController
@end

@implementation ChildTableViewController

- (void) dealloc
{
    NSLog(@"%s %@", __PRETTY_FUNCTION__, self);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ViewController ()
@end

@implementation ViewController {
    BOOL _didInit;
}

- (id) init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = @"Lua Demo";
    }
    return self;
}

- (void)loadView
{
    AppDelegate *appDelegate = [UIApplication sharedApplication].delegate;
    
    const CGRect frame = [[UIScreen mainScreen] bounds];
    self.view = ({
        UIView *view = [[UIView alloc] initWithFrame:frame];
        view.backgroundColor = appDelegate.luaAppearance.backColor;
        view.opaque = YES;
        view;
    });
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Console"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(actionConsole:)];
}

- (void) viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    if (!_didInit) {
        
        _didInit = YES;
        [self loadDemo];
    }
}

- (void) loadDemo
{
    AppDelegate *appDelegate = [UIApplication sharedApplication].delegate;
    LuaState *luaState = appDelegate.luaState;
    
    NSString *resourceFolder = [[NSBundle mainBundle] resourcePath];
    NSString *luaPath = [resourceFolder stringByAppendingPathComponent:@"demo.lua"];
    NSString *luaCode = [NSString stringWithContentsOfFile:luaPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    
    @autoreleasepool {

        NSError *error;
        if (![luaState runChunk:luaCode
                        rvalues:nil
                        options:0
                          error:&error])
        {
            NSLog(@"%@", error);
            return;
        }
    }
    
    [luaState collectGarbage];
}

- (void) actionConsole:(id)sender
{
    AppDelegate *appDelegate = [UIApplication sharedApplication].delegate;
    [self.navigationController pushViewController:appDelegate.luaConsole animated:YES];
}

@end
