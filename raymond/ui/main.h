#pragma once

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface AppViewController : NSViewController<NSWindowDelegate>

-(instancetype)initWithRenderer:(id)renderer;

@end

struct UIState {
    bool showImguiDemo;
    bool showImplotDemo;
};
