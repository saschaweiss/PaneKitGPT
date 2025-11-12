#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  A category defining helper methods on NSScreen that are generally useful for window management.
 *  These utilities are safe for use with multiple displays and support macOS 15 coordinate semantics.
 */
@interface NSScreen (PaneKit)

/// Returns the frame of the screen adjusted to a global coordinate system.
/// @return The global frame of the screen, including the Dock and Menu Bar.
- (CGRect)frameIncludingDockAndMenu NS_SWIFT_NAME(frameIncludingDockAndMenu());

/// Returns the frame of the screen adjusted to a global coordinate system,
/// excluding the Dock and Menu Bar.
/// @return The global visible frame of the screen (excluding Dock/Menu Bar areas).
- (CGRect)frameWithoutDockOrMenu NS_SWIFT_NAME(frameWithoutDockOrMenu());

/// Returns the next screen in the global coordinate space, or nil if none exists.
/// @return The next NSScreen object in the global display arrangement.
- (nullable NSScreen *)nextScreen NS_SWIFT_NAME(nextScreen());

/// Returns the previous screen in the global coordinate space, or nil if none exists.
/// @return The previous NSScreen object in the global display arrangement.
- (nullable NSScreen *)previousScreen NS_SWIFT_NAME(previousScreen());

/// Rotates the screen by the supplied degrees (0, 90, 180, 270).
/// - Parameter degrees: An integer rotation angle.
/// - Returns: YES if successful, NO otherwise.
- (BOOL)rotateTo:(NSInteger)degrees NS_SWIFT_NAME(rotate(to:));

@end

NS_ASSUME_NONNULL_END
