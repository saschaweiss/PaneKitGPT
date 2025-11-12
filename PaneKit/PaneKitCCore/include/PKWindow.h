#import <AppKit/AppKit.h>
#import "PKAccessibilityElement.h"
@class PKApplication;
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents an accessibility window element.
NS_SWIFT_NAME(PKWindow)

NSArray<NSDictionary *> *PKzOrderForScreen(CGRect screenFrame);

@interface PKWindow : PKAccessibilityElement

typedef NS_ENUM(NSInteger, PKWindowType) {
    PKWindowTypeWindow,
    PKWindowTypeTab
};

#pragma mark Window Accessors
/// Initializes a window from an AXUIElement reference.
/// Returns nil if the element does not represent a valid window.
- (instancetype)initWithAXUIElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAXUIElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(axUIElement:));

- (instancetype)initWithAXUIElement:(AXUIElementRef)element isTab:(BOOL)isTab parentTabHost:(nullable NSString *)parentTabHost;

- (instancetype)initWithAXUIElement:(AXUIElementRef)axuiElement isTab:(BOOL)isTab parentTabHost:(nullable NSString *)parentTabHost pid:(pid_t)pid bundleID:(nullable NSString *)bundleID;

//- (instancetype)initWithAXUIElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(axElement:));

- (instancetype)initWithAXElement:(AXUIElementRef)element;

NSString *computeStableIdentifierForWindow(AXUIElementRef axWindow, CGWindowID wid, pid_t pid, NSString *appName);
NSString *computeStableIdentifierForTab(AXUIElementRef axTab, CGWindowID wid, pid_t pid, NSString *appName);

+ (nullable PKWindow *)windowWithStableIdentifier:(NSString *)stableID NS_SWIFT_NAME(window(withStableIdentifier:));

/// Returns all windows currently known to the system.
+ (nullable NSArray<PKWindow *> *)allWindows;

/// Returns all windows that are currently visible.
+ (nullable NSArray<PKWindow *> *)visibleWindows;

/// Returns the currently focused window, or nil if none is focused.
+ (nullable PKWindow *)focusedWindow;

/// Returns all other windows on the same screen as this window.
- (nullable NSArray<PKWindow *> *)otherWindowsOnSameScreen;

/// Returns all other visible windows across all screens, excluding this one.
- (nullable NSArray<PKWindow *> *)otherWindowsOnAllScreens;

/// Returns all windows whose centers lie west of this window.
- (nullable NSArray<PKWindow *> *)windowsToWest;

/// Returns all windows whose centers lie east of this window.
- (nullable NSArray<PKWindow *> *)windowsToEast;

/// Returns all windows whose centers lie north of this window.
- (nullable NSArray<PKWindow *> *)windowsToNorth;

/// Returns all windows whose centers lie south of this window.
- (nullable NSArray<PKWindow *> *)windowsToSouth;

#pragma mark Window Properties

/// Returns the Core Graphics window ID.
- (CGWindowID)windowID;

@property (nonatomic, strong, readwrite) NSString *stableID;

/// Returns the window title, if available.
- (nullable NSString *)title;

/// Returns the window title, if available.
- (nullable NSString *)resolvedTitle;

/// Returns the human-readable name of the owning process (e.g. “Finder”, “Safari”, etc.)
- (NSString *)ownerName;

- (nullable NSString *)role;

/// Returns the underlying accessibility element for this window.
- (AXUIElementRef _Nullable)axElement NS_SWIFT_NAME(axElement());

+ (NSArray<PKWindow *> *)filteredRealWindowsForApp:(PKApplication *)app NS_SWIFT_NAME(filteredRealWindows(for:));

+ (nullable PKWindow *)updateWindowWithStableIdentifier:(NSString *)stableID NS_SWIFT_NAME(updateWindow(withStableIdentifier:));

/// Indicates whether the window is minimized.
@property (nonatomic, readonly, getter=isWindowMinimized) BOOL windowMinimized;

/// Indicates whether the window is a standard “normal” window.
@property (nonatomic, readonly, getter=isNormalWindow) BOOL normalWindow;

@property (nonatomic, readonly, getter=isRealWindow) BOOL realWindow;

/// Indicates whether the window represents a sheet.
@property (nonatomic, readonly, getter=isSheet) BOOL sheet;

/// Indicates whether the window is active (focused and visible).
@property (nonatomic, readonly, getter=isActive) BOOL active;

/// Indicates whether the window is currently on screen.
@property (nonatomic, readonly, getter=isOnScreen) BOOL onScreen;

@property (nonatomic, readonly, getter=isFocused) BOOL focused;

@property (nonatomic, assign, readwrite) NSInteger zIndex;

@property (nonatomic, strong, readwrite) NSString *title;
@property (nonatomic, strong, readwrite) NSString *ownerName;
@property (nonatomic, strong, readwrite) NSString *role;
@property (nonatomic, strong, readwrite) NSString *subrole;
@property (nonatomic, assign, readwrite) AXUIElementRef axElement;
@property (nonatomic, strong, readwrite) NSString *bundleID;
@property (nonatomic, assign, readwrite) PKWindowType windowType;

@property (nonatomic, assign, readwrite) BOOL isTabHost;
@property (nullable, nonatomic, strong, readwrite) NSArray<PKWindow *> *tabs;
@property (nonatomic, assign, readwrite) NSInteger tabIndex;

@property (nonatomic, strong, readwrite) NSString *parentTabHost;

@property (nonatomic, assign, readwrite) BOOL isTab;
@property (nonatomic, assign, readwrite) pid_t pid;

#pragma mark Screen

/// Returns the screen that contains the majority of this window’s area.
- (nullable NSScreen *)screen;

/// Moves the window to a specific screen, positioned at its origin.
- (void)moveToScreen:(NSScreen * _Nonnull)screen;

#pragma mark Space

/// Moves the window to a Mission Control space by numerical index (1–16).
- (void)moveToSpace:(NSUInteger)space;

/// Moves the window to a space using the given keyboard event shortcut.
- (void)moveToSpaceWithEvent:(NSEvent * _Nonnull)event;

#pragma mark - Window Actions
/// Maximizes the window to fill its current screen (excluding dock/menu bar).
- (void)maximize;

/// Minimizes the window.
- (void)minimize;

/// Restores a minimized window.
- (void)unMinimize;

- (void)refreshMetadata;

- (void)setWindowMinimized:(BOOL)flag;
- (BOOL)setWindowProperty:(NSString *)propType withValue:(id)value;

#pragma mark - Window Focus
/// Brings this window into focus.
/// @return YES if successful, NO otherwise.
- (BOOL)focusWindow;

/// Raises the window without focusing its application.
/// @return YES if successful, NO otherwise.
- (BOOL)raiseWindow;

/// Moves focus to the window west (left) of this one.
- (void)focusWindowLeft;

/// Moves focus to the window east (right) of this one.
- (void)focusWindowRight;

/// Moves focus to the window north (above) this one.
- (void)focusWindowUp;

/// Moves focus to the window south (below) this one.
- (void)focusWindowDown;

@end

@interface PKWindow (StableIdentifiers)
- (nullable NSString *)computeStableIdentifierForWindow;
- (nullable NSString *)computeStableIdentifierForTab;
@end

@interface PKWindow (FallbackFrame)
@property (nonatomic, assign) CGRect fallbackFrame;
@end

NS_ASSUME_NONNULL_END
