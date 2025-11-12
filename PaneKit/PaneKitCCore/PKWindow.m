#import "PKWindow.h"

#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#import "NSScreen+PaneKit.h"
#import "PKApplication.h"
#import "PKSystemWideElement.h"
#import "PKUniversalAccessHelper.h"
#import <dlfcn.h>
#import <CommonCrypto/CommonDigest.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <Foundation/NSValue.h>
#import <Cocoa/Cocoa.h>

#pragma mark - PaneKit CGWindowList Cache (PID-level)

#ifndef kAXSheetSubrole
    #define kAXSheetSubrole                         CFSTR("AXSheet")
#endif

#ifndef kAXDialogSubrole
    #define kAXDialogSubrole                        CFSTR("AXDialog")
#endif

#ifndef kAXSystemDialogSubrole
    #define kAXSystemDialogSubrole                  CFSTR("AXSystemDialog")
#endif

#ifndef kAXFloatingWindowSubrole
    #define kAXFloatingWindowSubrole                CFSTR("AXFloatingWindow")
#endif

#ifndef kAXStandardWindowSubrole
    #define kAXStandardWindowSubrole                CFSTR("AXStandardWindow")
#endif

#ifndef kAXUnknownSubrole
    #define kAXUnknownSubrole                       CFSTR("AXUnknown")
#endif

#ifndef kAXSystemDialogSubrole
    #define kAXSystemDialogSubrole                  CFSTR("AXSystemDialog")
#endif

#ifndef kAXVisibleAttribute
    #define kAXVisibleAttribute                     CFSTR("AXVisible")
#endif

#ifndef kAXChildrenInNavigationOrderAttribute
    #define kAXChildrenInNavigationOrderAttribute   CFSTR("AXChildrenInNavigationOrder")
#endif

#ifndef kAXFrameAttribute
    #define kAXFrameAttribute                       CFSTR("AXFrame")
#endif

@implementation PKWindow (FallbackFrame)
    static char kFallbackFrameKey;
    - (void)setFallbackFrame:(CGRect)frame {
        objc_setAssociatedObject(self, &kFallbackFrameKey,
            [NSValue valueWithBytes:&frame objCType:@encode(CGRect)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    - (CGRect)fallbackFrame {
        NSValue *val = objc_getAssociatedObject(self, &kFallbackFrameKey);
        CGRect rect = CGRectZero;
        if (val) {
            [val getValue:&rect];
        }
        return rect;
    }
@end

@interface _PaneKitWindowIDCache : NSObject
    @property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSDictionary *> *> *pidCache;
    @property (nonatomic, strong) NSDate *lastUpdate;
    + (instancetype)shared;
    - (nullable NSArray<NSDictionary *> *)windowsForPID:(pid_t)pid;
    - (void)storeWindows:(NSArray<NSDictionary *> *)windows forPID:(pid_t)pid;
@end
@interface PKWindow ()
    @property (nonatomic, assign) CGWindowID _windowID;
    @property (nonatomic, assign) BOOL isActiveCache;
    @property (nonatomic, assign) BOOL isMinimizedCache;
    @property (nonatomic, assign) BOOL isFocusedCache;
@end

@implementation _PaneKitWindowIDCache

+ (instancetype)shared {
    static _PaneKitWindowIDCache *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [_PaneKitWindowIDCache new];
        shared.pidCache = [NSMutableDictionary dictionary];
        shared.lastUpdate = [NSDate distantPast];
    });
    return shared;
}

- (nullable NSArray<NSDictionary *> *)windowsForPID:(pid_t)pid {
    if ([[NSDate date] timeIntervalSinceDate:self.lastUpdate] > 1.0)
        return nil;
    return self.pidCache[@(pid)];
}

- (void)storeWindows:(NSArray<NSDictionary *> *)windows forPID:(pid_t)pid {
    if (!windows) return;
    self.pidCache[@(pid)] = windows;
    self.lastUpdate = [NSDate date];
}

@end

typedef AXError (*AXUIElementGetWindowFn)(AXUIElementRef, CGWindowID *);
static AXUIElementGetWindowFn _AXUIElementGetWindow_ptr = NULL;

typedef AXError (*AXPrivCopyAttributeFn)(AXUIElementRef, CFStringRef, CFTypeRef *);
static AXPrivCopyAttributeFn _AXPrivCopyAttributeValue = NULL;

__attribute__((constructor))
static void _LoadPaneKitPrivateAXSymbol(void) {
    void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
    if (handle) {
        _AXPrivCopyAttributeValue = (AXPrivCopyAttributeFn)dlsym(handle, "_AXUIElementCopyAttributeValue");
    }
}

__attribute__((constructor))
static void _LoadPaneKitAXPrivateSymbols(void) {
    void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
    if (handle) {
        _AXUIElementGetWindow_ptr = (AXUIElementGetWindowFn)dlsym(handle, "_AXUIElementGetWindow");
        #if DEBUG
            //if (_AXUIElementGetWindow_ptr)
                //NSLog(@"[PaneKit] ✅ Loaded _AXUIElementGetWindow dynamically.");
            //else
                //NSLog(@"[PaneKit] ⚠️ Could not resolve _AXUIElementGetWindow, windowID will fall back.");
        #endif
    }
}

/// Safe wrapper for _AXUIElementGetWindow that falls back to kCGNullWindowID.
static AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *idOut) {
    if (!_AXUIElementGetWindow_ptr) {
        if (idOut) *idOut = kCGNullWindowID;
        return kAXErrorFailure;
    }
    return _AXUIElementGetWindow_ptr(element, idOut);
}

@implementation PKWindow

@synthesize pid = _pid;
@synthesize bundleID = _bundleID;
@synthesize ownerName = _ownerName;
@synthesize tabs = _tabs;
@synthesize parentTabHost;

+ (NSMutableDictionary<NSString *, PKWindow *> *)registry {
    static NSMutableDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ map = [NSMutableDictionary new]; });
    return map;
}

- (instancetype)initWithAXUIElement:(AXUIElementRef)element {
    self = [super initWithAXUIElement:element];
    pid_t pid = 0;
    AXUIElementGetPid(element, &pid);
    if (pid > 0) {
        self->_pid = pid;
        self.pid = pid;
    } else {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
        if (app) {
            self->_pid = app.processIdentifier;
            self.pid = app.processIdentifier;
        }
    }
    if (!self) return nil;
    
    CFTypeRef titleRef = NULL;
    NSString *title = nil;
    if (AXUIElementCopyAttributeValue(element, kAXTitleAttribute, &titleRef) == kAXErrorSuccess && titleRef) {
        title = CFBridgingRelease(titleRef);
    }

    if (title == nil || [[title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        return nil;
    }

    CGWindowID wid = self.windowID;
    NSString *appName = self.ownerName ?: @"Unknown";
    
    BOOL isTabElement = NO;
    CFTypeRef roleRef = NULL;
    CFTypeRef subroleRef = NULL;

    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &roleRef) == kAXErrorSuccess && roleRef) {
        NSString *role = CFBridgingRelease(roleRef);
        NSString *subrole = @"";
        if (AXUIElementCopyAttributeValue(element, kAXSubroleAttribute, &subroleRef) == kAXErrorSuccess && subroleRef) {
            subrole = CFBridgingRelease(subroleRef);
        }

        if ([role containsString:@"Tab"] || [role containsString:@"Button"]) {
            isTabElement = YES;
        } else if ([role isEqualToString:@"AXRadioButton"] || [role isEqualToString:@"AXTabButton"]) {
            if ([subrole containsString:@"Tab"]) {
                isTabElement = YES;
            }
        }
    }
    
    if (!isTabElement && (title == nil || title.length == 0)) {
        return nil;
    }

    if (isTabElement) {
        self.stableID = computeStableIdentifierForTab(self.axElementRef, wid, pid, appName);
    } else {
        self.stableID = computeStableIdentifierForWindow(self.axElementRef, wid, pid, appName);
    }
    
    NSArray *windowList = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    NSInteger index = NSNotFound;
    NSInteger currentIndex = 0;

    for (NSDictionary *info in windowList) {
        NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
        if (ownerPID && ownerPID.intValue == pid) {
            NSString *winTitle = info[(NSString *)kCGWindowName];
            if (winTitle && [winTitle isEqualToString:title]) {
                index = currentIndex;
                break;
            }
        }
        currentIndex++;
    }

    if (index == NSNotFound) {
        CGWindowID wid = self.windowID;
        for (NSInteger i = 0; i < windowList.count; i++) {
            NSDictionary *info = windowList[i];
            NSNumber *cgID = info[(NSString *)kCGWindowNumber];
            if (cgID && cgID.unsignedIntValue == wid) {
                index = i;
                break;
            }
        }
    }

    self.zIndex = (index != NSNotFound) ? index : 0;
    
    NSArray *cgList = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    NSDictionary *cgInfo = nil;

    for (NSDictionary *info in cgList) {
        NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
        if (ownerPID && ownerPID.intValue == pid) {
            NSNumber *cgID = info[(NSString *)kCGWindowNumber];
            if (cgID && cgID.unsignedIntValue == wid) {
                cgInfo = info;
                break;
            }
        }
    }

    if (cgInfo) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app) {
            self.bundleID = app.bundleIdentifier ?: @"<unknown>";
            self.ownerName = app.localizedName ?: @"Unknown";
        }

        NSDictionary *boundsDict = cgInfo[(NSString *)kCGWindowBounds];
        if (boundsDict) {
            CGRect rect;
            CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)boundsDict, &rect);
            self.frame = rect;
        }

        NSNumber *layer = cgInfo[(NSString *)kCGWindowLayer];
        if (layer) {
            self.zIndex = layer.integerValue;
        }
    }

    if (!self.bundleID) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        self.bundleID = app.bundleIdentifier ?: @"<unknown>";
    }

    NSString *key = self.stableID ?: @"STBL-INVALID";

    if (key == nil || [key isEqualToString:@"STBL-INVALID"] || key.length == 0) {
        //NSLog(@"⚠️ [PaneKit] Fenster ohne gültige stableID – %@ (PID=%d, Title=%@)", self.ownerName, self.pid, self.title);
        return nil;
    }
    
    //self.pid = _pid;

    [[PKWindow registry] setObject:self forKey:key];
    return self;
}

- (instancetype)initWithAXUIElement:(AXUIElementRef)element isTab:(BOOL)isTab parentTabHost:(nullable NSString *)parentTabHost {
    self = [self initWithAXUIElement:element];
    if (!self) return nil;

    if (isTab) {
        pid_t pid = self.processIdentifier;
        CGWindowID wid = self.windowID;
        NSString *appName = self.ownerName ?: @"Unknown";
        NSString *title = self.resolvedTitle ?: @"";
        //self.pid = _pid;

        NSString *raw = [NSString stringWithFormat:@"%@-%d-%@-%@", appName, pid, parentTabHost ?: @"<no parent>", title];
        NSString *hash = stableHashForWindow(raw);
        self.stableID = [NSString stringWithFormat:@"STBL-TAB-%@", [hash substringFromIndex:5]];
    }

    return self;
}

- (instancetype)initWithAXUIElement:(AXUIElementRef)axuiElement isTab:(BOOL)isTab parentTabHost:(nullable NSString *)parentTabHost pid:(pid_t)pid bundleID:(nullable NSString *)bundleID {
    if (isTab) {
        self = [super initWithAXUIElement:axuiElement];
    } else {
        self = [self initWithAXUIElement:axuiElement];
    }
    if (!self){
        return nil;
    }
        
    if (isTab) {
        self->_isTab = YES;
        if (pid > 0) self->_pid = pid;
        if (bundleID.length > 0) self->_bundleID = bundleID;
        self->parentTabHost = parentTabHost;
        //self.pid = _pid;

        NSString *appName = self->_ownerName ?: @"UnknownApp";
        NSString *newStable = computeStableIdentifierForTab(axuiElement, 0, pid, appName);
        self->_stableID = newStable ?: @"STBL-TAB-INVALID";
    }

    return self;
}

- (instancetype)initWithAXElement:(AXUIElementRef)element {
    return [self initWithAXUIElement:element];
}

- (void)refreshMetadata {
    if (self.pid == 0 || self.bundleID == nil || [self.bundleID isEqualToString:@""]) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
        if (app) {
            self.bundleID = app.bundleIdentifier ?: @"UnknownApp";
            self.pid = app.processIdentifier;
        }
    }
    if (self.pid == 0) {
        pid_t pid = 0;
        AXUIElementGetPid(self.axElementRef, &pid);
        if (pid > 0) {
            self->_pid = pid;
            self.pid = pid;
        }
    }

    if (!self.stableID || [self.stableID hasPrefix:@"STBL-INVALID"]) {
        NSString *newStable = nil;
        
        if(self.isTab){
            newStable = computeStableIdentifierForTab(self.axElement, self.windowID, self.pid, self.bundleID);
        } else {
            newStable = computeStableIdentifierForWindow(self.axElement, self.windowID, self.pid, self.bundleID);
        }
        if (newStable) self.stableID = newStable;
    }
}

+ (nullable PKWindow *)updateWindowWithStableIdentifier:(NSString *)stableID {
    if (stableID.length == 0) return nil;
    
    PKWindow *existing = [[self registry] objectForKey:stableID];
    if (!existing) {
        // Fallback: versuchen, das Fenster neu zu finden
        NSArray<PKWindow *> *all = [self allWindows];
        for (PKWindow *candidate in all) {
            if ([candidate.stableID isEqualToString:stableID]) {
                [[self registry] setObject:candidate forKey:stableID];
                existing = candidate;
                break;
            }
        }
        if (!existing) return nil;
    }

    pid_t pid = existing.processIdentifier;
    if (pid == 0) return existing;
    
    AXUIElementRef appRef = AXUIElementCreateApplication(pid);
    if (!appRef) return existing;
    
    CFTypeRef axWindows = NULL;
    if (AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, &axWindows) != kAXErrorSuccess || !axWindows) {
        CFRelease(appRef);
        return existing;
    }

    NSArray *axList = CFBridgingRelease(axWindows);
    for (id axWindowObj in axList) {
        AXUIElementRef axWindow = (__bridge AXUIElementRef)axWindowObj;
        PKWindow *tempWin = [[PKWindow alloc] initWithAXElement:axWindow];
        if (!tempWin) continue;
        
        if ([tempWin.stableID isEqualToString:stableID]) {
            existing.title = tempWin.resolvedTitle;
            existing.frame = tempWin.frame;
            existing.zIndex = tempWin.zIndex;
            existing.bundleID = tempWin.bundleID;
            existing.pid = tempWin.pid;
            existing->_isTab = tempWin->_isTab;
            existing.isActiveCache = tempWin.isActive;
            existing.isMinimizedCache = tempWin.isWindowMinimized;
            existing.isFocusedCache = tempWin.isFocused;
            
            [[self registry] setObject:existing forKey:stableID];
            break;
        }
    }
    
    CFRelease(appRef);
    return existing;
}

+ (NSArray *)allWindows {
    if (![PKUniversalAccessHelper isAccessibilityTrusted]) return nil;
    
    NSMutableArray *windows = [NSMutableArray array];
    
    for (PKApplication *application in [PKApplication runningApplications]) {
        NSArray *filtered = [PKWindow filteredRealWindowsForApp:application];
        [windows addObjectsFromArray:filtered];
    }
    
    return windows;
}

+ (NSArray *)visibleWindows {
    if (![PKUniversalAccessHelper isAccessibilityTrusted]) return nil;

    return [[self allWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PKWindow *win, NSDictionary *bindings) {
        return ![[win app] isHidden] && ![win isWindowMinimized] && [win isNormalWindow];
    }]];
}

+ (PKWindow *)focusedWindow {
    if (![PKUniversalAccessHelper isAccessibilityTrusted]) return nil;

    CFTypeRef applicationRef;
    AXUIElementCopyAttributeValue([PKSystemWideElement systemWideElement].axElementRef, kAXFocusedApplicationAttribute, &applicationRef);

    if (applicationRef) {
        CFTypeRef windowRef;
        AXError result = AXUIElementCopyAttributeValue(applicationRef, (CFStringRef)NSAccessibilityFocusedWindowAttribute, &windowRef);

        CFRelease(applicationRef);

        if (result == kAXErrorSuccess) {
            PKWindow *window = [[PKWindow alloc] initWithAXElement:windowRef];

            if ([window isSheet]) {
                PKAccessibilityElement *parent = [window elementForKey:kAXParentAttribute];
                if (parent) {
                    return [[PKWindow alloc] initWithAXElement:parent.axElementRef];
                }
            }

            return window;
        }
    }
    
    return nil;
}

- (NSArray *)otherWindowsOnSameScreen {
    return [[PKWindow visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PKWindow *win, NSDictionary *bindings) {
        return ![self isEqual:win] && [[self screen] isEqual: [win screen]];
    }]];
}

- (NSArray *)otherWindowsOnAllScreens {
    return [[PKWindow visibleWindows] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PKWindow *win, NSDictionary *bindings) {
        return ![self isEqual:win];
    }]];
}

- (NSArray *)windowsToWest {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI - fabs(angle); } shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToEast {
    return [[self windowsInDirectionFn:^double(double angle) { return 0.0 - angle; } shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaX <= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToNorth {
    return [[self windowsInDirectionFn:^double(double angle) { return -M_PI_2 - angle; } shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY >= 0); }] valueForKeyPath:@"win"];
}

- (NSArray *)windowsToSouth {
    return [[self windowsInDirectionFn:^double(double angle) { return M_PI_2 - angle; } shouldDisregardFn:^BOOL(double deltaX, double deltaY) { return (deltaY <= 0); }] valueForKeyPath:@"win"];
}

- (CGWindowID)windowID {
    static NSArray *cachedWindowList = nil;
    static NSDate *lastWindowListUpdate = nil;

    if (self._windowID != kCGNullWindowID) {
        return self._windowID;
    }

    CGWindowID windowID = kCGNullWindowID;

    if (_AXUIElementGetWindow_ptr) {
        AXError error = _AXUIElementGetWindow_ptr(self.axElementRef, &windowID);
        if (error == kAXErrorSuccess && windowID != kCGNullWindowID) {
            self._windowID = windowID;
            #if DEBUG
                //NSLog(@"[PaneKit] ✅ _AXUIElementGetWindow returned %u for %@", windowID, self.title);
            #endif
            return self._windowID;
        } else {
            #if DEBUG
                static NSMutableSet *loggedPIDs;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{ loggedPIDs = [NSMutableSet set]; });
                if (![loggedPIDs containsObject:@(self.processIdentifier)]) {
                    //NSLog(@"[PaneKit] ⚠️ _AXUIElementGetWindow failed (%d) for %@ (pid=%d)", error, self.title, self.processIdentifier); [loggedPIDs addObject:@(self.processIdentifier)];
                }
            #endif
        }
    }

    if (!cachedWindowList || !lastWindowListUpdate || [[NSDate date] timeIntervalSinceDate:lastWindowListUpdate] > 1.0) {
        CFArrayRef windowListRef = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
        cachedWindowList = CFBridgingRelease(windowListRef);
        lastWindowListUpdate = [NSDate date];
        #if DEBUG
            //NSLog(@"[PaneKit] ♻️ Refreshed global CGWindowList cache (%lu entries)", (unsigned long)cachedWindowList.count);
        #endif
    }

    // Suche passendes Fenster mit gleichem PID
    pid_t pid = self.processIdentifier;
    NSString *targetTitle = [self title] ?: @"";
    NSDictionary *bestMatch = nil;
    
    NSArray *cachedPIDWindows = [[_PaneKitWindowIDCache shared] windowsForPID:pid];
    if (cachedPIDWindows) {
        for (NSDictionary *info in cachedPIDWindows) {
            NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
            if (ownerPID && ownerPID.intValue == pid) {
                NSString *winName = info[(NSString *)kCGWindowName];
                if (winName && [winName isEqualToString:targetTitle]) {
                    bestMatch = info;
                    break;
                }
            }
        }
    }

    if (!bestMatch) {
        if (!cachedWindowList || !lastWindowListUpdate || [[NSDate date] timeIntervalSinceDate:lastWindowListUpdate] > 1.0) {
            CFArrayRef windowListRef = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
            cachedWindowList = CFBridgingRelease(windowListRef);
            lastWindowListUpdate = [NSDate date];
            #if DEBUG
                //NSLog(@"[PaneKit] ♻️ Refreshed global CGWindowList cache (%lu entries)", (unsigned long)cachedWindowList.count);
            #endif
        }
        NSMutableArray *pidMatches = [NSMutableArray array];
        for (NSDictionary *info in cachedWindowList) {
            NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
            if (ownerPID && ownerPID.intValue == pid) {
                [pidMatches addObject:info];
                NSString *winName = info[(NSString *)kCGWindowName];
                if (winName && [winName isEqualToString:targetTitle]) {
                    bestMatch = info;
                    break;
                }
            }
        }
        [[_PaneKitWindowIDCache shared] storeWindows:pidMatches forPID:pid];
    }

    for (NSDictionary *info in cachedWindowList) {
        NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
        if (ownerPID && ownerPID.intValue == pid) {
            NSString *winName = info[(NSString *)kCGWindowName];
            if (winName && [winName isEqualToString:targetTitle]) {
                bestMatch = info;
                break;
            }
            if (!bestMatch && winName.length > 0) {
                bestMatch = info;
            }
        }
    }

    if (bestMatch) {
        windowID = [bestMatch[(NSString *)kCGWindowNumber] unsignedIntValue];
        if (windowID != kCGNullWindowID) {
            self._windowID = windowID;
            #if DEBUG
                //NSLog(@"[PaneKit] 🪟 CoreGraphics fallback matched PID=%d WID=%u Title=\"%@\"", pid, windowID, targetTitle);
            #endif
            return self._windowID;
        }
    }

    #if DEBUG
        static NSMutableSet *failedPIDs;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ failedPIDs = [NSMutableSet set]; });

        if (![failedPIDs containsObject:@(pid)]) {
            //NSLog(@"[PaneKit] ⚠️ CoreGraphics fallback failed for PID=%d (%@)", pid, targetTitle);
            [failedPIDs addObject:@(pid)];
        }
    #endif

    self._windowID = kCGNullWindowID;
    return self._windowID;
}

- (NSString *)stableID {
    if (!_stableID) {
        _stableID = @"xxx";
    }
    return _stableID;
}

NSString *stableHashForWindow(NSString *input) {
    if (!input) return @"STBL-00000000";

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.UTF8String, (CC_LONG)strlen(input.UTF8String), hash);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", hash[i]];
    }

    NSString *shortHash = [hex substringToIndex:8];
    return [NSString stringWithFormat:@"STBL-%@", shortHash];
}

NSString *computeStableIdentifierForWindow(AXUIElementRef axWindow, CGWindowID wid, pid_t pid, NSString *appName) {
    if (!appName) appName = @"UnknownApp";
    if (pid == 0) return @"STBL-INVALID";
    
    NSString *bundleID = nil;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    bundleID = app.bundleIdentifier ?: appName;

    CFTypeRef titleRef = NULL;
    NSString *title = nil;
    if (AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute, &titleRef) == kAXErrorSuccess && titleRef) {
        title = CFBridgingRelease(titleRef);
    }

    CFTypeRef posRef = NULL, sizeRef = NULL;
    CGPoint pos = CGPointZero;
    CGSize size = CGSizeZero;
    if (AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute, &posRef) == kAXErrorSuccess && posRef) {
        AXValueGetValue(posRef, kAXValueCGPointType, &pos);
        CFRelease(posRef);
    }
    if (AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess && sizeRef) {
        AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
        CFRelease(sizeRef);
    }

    NSString *raw = [NSString stringWithFormat:@"%@-%d-%u-(%.0f,%.0f)-(%.0fx%.0f)-%@", bundleID, pid, wid, pos.x, pos.y, size.width, size.height, title ?: @"<no title>"];

    return stableHashForWindow(raw);
}

NSString *computeStableIdentifierForTab(AXUIElementRef axTab, CGWindowID wid, pid_t pid, NSString *appName) {
    if (!appName) appName = @"UnknownApp";
    if (pid == 0) return @"STBL-INVALID";

    NSString *bundleID = nil;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    bundleID = app.bundleIdentifier ?: appName;

    CFTypeRef identifierRef = NULL;
    NSString *identifier = nil;
    if (AXUIElementCopyAttributeValue(axTab, CFSTR("AXIdentifier"), &identifierRef) == kAXErrorSuccess && identifierRef) {
        identifier = CFBridgingRelease(identifierRef);
    }

    if (!identifier || identifier.length == 0) {
        CFTypeRef titleRef = NULL;
        if (AXUIElementCopyAttributeValue(axTab, kAXTitleAttribute, &titleRef) == kAXErrorSuccess && titleRef) {
            NSString *title = CFBridgingRelease(titleRef);
            if (title.length > 0) identifier = title;
        }
    }

    NSString *parentHash = nil;
    AXUIElementRef parent = NULL;
    if (AXUIElementCopyAttributeValue(axTab, kAXParentAttribute, (CFTypeRef *)&parent) == kAXErrorSuccess && parent) {
        parentHash = [NSString stringWithFormat:@"%p", parent];
        CFRelease(parent);
    }

    NSString *raw = [NSString stringWithFormat:@"%@-%d-%u-%@-%@-%p", bundleID, pid, wid, identifier ?: @"<noid>", parentHash ?: @"<noparent>", axTab];

    NSString *hash = stableHashForWindow(raw);

    if ([hash hasPrefix:@"STBL-"]) {
        return [hash stringByReplacingOccurrencesOfString:@"STBL-" withString:@"STBL-TAB-"];
    }
    return [NSString stringWithFormat:@"STBL-TAB-%@", hash];
}

NSString *_windowType;

@synthesize windowType = _windowType;

- (NSString *)title {
    return [self resolvedTitle] ?: @"(untitled)";
}

- (NSString *)ownerName {
    if (_ownerName && ![_ownerName isEqualToString:@"Unknown"] && _ownerName.length > 0) {
        return _ownerName;
    }
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id app = nil;
    if ([self respondsToSelector:@selector(owner)]) {
        app = [self performSelector:@selector(owner)];
    }
    #pragma clang diagnostic pop

    if (app && [app respondsToSelector:@selector(name)]) {
        NSString *appName = [app performSelector:@selector(name)];
        if (appName.length > 0) {
            return appName;
        }
    }

    NSRunningApplication *runningApp = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    if (runningApp && runningApp.localizedName.length > 0) {
        return runningApp.localizedName;
    }

    return @"Unknown";
}

- (NSString *)bundleID {
    if (_bundleID && ![_bundleID isEqualToString:@"Unknown"] && _bundleID.length > 0) {
        return _bundleID;
    }

    pid_t pid = self.processIdentifier;
    if (pid <= 0) {
        return @"Unknown";
    }

    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app.bundleIdentifier) {
        _bundleID = app.bundleIdentifier;
        return _bundleID;
    }

    NSString *owner = self.ownerName;
    if (owner.length > 0) {
        for (NSRunningApplication *running in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if ([running.localizedName isEqualToString:owner]) {
                _bundleID = running.bundleIdentifier ?: @"Unknown";
                return _bundleID;
            }
        }
    }

    return _bundleID ?: @"Unknown";
}

- (AXUIElementRef)axElement {
    return self.axElementRef;
}

- (NSString *)resolvedTitle {
    NSString *title = [self stringForKey:kAXTitleAttribute];
    if (title && title.length > 0) {
        return title;
    }
    
    CFTypeRef minimizedValue = NULL;
    if (AXUIElementCopyAttributeValue(self.axElementRef, kAXMinimizedAttribute, &minimizedValue) == kAXErrorSuccess) {
        if (CFBooleanGetValue(minimizedValue)) {
            CFRelease(minimizedValue);
            return @"(minimized window)";
        }
        CFRelease(minimizedValue);
    }

    BOOL isMinimized = [[self numberForKey:kAXMinimizedAttribute] boolValue];
    pid_t pid = self.processIdentifier;
    NSString *appName = [[NSRunningApplication runningApplicationWithProcessIdentifier:pid] localizedName] ?: @"(Unknown App)";

    if (isMinimized) {
        AXUIElementRef appElement = AXUIElementCreateApplication(pid);
        if (appElement) {
            typedef AXError (*AXPrivCopyAttributeFn)(AXUIElementRef, CFStringRef, CFTypeRef *);
            static AXPrivCopyAttributeFn _AXPrivCopyAttributeValue = NULL;

            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
                if (handle) {
                    _AXPrivCopyAttributeValue = (AXPrivCopyAttributeFn)dlsym(handle, "_AXUIElementCopyAttributeValue");
                    #if DEBUG
                        if (_AXPrivCopyAttributeValue) {
                            //NSLog(@"[PaneKit] ✅ Loaded _AXUIElementCopyAttributeValue (private)");
                        } else {
                            //NSLog(@"[PaneKit] ⚠️ Failed to load _AXUIElementCopyAttributeValue");
                        }
                    #endif
                }
            });

            CFTypeRef axWindows = NULL;
            AXError result = kAXErrorFailure;

            result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindows);

            if ((result != kAXErrorSuccess || !axWindows) && _AXPrivCopyAttributeValue) {
                result = _AXPrivCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindows);
            }

            if (result == kAXErrorSuccess && axWindows) {
                NSArray *windowList = CFBridgingRelease(axWindows);
                
                for (id axWindow in windowList) {
                    AXUIElementRef windowRef = (__bridge AXUIElementRef)axWindow;
                    CFTypeRef titleValue = NULL;
                    if (AXUIElementCopyAttributeValue(windowRef, kAXTitleAttribute, &titleValue) == kAXErrorSuccess) {
                        NSString *candidate = CFBridgingRelease(titleValue);
                        if (candidate.length > 0) {
                            CFRelease(appElement);
                            return [NSString stringWithFormat:@"%@ — %@", appName, candidate];
                        }
                    }
                }
            }
            CFRelease(appElement);
        }

        CFArrayRef windowInfoArray = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
        if (windowInfoArray) {
            NSArray *windows = CFBridgingRelease(windowInfoArray);
            for (NSDictionary *info in windows) {
                NSNumber *winID = info[(NSString *)kCGWindowNumber];
                if (winID && winID.intValue == self.windowID) {
                    NSString *cgTitle = info[(NSString *)kCGWindowName];
                    if (cgTitle.length > 0) {
                        return [NSString stringWithFormat:@"%@ — %@", appName, cgTitle];
                    }
                }
            }
        }

        return [NSString stringWithFormat:@"%@ (minimized)", appName];
    }
    
    if([appName isEqual:@"(Unknown App)"] && self->_ownerName){
        appName = self->_ownerName;
    }

    return appName ?: @"<untitled>";
}

- (NSString *)role {
    return [self stringForKey:kAXRoleAttribute] ?: @"AXWindow";
}

- (NSString *)subrole {
    return [self stringForKey:kAXSubroleAttribute] ?: @"AXStandardWindow";
}

- (BOOL)isWindowMinimized {
    return [[self numberForKey:kAXMinimizedAttribute] boolValue];
}

- (BOOL)isNormalWindow {
    NSString *subrole = [self subrole];
    if (subrole) {
        return [subrole isEqualToString:(__bridge NSString *)kAXStandardWindowSubrole];
    }
    return YES;
}

+ (BOOL)isRealWindow:(PKWindow *)win {
    return [win isRealWindow];
}

- (BOOL)isRealWindow {
    pid_t pid = self.processIdentifier;
    CGWindowID windowID = self.windowID;
    if (pid <= 0) return NO;

    if (windowID == kCGNullWindowID) {
        AXUIElementRef appElement = AXUIElementCreateApplication(pid);
        if (!appElement) return NO;
        
        CFTypeRef axWindowsRef = NULL;
        if (AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindowsRef) != kAXErrorSuccess || !axWindowsRef) {
            CFRelease(appElement);
            return NO;
        }

        NSArray *axWindows = CFBridgingRelease(axWindowsRef);
        BOOL hasVisibleAXWindow = NO;

        for (id axWin in axWindows) {
            if (!axWin || CFGetTypeID((__bridge CFTypeRef)axWin) != AXUIElementGetTypeID()) continue;

            CFTypeRef visibleRef = NULL;
            BOOL isVisible = NO;
            if (AXUIElementCopyAttributeValue((__bridge AXUIElementRef)axWin, kAXVisibleAttribute, &visibleRef) == kAXErrorSuccess && visibleRef) {
                isVisible = CFBooleanGetValue(visibleRef);
                CFRelease(visibleRef);
            }

            CFTypeRef sizeRef = NULL;
            CGSize size = CGSizeZero;
            if (AXUIElementCopyAttributeValue((__bridge AXUIElementRef)axWin, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess && sizeRef) {
                AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
                CFRelease(sizeRef);
            }

            CFTypeRef roleRef = NULL;
            NSString *role = nil;
            if (AXUIElementCopyAttributeValue((__bridge AXUIElementRef)axWin, kAXRoleAttribute, &roleRef) == kAXErrorSuccess && roleRef) {
                role = CFBridgingRelease(roleRef);
            }

            BOOL isRealCandidate = ([role isEqualToString:@"AXWindow"] && size.width > 80 && size.height > 80);

            if (isRealCandidate) {
                hasVisibleAXWindow = YES;
                break;
            }
        }

        CFRelease(appElement);
        return hasVisibleAXWindow;
    }

    CFArrayRef windowListRef = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    NSArray *windowList = CFBridgingRelease(windowListRef);
    NSDictionary *cgWindowInfo = nil;
    for (NSDictionary *info in windowList) {
        NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
        if (ownerPID && ownerPID.intValue == pid) {
            NSNumber *cgID = info[(NSString *)kCGWindowNumber];
            if (cgID && cgID.intValue == windowID) {
                cgWindowInfo = info;
                break;
            }
        }
    }

    if (cgWindowInfo) {
        NSNumber *layerNum = cgWindowInfo[(NSString *)kCGWindowLayer];
        if (layerNum && layerNum.intValue > 0) return NO;

        NSString *title = cgWindowInfo[(NSString *)kCGWindowName];
        if (title.length == 0) {
            NSDictionary *boundsDict = cgWindowInfo[(NSString *)kCGWindowBounds];
            if (boundsDict) {
                CGFloat w = [boundsDict[@"Width"] doubleValue];
                CGFloat h = [boundsDict[@"Height"] doubleValue];
                if (w > 30 && h > 30) return YES;
            }

            if (self.isOnScreen || self.isWindowMinimized) {
                return YES;
            }

            return NO;
        }

        return YES;
    }

    AXUIElementRef appElement = AXUIElementCreateApplication(pid);
    if (!appElement) return YES;

    CFTypeRef axWindowsRef = NULL;
    AXError result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindowsRef);
    if (result != kAXErrorSuccess || !axWindowsRef) {
        CFRelease(appElement);
        return YES;
    }

    NSArray *axWindows = CFBridgingRelease(axWindowsRef);
    for (id axWindowObj in axWindows) {
        AXUIElementRef axWindow = (__bridge AXUIElementRef)axWindowObj;
        if (!axWindow || CFGetTypeID(axWindow) != AXUIElementGetTypeID()) continue;

        CGWindowID currentID = 0;
        if (_AXUIElementGetWindow_ptr(axWindow, &currentID) != kAXErrorSuccess || currentID != windowID) continue;

        NSString *role = [self stringForAXAttribute:kAXRoleAttribute ofElement:axWindow];
        NSString *subrole = [self stringForAXAttribute:kAXSubroleAttribute ofElement:axWindow];

        if ([role isEqualToString:@"AXWindow"] ||
            [role isEqualToString:@"AXDialog"] ||
            [role isEqualToString:@"AXUnknown"]) {

            if ([subrole isEqualToString:@"AXSystemDialog"] ||
                [subrole isEqualToString:@"AXSheet"] ||
                [subrole isEqualToString:@"AXFloatingWindow"]) {
                continue;
            }

            CGSize size = [self sizeForAXAttribute:kAXSizeAttribute ofElement:axWindow];
            if (size.width < 80 || size.height < 80) continue;

            CFRelease(appElement);
            return YES;
        }
    }

    CFRelease(appElement);
    return YES;
}

+ (instancetype)windowWithAXElementOnly:(AXUIElementRef)axElement {
    if (!axElement) return nil;

    PKWindow *win = [PKWindow alloc];
    if (!win) return nil;

    win->_axElement = (AXUIElementRef)CFRetain(axElement);
    win->__windowID = kCGNullWindowID;

    pid_t pid = 0;
    AXUIElementGetPid(axElement, &pid);
    win->_pid = pid;

    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app) {
        win->_bundleID = app.bundleIdentifier ?: @"<unknown>";
        win->_ownerName = app.localizedName ?: @"Unknown";
    }

    NSString *raw = [NSString stringWithFormat:@"%@-%d-%p", win->_bundleID ?: @"UnknownApp", pid, axElement];
    win->_stableID = stableHashForWindow(raw);

    win.frame = CGRectZero;
    win->_zIndex = 0;
    win->_isTab = NO;
    win->_isTabHost = NO;
    
    if (win->_pid <= 0) {
        pid_t fallbackPID = 0;
        if (AXUIElementGetPid(axElement, &fallbackPID) == kAXErrorSuccess && fallbackPID > 0) {
            win->_pid = fallbackPID;
        } else {
            NSRunningApplication *app = nil;
            for (NSRunningApplication *candidate in [[NSWorkspace sharedWorkspace] runningApplications]) {
                if ([candidate.localizedName isEqualToString:win->_ownerName]) {
                    app = candidate;
                    break;
                }
            }
            if (app) {
                win->_pid = app.processIdentifier;
                win->_bundleID = app.bundleIdentifier ?: win->_bundleID;
            }
        }
    }

    return win;
}

+ (NSArray<PKWindow *> *)filteredRealWindowsForApp:(PKApplication *)app {
    if (!app) return @[];
    pid_t pid = app.processIdentifier;
    if (pid <= 0) return @[];
    
    NSRunningApplication *runningApp = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!runningApp) return @[];
    
    NSString *bundleID = runningApp.bundleIdentifier ?: @"";
    NSString *appName  = runningApp.localizedName ?: @"Unknown";
    
    if (appName.length == 0 || [appName isEqualToString:@"Unknown"]) return @[];

    static NSArray<NSString *> *excludedPrefixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedPrefixes = @[
            @"com.apple.loginwindow",
            @"com.apple.dock",
            @"com.apple.systemuiserver",
            @"com.apple.WindowManager",
            @"com.apple.notificationcenter",
            @"com.apple.ControlStrip",
            @"com.apple.Spotlight",
            @"com.apple.wifiagent",
            @"com.apple.TextInputMenuAgent",
            @"com.apple.airplayuiagent",
            @"com.apple.universalaccess",
            @"com.apple.corelocationagent",
            @"com.apple.FolderActionsDispatcher",
            @"com.apple.DockHelper",
            @"com.apple.AXVisualSupportAgent",
            @"com.apple.PowerChime"
        ];
    });

    for (NSString *prefix in excludedPrefixes) {
        if ([bundleID hasPrefix:prefix]) {
            return @[];
        }
    }
    
    AXUIElementRef appElement = AXUIElementCreateApplication(pid);
    if (!appElement) return @[];

    NSMutableArray<PKWindow *> *windows = [NSMutableArray array];

    CFTypeRef axWindows = NULL;
    AXError result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindows);

    if ((result != kAXErrorSuccess || !axWindows) && _AXPrivCopyAttributeValue) {
        result = _AXPrivCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindows);
    }
    
    if (result != kAXErrorSuccess || !axWindows) {
        //if (appElement) CFRelease(appElement);
        //return @[];
    }
    
    NSArray *axList = CFBridgingRelease(axWindows);
    
    for (id axWindow in axList) {
        if (!axWindow || CFGetTypeID((__bridge CFTypeRef)axWindow) != AXUIElementGetTypeID()) {
            continue;
        }

        PKWindow *win = [[PKWindow alloc] initWithAXElement:(__bridge AXUIElementRef)axWindow];
        if (!win) {
            win = [PKWindow windowWithAXElementOnly:(__bridge AXUIElementRef)axWindow];
            if (!win) {
                continue;
            }
            
            if (win && (win.pid <= 0 || win.ownerName.length == 0)) {
                pid_t fallbackPID = 0;
                AXUIElementGetPid((__bridge AXUIElementRef)axWindow, &fallbackPID);

                if (fallbackPID > 0) {
                    win->_pid = fallbackPID;
                } else {
                    NSRunningApplication *running = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                    if (running) {
                        win->_pid = running.processIdentifier;
                        win->_ownerName = running.localizedName ?: nil;
                        win->_bundleID = running.bundleIdentifier ?: nil;
                    }
                }

                if (!win.title || win.title.length == 0) {
                    CFTypeRef titleRef = NULL;
                    if (AXUIElementCopyAttributeValue((__bridge AXUIElementRef)axWindow, kAXTitleAttribute, &titleRef) == kAXErrorSuccess && titleRef) {
                        win->_title = [(__bridge NSString *)titleRef copy];
                        CFRelease(titleRef);
                    }
                }
            }
        }

        NSString *subrole = [win subrole];
        CGSize size = CGSizeZero;

        if (win.windowID == 0 || CGRectIsEmpty(win.frame) || win.frame.size.width < 5.0) {
            CGRect axRect = [win frameForAXElement:(__bridge AXUIElementRef)axWindow];
            if (CGRectIsEmpty(axRect) || axRect.size.width < 5.0) {
                NSScreen *main = [NSScreen mainScreen];
                if (main) axRect = [main frame];
            }
            if (!win) {
                win = [PKWindow windowWithAXElementOnly:(__bridge AXUIElementRef)axWindow];
            }
            if (!CGRectIsEmpty(axRect)) {
                win.fallbackFrame = axRect;
            }
            
            if(axRect.size.width > 5.0 && axRect.size.height > 5.0){
                size.width = axRect.size.width;
                size.height = axRect.size.height;
            }
        }
        
        if (size.width < 5.0 || size.height < 5.0) {
            NSDictionary *cgInfo = nil;
            CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
            NSArray *infos = CFBridgingRelease(windowList);

            for (NSDictionary *entry in infos) {
                NSNumber *pidNum = entry[(NSString *)kCGWindowOwnerPID];
                if (pidNum.intValue == pid) {
                    NSNumber *cgID = entry[(NSString *)kCGWindowNumber];
                    if (cgID && cgID.unsignedIntValue == win.windowID) {
                        cgInfo = entry;
                        break;
                    }
                }
            }

            if (cgInfo) {
                NSDictionary *boundsDict = cgInfo[(NSString *)kCGWindowBounds];
                if (boundsDict) {
                    CGRect rect;
                    if (CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)boundsDict, &rect)) {
                        size = rect.size;
                        win.frame = rect;
                    }
                }
            }
        }
        
        if (size.width < 5.0 || size.height < 5.0) {
            CGRect cgsRect = CGRectZero;
            typedef CGError (*CGSGetWindowBoundsFn)(int, uint32_t, CGRect *);
            typedef int (*CGSMainConnectionIDFn)(void);
            static CGSGetWindowBoundsFn _CGSGetWindowBounds = NULL;
            static CGSMainConnectionIDFn _CGSMainConnectionID = NULL;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
                if (handle) {
                    _CGSGetWindowBounds = (CGSGetWindowBoundsFn)dlsym(handle, "CGSGetWindowBounds");
                    _CGSMainConnectionID = (CGSMainConnectionIDFn)dlsym(handle, "CGSMainConnectionID");
                }
            });

            if (_CGSGetWindowBounds && _CGSMainConnectionID) {
                CGError err = _CGSGetWindowBounds(_CGSMainConnectionID(), win.windowID, &cgsRect);
                if (err == kCGErrorSuccess && cgsRect.size.width > 10 && cgsRect.size.height > 10) {
                    win.frame = cgsRect;
                    size = cgsRect.size;
                }
            }
        }
        
        if (size.width < 5.0 || size.height < 5.0) {
            CGRect axRect2 = [win frameForAXElement:(__bridge AXUIElementRef)axWindow];
            if (!CGRectIsEmpty(axRect2) && axRect2.size.width > 10 && axRect2.size.height > 10) {
                win.fallbackFrame = axRect2;
                win.frame = axRect2;
                size = axRect2.size;
            }
        }
        
        if (win.pid <= 0 && win->_pid > 0) {
            win.pid = win->_pid;
        }
        
        if (win._windowID == 0 && win.pid > 0) {
            win._windowID = (uint32_t)((win.pid & 0xFFFF) << 16) | (uint32_t)(arc4random_uniform(0xFFFF));
        }
        
        if((!win.ownerName || [win.ownerName  isEqual: @"Unknown"]) && win->_ownerName){
            win.ownerName = win->_ownerName;
        }
        
        if((!win.bundleID || [win.bundleID  isEqual: @"Unknown"]) && win->_bundleID){
            win.bundleID = win->_bundleID;
        }
                
        BOOL tooSmall = (size.width < 60 || size.height < 60);
        BOOL isDialog = [subrole isEqualToString:(__bridge NSString *)kAXSystemDialogSubrole] || [subrole isEqualToString:(__bridge NSString *)kAXSheetSubrole];

        if (tooSmall) {
            continue;
        }
        if (isDialog) {
            continue;
        }
        
        //NSLog(@"🩹 Endresultat: %@ → pid=%d title=%@", win->_ownerName, win->_pid, win.title);

        [windows addObject:win];
    }
    
    if (appElement) CFRelease(appElement);
    if (windows.count == 0) return @[];

    
    if ([bundleID isEqualToString:@"com.coteditor.CotEditor"]) {
        NSMutableArray *filtered = [NSMutableArray array];

        for (PKWindow *win in windows) {
            BOOL isMain = NO, isVisible = NO;
            CFTypeRef mainRef = NULL, visibleRef = NULL;

            if (AXUIElementCopyAttributeValue(win.axElementRef, kAXMainAttribute, &mainRef) == kAXErrorSuccess && mainRef) {
                isMain = CFBooleanGetValue(mainRef);
                CFRelease(mainRef);
            }
            if (AXUIElementCopyAttributeValue(win.axElementRef, kAXVisibleAttribute, &visibleRef) == kAXErrorSuccess && visibleRef) {
                isVisible = CFBooleanGetValue(visibleRef);
                CFRelease(visibleRef);
            }

            CGRect frame = [win frameForAXElement:win.axElementRef];
            BOOL hasValidFrame = !CGRectIsEmpty(frame) && frame.size.width > 50 && frame.size.height > 50;

            if (isMain || isVisible || hasValidFrame) {
                [filtered addObject:win];
            }
        }

        if (filtered.count == 0 && windows.count > 0) {
            filtered = [windows mutableCopy];
        }

        windows = filtered;
    }

    return [windows copy];
}

- (BOOL)isTabHost { return _isTabHost; }
- (NSArray<PKWindow *> *)tabs { return _tabs; }

+ (BOOL)isTabLikeOrRendererApp:(pid_t)pid {
    AXUIElementRef appElement = AXUIElementCreateApplication(pid);
    if (!appElement) return NO;

    CFTypeRef axWindowsRef = NULL;
    AXError result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, &axWindowsRef);
    if (result != kAXErrorSuccess || !axWindowsRef) {
        CFRelease(appElement);
        return NO;
    }

    NSArray *axWindows = CFBridgingRelease(axWindowsRef);
    if (axWindows.count < 3) {
        CFRelease(appElement);
        return NO;
    }

    NSMutableArray *frames = [NSMutableArray array];
    NSInteger visibleCount = 0;
    NSMutableArray *childCounts = [NSMutableArray array];
    NSInteger toolbarCount = 0;

    for (id ax in axWindows) {
        AXUIElementRef win = (__bridge AXUIElementRef)ax;

        CFTypeRef visRef = NULL;
        if (AXUIElementCopyAttributeValue(win, kAXVisibleAttribute, &visRef) == kAXErrorSuccess && visRef) {
            if (CFBooleanGetValue(visRef)) visibleCount++;
            CFRelease(visRef);
        }

        // Frame sammeln
        CGPoint pos; CGSize size;
        CFTypeRef posRef = NULL, sizeRef = NULL;
        if (AXUIElementCopyAttributeValue(win, kAXPositionAttribute, &posRef) == kAXErrorSuccess && AXUIElementCopyAttributeValue(win, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess) {
            AXValueGetValue(posRef, kAXValueCGPointType, &pos);
            AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
            CGRect rect = CGRectMake(pos.x, pos.y, size.width, size.height);
            [frames addObject:[NSValue valueWithBytes:&rect objCType:@encode(CGRect)]];
        }
        if (posRef) CFRelease(posRef);
        if (sizeRef) CFRelease(sizeRef);

        // Kinder zählen
        CFArrayRef kidsRef = NULL;
        if (AXUIElementCopyAttributeValues(win, kAXChildrenAttribute, 0, 10, &kidsRef) == kAXErrorSuccess && kidsRef) {
            NSArray *kids = CFBridgingRelease(kidsRef);
            [childCounts addObject:@(kids.count)];
        }

        // Toolbar prüfen
        CFTypeRef tbRef = NULL;
        if (AXUIElementCopyAttributeValue(win, CFSTR("AXToolbar"), &tbRef) == kAXErrorSuccess && tbRef) {
            toolbarCount++;
            CFRelease(tbRef);
        }
    }

    CGFloat meanΔ = 0;
    if (frames.count > 1) {
        CGFloat cx = 0, cy = 0;
        for (NSValue *v in frames) {
            CGRect r = v.rectValue;
            cx += CGRectGetMidX(r);
            cy += CGRectGetMidY(r);
        }
        cx /= frames.count; cy /= frames.count;
        for (NSValue *v in frames) {
            CGRect r = v.rectValue;
            meanΔ += hypot(CGRectGetMidX(r) - cx, CGRectGetMidY(r) - cy);
        }
        meanΔ /= frames.count;
    }

    NSInteger total = axWindows.count;
    NSInteger avgChildren = 0;
    for (NSNumber *n in childCounts) avgChildren += n.integerValue;
    if (childCounts.count > 0) avgChildren /= childCounts.count;

    double visRatio = (double)visibleCount / (double)total;
    double toolbarRatio = (double)toolbarCount / (double)total;

    BOOL manyWindows = total >= 4;
    BOOL moderateChildren = avgChildren <= 10;
    BOOL lowToolbar = toolbarRatio < 0.8;
    BOOL frameStable = meanΔ < 2000;
    BOOL notInvisible = visRatio <= 0.3;
    BOOL maybeJetBrains = avgChildren > 6 && toolbarRatio < 0.3;

    BOOL isRenderer = manyWindows && moderateChildren && lowToolbar && frameStable && notInvisible && !maybeJetBrains;

    CFRelease(appElement);
    return isRenderer;
}

- (BOOL)isSheet {
    return [[self stringForKey:kAXRoleAttribute] isEqualToString:(__bridge NSString *)kAXSheetRole];
}

- (BOOL)isActive {
    if ([[self numberForKey:kAXHiddenAttribute] boolValue]) return NO;
    if ([[self numberForKey:kAXMinimizedAttribute] boolValue]) return NO;
    return YES;
}

- (BOOL)isOnScreen {
    if (!self.isActive) return NO;

    CFArrayRef windowDescriptions = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowDescriptions) return NO;

    BOOL match = NO;
    for (NSDictionary *dictionary in (__bridge_transfer NSArray *)windowDescriptions) {
        NSNumber *windowNum = dictionary[(__bridge NSString *)kCGWindowNumber];
        if (windowNum && windowNum.intValue == self.windowID) {
            match = YES;
            break;
        }
    }
    return match;
}

- (BOOL)isFocused {
    PKWindow *focused = [PKWindow focusedWindow];
    if (!focused) return NO;

    AXUIElementRef selfRef = self.axElementRef;
    AXUIElementRef focusedRef = focused.axElementRef;

    if (!selfRef || !focusedRef) return NO;

    if (CFGetTypeID(selfRef) != AXUIElementGetTypeID() ||
        CFGetTypeID(focusedRef) != AXUIElementGetTypeID()) {
        return NO;
    }

    return CFEqual(selfRef, focusedRef);
}

- (NSScreen *)screen {
    CGRect windowFrame = [self frame];
    
    CGFloat lastVolume = 0;
    NSScreen *lastScreen = nil;
    
    for (NSScreen *screen in [NSScreen screens]) {
        CGRect screenFrame = [screen frameIncludingDockAndMenu];
        CGRect intersection = CGRectIntersection(windowFrame, screenFrame);
        CGFloat volume = intersection.size.width * intersection.size.height;
        
        if (volume > lastVolume) {
            lastVolume = volume;
            lastScreen = screen;
        }
    }
    
    return lastScreen;
}

- (void)moveToScreen:(NSScreen *)screen {
    self.position = screen.frameWithoutDockOrMenu.origin;
}

- (void)moveToSpace:(NSUInteger)space {
    NSEvent *event = [PKSystemWideElement eventForSwitchingToSpace:space];
    if (event == nil) return;
    
    [self moveToSpaceWithEvent:event];
}

- (void)moveToSpaceWithEvent:(NSEvent *)event {
    if (!event) return;

    PKAccessibilityElement *minimizeButtonElement = [self elementForKey:kAXMinimizeButtonAttribute];
    if (!minimizeButtonElement) return;

    CGRect minimizeButtonFrame = minimizeButtonElement.frame;
    CGRect windowFrame = self.frame;

    CGPoint mouseCursorPoint = {
        .x = CGRectIsEmpty(minimizeButtonFrame) ? windowFrame.origin.x + 5.0 : CGRectGetMidX(minimizeButtonFrame),
        .y = windowFrame.origin.y + fabs(windowFrame.origin.y - CGRectGetMinY(minimizeButtonFrame)) / 2.0
    };

    CGEventRef mouseMoveEvent = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, mouseCursorPoint, kCGMouseButtonLeft);
    CGEventRef mouseDragEvent = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDragged, mouseCursorPoint, kCGMouseButtonLeft);
    CGEventRef mouseDownEvent = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, mouseCursorPoint, kCGMouseButtonLeft);
    CGEventRef mouseUpEvent = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, mouseCursorPoint, kCGMouseButtonLeft);

    if (!mouseMoveEvent || !mouseDragEvent || !mouseDownEvent || !mouseUpEvent) {
        #if DEBUG
            //NSLog(@"[PaneKit] Failed to create CGEvent objects for moveToSpaceWithEvent:");
        #endif
        return;
    }

    CGEventSetFlags(mouseMoveEvent, 0);
    CGEventSetFlags(mouseDownEvent, 0);
    CGEventSetFlags(mouseUpEvent, 0);

    CGEventPost(kCGHIDEventTap, mouseMoveEvent);
    CGEventPost(kCGHIDEventTap, mouseDownEvent);
    CGEventPost(kCGHIDEventTap, mouseDragEvent);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [PKSystemWideElement switchToSpaceWithEvent:event];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGEventPost(kCGHIDEventTap, mouseUpEvent);
            CFRelease(mouseUpEvent);
        });
    });

    CFRelease(mouseMoveEvent);
    CFRelease(mouseDownEvent);
    CFRelease(mouseDragEvent);
}

- (void)maximize {
    CGRect screenRect = [[self screen] frameWithoutDockOrMenu];
    [self setFrame: screenRect];
}

- (void)minimize {
    [self setWindowMinimized:YES];
}

- (void)unMinimize {
    [self setWindowMinimized:NO];
}

- (void)setWindowMinimized:(BOOL)flag {
    [self setWindowProperty:NSAccessibilityMinimizedAttribute withValue:@(flag)];
}

- (BOOL)setWindowProperty:(NSString *)propType withValue:(id)value {
    if (!propType || !value) return NO;
    if (![value isKindOfClass:[NSNumber class]]) return NO;

    AXError result = AXUIElementSetAttributeValue(self.axElementRef, (__bridge CFStringRef)propType, (__bridge CFTypeRef)value);
    if (result != kAXErrorSuccess) {
        #if DEBUG
            [self logAXError:result context:[NSString stringWithFormat:@"setWindowProperty: %@", propType]];
        #endif
        return NO;
    }
    return YES;
}

- (BOOL)focusWindow {
    if (![PKUniversalAccessHelper isAccessibilityTrusted]) {
        return NO;
    }
    
    AXUIElementRef element = self.axElementRef;
    if (!element) {
        return NO;
    }
    
    CFTypeRef roleRef = NULL;
    NSString *role = nil;
    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &roleRef) == kAXErrorSuccess && roleRef) {
        role = CFBridgingRelease(roleRef);
    }
    
    BOOL isTab = [role containsString:@"Tab"] || [role containsString:@"Button"];

    if (isTab) {
        CFTypeRef parentRef = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXParentAttribute, &parentRef) == kAXErrorSuccess && parentRef) {
            AXUIElementRef host = (AXUIElementRef)parentRef;
            AXUIElementPerformAction(host, kAXRaiseAction);
            AXUIElementPerformAction(element, kAXPressAction);
            CFRelease(parentRef);
            return YES;
        }
        return NO;
    }

    pid_t pid = self.processIdentifier;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];

    if (app) {
        if (@available(macOS 14.0, *)) {
            [app activateWithOptions:NSApplicationActivateAllWindows];
        } else {
            [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
    }

    AXError raiseErr = AXUIElementPerformAction(element, kAXRaiseAction);
    if (raiseErr != kAXErrorSuccess) {
        [self logAXError:raiseErr context:@"AXUIElementPerformAction(kAXRaiseAction)"];

        AXError setFocusErr = AXUIElementSetAttributeValue([PKSystemWideElement systemWideElement].axElementRef, kAXFocusedWindowAttribute, element);
        if (setFocusErr == kAXErrorSuccess) {
            return YES;
        }
        return NO;
    }

    return YES;
}

- (BOOL)raiseWindow {
    //NSLog(@"[PaneKit] RaiseWindow");
    AXError error = AXUIElementPerformAction(self.axElementRef, kAXRaiseAction);
    if (error != kAXErrorSuccess) {
        #if DEBUG
            [self logAXError:error context:@"AXUIElementPerformAction(kAXRaiseAction)"];
        #endif
        return kCGNullWindowID;
    }
    return YES;
}

NSPoint PKMidpoint(NSRect r) {
    return NSMakePoint(NSMidX(r), NSMidY(r));
}

- (NSArray *)windowsInDirectionFn:(double(^)(double angle))whichDirectionFn shouldDisregardFn:(BOOL(^)(double deltaX, double deltaY))shouldDisregardFn {
    PKWindow *thisWindow = [PKWindow focusedWindow];
    NSPoint startingPoint = PKMidpoint([thisWindow frame]);
    
    NSArray *otherWindows = [thisWindow otherWindowsOnAllScreens];
    NSMutableArray *closestOtherWindows = [NSMutableArray arrayWithCapacity:[otherWindows count]];
    
    for (PKWindow *win in otherWindows) {
        NSPoint otherPoint = PKMidpoint([win frame]);
        
        double deltaX = otherPoint.x - startingPoint.x;
        double deltaY = otherPoint.y - startingPoint.y;
        
        if (shouldDisregardFn(deltaX, deltaY)) continue;
        
        double angle = atan2(deltaY, deltaX);
        double distance = hypot(deltaX, deltaY);
        
        double angleDifference = whichDirectionFn(angle);
        
        double score = distance / cos(angleDifference / 2.0);
        
        [closestOtherWindows addObject:@{
         @"score": @(score),
         @"win": win,
         }];
    }
    
    NSArray *sortedOtherWindows = [closestOtherWindows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* pair1, NSDictionary* pair2) {
        return [[pair1 objectForKey:@"score"] compare:[pair2 objectForKey:@"score"]];
    }];
    
    return sortedOtherWindows;
}

- (void)focusFirstValidWindowIn:(NSArray*)closestWindows {
    for (PKWindow *win in closestWindows) {
        if ([win focusWindow]) break;
    }
}

- (void)focusWindowLeft {
    [self focusFirstValidWindowIn:[self windowsToWest]];
}

- (void)focusWindowRight {
    [self focusFirstValidWindowIn:[self windowsToEast]];
}

- (void)focusWindowUp {
    [self focusFirstValidWindowIn:[self windowsToNorth]];
}

- (void)focusWindowDown {
    [self focusFirstValidWindowIn:[self windowsToSouth]];
}

- (nullable NSString *)stringForAXAttribute:(CFStringRef)attr ofElement:(AXUIElementRef)element {
    CFTypeRef val = NULL;
    if (AXUIElementCopyAttributeValue(element, attr, &val) == kAXErrorSuccess && val) {
        NSString *str = CFBridgingRelease(val);
        return str;
    }
    return nil;
}

- (nullable NSNumber *)boolForAXAttribute:(CFStringRef)attr ofElement:(AXUIElementRef)element {
    CFTypeRef val = NULL;
    if (AXUIElementCopyAttributeValue(element, attr, &val) == kAXErrorSuccess && val) {
        NSNumber *num = CFBridgingRelease(val);
        return num;
    }
    return nil;
}

- (CGSize)sizeForAXAttribute:(CFStringRef)attr ofElement:(AXUIElementRef)element {
    CFTypeRef val = NULL;
    CGSize size = CGSizeZero;
    if (AXUIElementCopyAttributeValue(element, attr, &val) == kAXErrorSuccess && val) {
        if (CFGetTypeID(val) == AXValueGetTypeID()) {
            AXValueGetValue(val, kAXValueCGSizeType, &size);
        }
        CFRelease(val);
    }
    return size;
}

- (CGRect)frameForAXElement:(AXUIElementRef)element {
    CGPoint pos = CGPointZero;
    CGSize size = CGSizeZero;
    CFTypeRef posRef = NULL, sizeRef = NULL;
    if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &posRef) == kAXErrorSuccess && AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &sizeRef) == kAXErrorSuccess && posRef && sizeRef) {
        AXValueGetValue(posRef, kAXValueCGPointType, &pos);
        AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
    }
    if (posRef) CFRelease(posRef);
    if (sizeRef) CFRelease(sizeRef);
    return CGRectMake(pos.x, pos.y, size.width, size.height);
}

NSArray<NSDictionary *> *PKzOrderForScreen(CGRect screenFrame) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    NSMutableArray *result = [NSMutableArray array];

    NSArray *windows = [[(__bridge NSArray *)list reverseObjectEnumerator] allObjects];
    NSInteger z = 0;
    for (NSDictionary *info in windows) {
        NSDictionary *bounds = info[(NSString *)kCGWindowBounds];
        if (!bounds) continue;

        CGRect rect = CGRectMake([bounds[@"X"] doubleValue], [bounds[@"Y"] doubleValue], [bounds[@"Width"] doubleValue], [bounds[@"Height"] doubleValue]);
        if (!CGRectIntersectsRect(rect, screenFrame)) continue;

        pid_t pid = [info[(NSString *)kCGWindowOwnerPID] intValue];
        NSNumber *windowID = info[(NSString *)kCGWindowNumber];
        if (!windowID) continue;

        [result addObject:@{
            @"pid": @(pid),
            @"windowID": windowID,
            @"zIndex": @(z++),
            @"frame": NSStringFromRect(NSRectFromCGRect(rect))
        }];
    }

    CFRelease(list);
    return result;
}

@end
