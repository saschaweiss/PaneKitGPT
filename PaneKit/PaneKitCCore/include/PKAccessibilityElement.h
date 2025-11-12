#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(AccessibilityElement)
@interface PKAccessibilityElement : NSObject <NSCopying>

/// The underlying Accessibility reference.
@property (nonatomic, readonly, assign, nonnull) AXUIElementRef axElementRef;

/// Create a new Accessibility Element with an existing AX reference.
- (nullable instancetype)initWithAXUIElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAXElement:(AXUIElementRef)element NS_DESIGNATED_INITIALIZER;

/// Unavailable default initializer.
- (instancetype)init NS_UNAVAILABLE;

/// The frame rectangle of the element in screen coordinates.
@property (nonatomic, readonly) CGRect frame;

/// Sets the frame to a new rectangle with a given threshold to avoid redundant calls.
- (void)setFrame:(CGRect)frame withThreshold:(CGSize)threshold;

/// Convenience setter for frame.
- (void)setFrame:(CGRect)frame;

/// Returns YES if the element’s position can be changed.
@property (nonatomic, readonly, getter=isMovable) BOOL movable;

/// Returns YES if the element’s size can be changed.
@property (nonatomic, readonly, getter=isResizable) BOOL resizable;

/// The process identifier (PID) that owns this accessibility element.
@property (nonatomic, readonly) pid_t processIdentifier;

/// Returns the associated application for this element, if available.
- (nullable id)app;

/// Fetches a string attribute by key.
- (nullable NSString *)stringForKey:(CFStringRef _Nonnull)accessibilityValueKey;

/// Fetches a numeric attribute (NSNumber or Bool) by key.
- (nullable NSNumber *)numberForKey:(CFStringRef _Nonnull)accessibilityValueKey;

/// Fetches an array of attributes by key.
- (nullable NSArray<id> *)arrayForKey:(CFStringRef _Nonnull)accessibilityValueKey;

/// Fetches a child accessibility element by key.
- (nullable instancetype)elementForKey:(CFStringRef _Nonnull)accessibilityValueKey;

/// Sets the size of the element.
- (void)setSize:(CGSize)size;

/// Sets the position of the element.
- (void)setPosition:(CGPoint)position;

/// Attempts to set an accessibility flag (Boolean AX attribute).
- (BOOL)setFlag:(BOOL)flag forKey:(CFStringRef _Nonnull)accessibilityValueKey;

/// Logs an accessibility error with context (debug only).
- (void)logAXError:(AXError)error context:(NSString *_Nonnull)context;

@end

NS_ASSUME_NONNULL_END
