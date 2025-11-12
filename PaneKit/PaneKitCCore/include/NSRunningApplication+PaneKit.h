#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Extends NSRunningApplication with AXUIElement-level access and helper properties.
@interface NSRunningApplication (PaneKit)

/// Initializes an accessibility-aware wrapper for a running application.
/// Returns nil if the element does not represent a valid application.
- (nullable instancetype)initWithAXUIElement:(AXUIElementRef)element;

/// Returns YES if the application is an LSUIElement (agent-only, no Dock icon).
@property (readonly, nonatomic) BOOL isAgent NS_SWIFT_NAME(isAgent);

/// The underlying AXUIElement reference (if any).
@property (nullable, nonatomic, readonly) AXUIElementRef axElementRef;

@end

NS_ASSUME_NONNULL_END
