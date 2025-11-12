#import <AppKit/AppKit.h>
#import "PKAccessibilityElement.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  Wrapper around the system-wide element.
 */
NS_SWIFT_NAME(SystemWideElement)
@interface PKSystemWideElement : PKAccessibilityElement

/**
 *  Returns a globally shared reference to the system-wide accessibility element.
 *
 *  @return A globally shared reference to the system-wide accessibility element.
 */
+ (instancetype)systemWideElement;

- (instancetype)initWithAXElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAXUIElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER;

/**
 *  Generates an event with the relevant shortcut information to switch to the space at the given index.
 *
 *  @param space The space to switch to.
 */
+ (nullable NSEvent *)eventForSwitchingToSpace:(NSUInteger)space;

/**
 *  Perform a space switch event.
 *
 *  @param event The event to perform the keyboard shortcut
 */
+ (void)switchToSpaceWithEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
