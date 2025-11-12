#import "PKSystemWideElement.h"
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <Carbon/Carbon.h>

typedef AXError (*AXUIElementPerformActionWithValueFn)(AXUIElementRef, CFStringRef, CFTypeRef);
static AXUIElementPerformActionWithValueFn _AXUIElementPerformActionWithValue_ptr = NULL;

__attribute__((constructor))
static void _LoadPaneKitSystemWideSymbols(void) {
    void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
    if (handle) {
        _AXUIElementPerformActionWithValue_ptr = (AXUIElementPerformActionWithValueFn)dlsym(handle, "_AXUIElementPerformActionWithValue");
        #if DEBUG
            if (_AXUIElementPerformActionWithValue_ptr) {
                //NSLog(@"[PaneKit] ✅ Loaded _AXUIElementPerformActionWithValue dynamically.");
            } else {
                //NSLog(@"[PaneKit] ⚠️ Could not resolve _AXUIElementPerformActionWithValue (will use fallback).");
            }
        #endif
    }
}

@implementation PKSystemWideElement

- (instancetype)initWithAXElement:(AXUIElementRef)element {
    self = [super initWithAXElement:element];
    if (self) {
        // custom setup
    }
    return self;
}

- (instancetype)initWithAXUIElement:(AXUIElementRef)element {
    self = [super initWithAXUIElement:element];
    if (self) {
        // custom setup
    }
    return self;
}

+ (instancetype)systemWideElement {
    static PKSystemWideElement *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AXUIElementRef ref = AXUIElementCreateSystemWide();
        if (ref) {
            shared = [[self alloc] initWithAXElement:ref];
            CFRelease(ref);
        } else {
            #if DEBUG
                //NSLog(@"[PaneKit] ❌ Failed to create system-wide AX element.");
            #endif
        }
    });
    return shared;
}

+ (void)switchToSpaceWithEvent:(NSEvent *)event {
    if (!event) return;

    CGEventRef cgEvent = [event CGEvent];
    if (!cgEvent) return;

    CGEventPost(kCGHIDEventTap, cgEvent);
}

+ (nullable NSEvent *)eventForSwitchingToSpace:(NSUInteger)spaceIndex {
    if (spaceIndex == 0 || spaceIndex > 16) return nil;

    CGKeyCode keyCode = kVK_F1 + (CGKeyCode)(spaceIndex - 1);
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:keyCode];
    return event;
}

@end
