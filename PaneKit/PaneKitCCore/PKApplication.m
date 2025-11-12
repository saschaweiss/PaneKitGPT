#import "PKApplication.h"
#import <AppKit/AppKit.h>
#import "PKWindow.h"
#import "PKUniversalAccessHelper.h"

@interface PKApplicationObservation : NSObject
@property (nonatomic, strong) NSString *notification;
@property (nonatomic, copy) PKAXNotificationHandler handler;
@end
@implementation PKApplicationObservation
@end

@interface PKApplication ()
@property (nonatomic, assign, nullable) AXObserverRef observerRef;
@property (nonatomic, strong) NSMutableDictionary<PKAccessibilityElement *, NSMutableArray<PKApplicationObservation *> *> *elementToObservations;
@property (nonatomic, strong, nullable) NSMutableArray<PKWindow *> *cachedWindows;
@end

@implementation PKApplication

- (instancetype)initWithAXUIElement:(AXUIElementRef)element {
    self = [super initWithAXUIElement:element];
    if (!self) return nil;
    return self;
}

- (instancetype)initWithAXElement:(AXUIElementRef)element {
    self = [super initWithAXUIElement:element];
    if (!self) return nil;
    return self;
}

+ (nullable instancetype)forProcessIdentifier:(pid_t)pid {
    if (pid <= 0) return nil;
    NSRunningApplication *runningApp = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!runningApp) return nil;

    PKApplication *app = [[self alloc] initWithAXUIElement:AXUIElementCreateApplication(pid)];
    if (app) app->_runningApplication = runningApp;
    return app;
}

+ (nullable instancetype)applicationWithRunningApplication:(NSRunningApplication *)runningApplication {
    if (!runningApplication || runningApplication.terminated) return nil;
    if (runningApplication.activationPolicy != NSApplicationActivationPolicyRegular) return nil;

    AXUIElementRef axElementRef = AXUIElementCreateApplication(runningApplication.processIdentifier);
    if (!axElementRef) return nil;

    PKApplication *application = [[self alloc] initWithAXElement:axElementRef];
    if (application) application->_runningApplication = runningApplication;
    CFRelease(axElementRef);
    return application;
}

+ (NSArray<PKApplication *> *)runningApplications {
    if (![PKUniversalAccessHelper isAccessibilityTrusted]) {
        #if DEBUG
            //NSLog(@"[PaneKit] Accessibility permissions missing — returning nil app list.");
        #endif
        return nil;
    }
    
    NSMutableArray<PKApplication *> *apps = [NSMutableArray array];
    NSArray<NSRunningApplication *> *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication *runningApp in runningApps) {
        if (runningApp.terminated || runningApp.activationPolicy != NSApplicationActivationPolicyRegular || runningApp.hidden) {
            continue;
        }
        
        PKApplication *app = [PKApplication applicationWithRunningApplication:runningApp];
        if (!app) continue;
        
        NSArray *windows = [app arrayForKey:kAXWindowsAttribute];
        BOOL hasValidWindow = NO;
        
        for (id ref in windows) {
            if (CFGetTypeID((__bridge CFTypeRef)ref) == AXUIElementGetTypeID()) {
                AXUIElementRef winRef = (__bridge AXUIElementRef)ref;
                CFTypeRef roleValue = NULL;
                if (AXUIElementCopyAttributeValue(winRef, kAXRoleAttribute, &roleValue) == kAXErrorSuccess) {
                    NSString *role = (__bridge_transfer NSString *)roleValue;
                    if ([role isEqualToString:(__bridge NSString *)kAXWindowRole]) {
                        hasValidWindow = YES;
                        break;
                    }
                }
            }
        }
        
        if (!hasValidWindow) {
            continue;
        }

        [apps addObject:app];
    }

    return [apps copy];
}

+ (NSArray<PKApplication *> *)allRunningApplications {
    NSMutableArray<PKApplication *> *apps = [NSMutableArray array];
    for (NSRunningApplication *runningApp in [[NSWorkspace sharedWorkspace] runningApplications]) {
        PKApplication *app = [[PKApplication alloc] initWithAXUIElement:AXUIElementCreateApplication(runningApp.processIdentifier)];
        if (app) [apps addObject:app];
    }
    return apps;
}

- (void)dealloc {
    if (_observerRef) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(_observerRef), kCFRunLoopDefaultMode);

        for (PKAccessibilityElement *element in self.elementToObservations.allKeys) {
            for (PKApplicationObservation *observation in self.elementToObservations[element]) {
                AXObserverRemoveNotification(_observerRef, element.axElementRef, (__bridge CFStringRef)observation.notification);
            }
        }

        CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(_observerRef));
        CFRelease(_observerRef);
        _observerRef = NULL;
    }
}

#pragma mark - AXObserver Callback

static void observerCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, CFDictionaryRef _Nullable userInfo, void * _Nullable refcon){
    if (!refcon || !element) return;

    PKAXNotificationHandler callback = (__bridge PKAXNotificationHandler)refcon;
    if (!callback) return;

    PKWindow *window = [[PKWindow alloc] initWithAXElement:element];
    if (window) callback(window);
}

#pragma mark - Observer Management

- (BOOL)observeNotification:(CFStringRef)notification withElement:(PKAccessibilityElement * _Nonnull)accessibilityElement handler:(PKAXNotificationHandler _Nonnull)handler{
    if (!notification || !accessibilityElement || !handler) {
        return NO;
    }

    if (!self.observerRef) {
        AXObserverRef observerRef = NULL;
        AXError createError = AXObserverCreateWithInfoCallback(self.processIdentifier, observerCallback, &observerRef);
        if (createError != kAXErrorSuccess || !observerRef) {
            #if DEBUG
                //NSLog(@"[PaneKit] Failed to create AXObserver (error %d)", createError);
            #endif
            return NO;
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observerRef), kCFRunLoopDefaultMode);
        self.observerRef = observerRef;
        self.elementToObservations = [NSMutableDictionary dictionary];
    }

    AXError addError = AXObserverAddNotification(self.observerRef, accessibilityElement.axElementRef, notification, (__bridge void *)handler);
    if (addError != kAXErrorSuccess) {
        #if DEBUG
            //NSLog(@"[PaneKit] Failed to add AX notification %@ (error %d)", notification, addError);
        #endif
        return NO;
    }

    PKApplicationObservation *observation = [[PKApplicationObservation alloc] init];
    observation.notification = (__bridge NSString *)notification;
    observation.handler = handler;

    NSMutableArray<PKApplicationObservation *> *list = self.elementToObservations[accessibilityElement];
    if (!list) {
        list = [NSMutableArray array];
        self.elementToObservations[accessibilityElement] = list;
    }
    [list addObject:observation];
    return YES;
}

- (void)unobserveNotification:(CFStringRef _Nonnull)notification withElement:(PKAccessibilityElement * _Nonnull)accessibilityElement {
    if (!self.observerRef || !accessibilityElement) return;

    NSArray<PKApplicationObservation *> *observations = self.elementToObservations[accessibilityElement];
    for (PKApplicationObservation *observation in observations) {
        AXError error = AXObserverRemoveNotification(self.observerRef, accessibilityElement.axElementRef, (__bridge CFStringRef)observation.notification);
        #if DEBUG
            if (error != kAXErrorSuccess) {
                //NSLog(@"[PaneKit] Failed to remove notification %@ (error %d)", observation.notification, error);
            }
        #endif
    }

    [self.elementToObservations removeObjectForKey:accessibilityElement];

    if (self.elementToObservations.count == 0) {
        CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(self.observerRef));
        CFRelease(self.observerRef);
        self.observerRef = NULL;
    }
}

#pragma mark - Public Accessors

- (NSArray<PKWindow *> *)windows {
    if (!self.cachedWindows) {
        self.cachedWindows = [NSMutableArray array];
        NSArray *windowRefs = [self arrayForKey:kAXWindowsAttribute];

        for (id ref in windowRefs) {
            if (CFGetTypeID((__bridge CFTypeRef)ref) == AXUIElementGetTypeID()) {
                AXUIElementRef windowRef = (__bridge AXUIElementRef)ref;
                PKWindow *window = [[PKWindow alloc] initWithAXElement:windowRef];
                if (window) [self.cachedWindows addObject:window];
            }
        }
    }
    return [self.cachedWindows copy];
}

- (NSArray<PKWindow *> *)visibleWindows {
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PKWindow *window, NSDictionary<NSString *, id> *bindings) {
        return ![[window app] isHidden] && ![window isWindowMinimized] && [window isNormalWindow];
    }];
    return [self.windows filteredArrayUsingPredicate:predicate];
}

- (nullable NSString *)title {
    return [self stringForKey:kAXTitleAttribute];
}

- (BOOL)isHidden {
    return [[self numberForKey:kAXHiddenAttribute] boolValue];
}

- (void)hide {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    [app hide];
}

- (void)unhide {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    [app unhide];
}

- (void)kill {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    [app terminate];
}

- (void)kill9 {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    [app forceTerminate];
}

- (void)dropWindowsCache {
    self.cachedWindows = nil;
}

@end
