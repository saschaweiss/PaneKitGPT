#import "PKUniversalAccessHelper.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation PKUniversalAccessHelper

static BOOL _cachedAccessibilityTrust = NO;
static BOOL _hasCachedTrustValue = NO;

+ (BOOL)isAccessibilityTrusted {
    return [self isAccessibilityTrustedPromptUser:NO];
}

+ (BOOL)isAccessibilityTrustedPromptUser:(BOOL)prompt {
    // Use cached value if already checked and no prompt requested
    if (_hasCachedTrustValue && !prompt) {
        #if DEBUG
            //NSLog(@"[PaneKit] ℹ️ Using cached accessibility trust state: %@", _cachedAccessibilityTrust ? @"YES" : @"NO");
        #endif
        return _cachedAccessibilityTrust;
    }

    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    };
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    #if DEBUG
        if (!trusted) {
            //NSLog(@"[PaneKit] ⚠️ Accessibility permission not granted (trusted = NO, prompt = %@)", prompt ? @"YES" : @"NO");
        } else {
            //NSLog(@"[PaneKit] ✅ Accessibility permission granted.");
        }
    #endif

    // Cache result for subsequent lookups
    _cachedAccessibilityTrust = trusted;
    _hasCachedTrustValue = YES;

    return trusted;
}

/// Forces re-evaluation of TCC trust, e.g. if user toggled permissions in System Settings.
+ (void)refreshAccessibilityTrustCache {
    _hasCachedTrustValue = NO;
    (void)[self isAccessibilityTrustedPromptUser:NO];
}

static CGEventRef _PaneKitDummyTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    return event;
}

+ (BOOL)hasInputMonitoringPermission {
    CGEventTapLocation loc = kCGHIDEventTap;
    CFMachPortRef tap = CGEventTapCreate(loc, kCGHeadInsertEventTap, 0, kCGEventMaskForAllEvents, _PaneKitDummyTapCallback, NULL);
    if (!tap) {
        #if DEBUG
            //NSLog(@"[PaneKit] ⚠️ No Input Monitoring permission (CGEventTapCreate failed).");
        #endif
        return NO;
    }
    CFRelease(tap);
    return YES;
}

@end
