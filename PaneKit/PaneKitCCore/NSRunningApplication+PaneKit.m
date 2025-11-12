#import "NSRunningApplication+PaneKit.h"
#import <objc/runtime.h>

static const void *AXElementRefKey = &AXElementRefKey;

@implementation NSRunningApplication (PaneKit)

- (nullable instancetype)initWithAXUIElement:(AXUIElementRef)element {
    self = [super init];
    if (!self) return nil;
    if (!element) return nil;

    CFRetain(element);
    objc_setAssociatedObject(self, AXElementRefKey, (__bridge id)element, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}

- (AXUIElementRef)axElementRef {
    id stored = objc_getAssociatedObject(self, AXElementRefKey);
    return (__bridge AXUIElementRef)stored;
}

- (BOOL)isAgent {
    NSURL *bundleURL = self.bundleURL;
    if (!bundleURL) return NO;
    
    NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Contents/Info.plist"]];
    NSNumber *agentFlag = infoDict[@"LSUIElement"];
    return agentFlag.boolValue;
}

@end
