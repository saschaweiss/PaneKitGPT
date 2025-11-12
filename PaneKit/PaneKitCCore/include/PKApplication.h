#import <AppKit/AppKit.h>
#import "PKAccessibilityElement.h"
#import "PKWindow.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  Block type for the handling of accessibility notifications.
 *
 *  @param accessibilityElement The accessibility element that the accessibility notification pertains to. Will always be an element either owned by the application or the application itself.
 */
typedef void (^PKAXNotificationHandler)(PKAccessibilityElement * _Nonnull accessibilityElement);

/// Accessibility wrapper for application-level elements.
NS_SWIFT_NAME(Application)
@interface PKApplication : PKAccessibilityElement

+ (nullable instancetype)forProcessIdentifier:(pid_t)pid NS_SWIFT_NAME(init(pid:));

/// Attempts to construct an accessibility wrapper from an NSRunningApplication instance.
/// @param runningApplication A running application in the shared workspace.
/// @return A new PKApplication instance, or nil if accessibility access is not available.
+ (nullable instancetype)applicationWithRunningApplication:(NSRunningApplication * _Nonnull)runningApplication NS_SWIFT_NAME(init(running:));

/// Returns all PKApplication instances for currently running applications.
/// @return An array of all accessible running applications.
+ (nullable NSArray<PKApplication *> *)runningApplications;

@property (nonatomic, strong, readonly, nullable) NSRunningApplication *runningApplication;

+ (NSArray<PKApplication *> *)allRunningApplications;

- (instancetype)initWithAXElement:(AXUIElementRef _Nonnull)element NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAXUIElement:(AXUIElementRef _Nonnull)element NS_DESIGNATED_INITIALIZER;

/// Registers a notification handler for an accessibility notification.
/// The handler will be retained until unregistered.
/// @param notification The notification name (e.g. kAXFocusedWindowChangedNotification).
/// @param accessibilityElement The element to associate with the notification.
/// @param handler A block to invoke when the notification fires.
/// @return YES if registration succeeded; NO otherwise.
- (BOOL)observeNotification:(CFStringRef _Nonnull)notification withElement:(PKAccessibilityElement * _Nonnull)accessibilityElement handler:(PKAXNotificationHandler _Nonnull)handler;

/// Unregisters a previously registered notification handler.
/// @param notification The notification name.
/// @param accessibilityElement The element associated with the handler.
- (void)unobserveNotification:(CFStringRef _Nonnull)notification withElement:(PKAccessibilityElement * _Nonnull)accessibilityElement;

/// Returns all window elements associated with the application.
@property (nonatomic, readonly, copy) NSArray<PKWindow *> *windows;

/// Returns only currently visible windows for the application.
@property (nonatomic, readonly, copy) NSArray<PKWindow *> *visibleWindows;

/// The localized title of the application.
@property (nonatomic, readonly, copy, nullable) NSString *title;

/// Whether the application is currently hidden.
@property (nonatomic, readonly, getter=isHidden) BOOL hidden;

/// Hides the application (if visible).
- (void)hide;

/// Unhides the application (if hidden).
- (void)unhide;

/// Sends the application a standard termination signal (SIGTERM).
- (void)kill;

/// Sends the application a forced termination signal (SIGKILL).
- (void)kill9;

/// Clears any cached window list so subsequent calls reflect the current system state.
- (void)dropWindowsCache;

@end

NS_ASSUME_NONNULL_END
