#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A lightweight utility for checking Accessibility and Input Monitoring permissions.
/// Compatible with macOS 10.15+ (AXIsProcessTrustedWithOptions) and macOS 15 SDKs.
@interface PKUniversalAccessHelper : NSObject

/// Returns whether the app has Accessibility permission, without prompting the user.
/// Equivalent to `[PKUniversalAccessHelper isAccessibilityTrustedPromptUser:NO]`.
+ (BOOL)isAccessibilityTrusted;

/// Returns whether the app has Accessibility permission, optionally prompting the user to grant it.
/// @param prompt Whether to show the system prompt if not authorized.
/// @return YES if trusted, otherwise NO.
+ (BOOL)isAccessibilityTrustedPromptUser:(BOOL)prompt;

/// Returns whether the app has Input Monitoring permission (TCC protected).
/// Uses a non-private, sandbox-safe CGEventTapCreate-based check.
/// @return YES if permission is granted, otherwise NO.
+ (BOOL)hasInputMonitoringPermission;

@end

NS_ASSUME_NONNULL_END
