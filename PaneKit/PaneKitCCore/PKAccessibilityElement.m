#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import "PKAccessibilityElement.h"
#import "PKApplication.h"

#define kAXEnhancedUserInterfaceKey CFSTR("AXEnhancedUserInterface")

typedef AXError (*AXUIElementSetParameterizedAttributeValue_t)(AXUIElementRef element, CFStringRef attribute, CFStringRef parameter, CFTypeRef value);
typedef AXError (*AXUIElementCopyParameterizedAttributeValue_t)(AXUIElementRef element,CFStringRef attribute, CFStringRef parameter, CFTypeRef * _Nullable value);

static AXUIElementSetParameterizedAttributeValue_t _AXUIElementSetParameterizedAttributeValue = NULL;
static AXUIElementCopyParameterizedAttributeValue_t _AXUIElementCopyParameterizedAttributeValue = NULL;

static const CFStringRef kPKAXFrameAttribute = CFSTR("AXFrame");
static const CFStringRef kPKAXMainAttribute  = CFSTR("AXMain");

__attribute__((constructor))
static void _PKLoadPrivateAXSymbols(void) {
    void *handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
    if (!handle) return;

    _AXUIElementSetParameterizedAttributeValue = (AXUIElementSetParameterizedAttributeValue_t)dlsym(handle, "AXUIElementSetParameterizedAttributeValue");
    _AXUIElementCopyParameterizedAttributeValue = (AXUIElementCopyParameterizedAttributeValue_t)dlsym(handle, "AXUIElementCopyParameterizedAttributeValue");
}

static inline AXError PKLAXSetParameterizedValue(AXUIElementRef element, CFStringRef attribute, CFStringRef parameter, CFTypeRef value){
    if (_AXUIElementSetParameterizedAttributeValue) return _AXUIElementSetParameterizedAttributeValue(element, attribute, parameter, value);
    return kAXErrorAttributeUnsupported;
}

static inline AXError PKLAXCopyParameterizedValue(AXUIElementRef element, CFStringRef attribute, CFStringRef parameter, CFTypeRef * _Nullable value){
    if (_AXUIElementCopyParameterizedAttributeValue) return _AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, value);
    return kAXErrorAttributeUnsupported;
}

static AXError SafeAXUIElementSetAttributeValue(AXUIElementRef element, CFStringRef key, CFTypeRef value) {
    if (!element || CFGetTypeID(element) != AXUIElementGetTypeID()) {
        return kAXErrorInvalidUIElement;
    }

    AXError error = AXUIElementSetAttributeValue(element, key, value);
    return error;
}

@interface PKAccessibilityElement ()
@property (nonatomic, assign, nonnull) AXUIElementRef axElementRef;
@end

@implementation PKAccessibilityElement

#pragma mark Lifecycle

- (instancetype)init { return nil; }

- (instancetype)initWithAXElement:(AXUIElementRef)axElementRef {
    NSParameterAssert(axElementRef);
    self = [super init];
    if (self) {
        _axElementRef = (AXUIElementRef)CFRetain(axElementRef);
    }
    return self;
}

- (nullable instancetype)initWithAXUIElement:(AXUIElementRef)element {
    self = [super init];
    if (!self) return nil;
    if (!element) return nil;

    _axElementRef = (AXUIElementRef)CFRetain(element);
    return self;
}

- (void)dealloc {
    if (_axElementRef) {
        CFRelease(_axElementRef);
        _axElementRef = NULL;
    }
}

#pragma mark NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ <Title: %@> <pid: %d>", super.description, [self stringForKey:kAXTitleAttribute], self.processIdentifier];
}

- (BOOL)isEqual:(id)object {
    if (!object) return NO;

    if (![object isKindOfClass:[self class]]) return NO;

    PKAccessibilityElement *otherElement = object;
    if (CFEqual(self.axElementRef, otherElement.axElementRef)) return YES;

    return NO;
}

- (NSUInteger)hash {
    return CFHash(self.axElementRef);
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithAXElement:self.axElementRef];
}

#pragma mark Public Accessors

- (BOOL)isResizable {
    Boolean sizeWriteable = false;
    AXError error = AXUIElementIsAttributeSettable(self.axElementRef, kAXSizeAttribute, &sizeWriteable);
    if (error != kAXErrorSuccess) return NO;
    
    return sizeWriteable;
}

- (BOOL)isMovable {
    Boolean positionWriteable = false;
    AXError error = AXUIElementIsAttributeSettable(self.axElementRef, kAXPositionAttribute, &positionWriteable);
    if (error != kAXErrorSuccess) return NO;
    
    return positionWriteable;
}

- (nullable NSString *)stringForKey:(CFStringRef)accessibilityValueKey {
    if (!accessibilityValueKey) return nil;

    CFTypeRef valueRef = NULL;
    AXError error = AXUIElementCopyAttributeValue(self.axElementRef, accessibilityValueKey, &valueRef);

    if (error != kAXErrorSuccess || !valueRef || CFGetTypeID(valueRef) != CFStringGetTypeID()) {
        if (valueRef) CFRelease(valueRef);
        return nil;
    }

    return CFBridgingRelease(valueRef);
}

- (NSNumber *)numberForKey:(CFStringRef)accessibilityValueKey {
    CFTypeRef valueRef;
    AXError error;

    error = AXUIElementCopyAttributeValue(self.axElementRef, accessibilityValueKey, &valueRef);

    if (error != kAXErrorSuccess || !valueRef) return nil;
    if (CFGetTypeID(valueRef) != CFNumberGetTypeID() && CFGetTypeID(valueRef) != CFBooleanGetTypeID()) return nil;
    
    return CFBridgingRelease(valueRef);
}

- (NSArray *)arrayForKey:(CFStringRef)accessibilityValueKey {
    CFArrayRef arrayRef;
    AXError error;

    error = AXUIElementCopyAttributeValues(self.axElementRef, accessibilityValueKey, 0, 100, &arrayRef);

    if (error != kAXErrorSuccess || !arrayRef) return nil;

    return CFBridgingRelease(arrayRef);
}

- (PKAccessibilityElement *)elementForKey:(CFStringRef)accessibilityValueKey {
    CFTypeRef valueRef;
    AXError error;

    error = AXUIElementCopyAttributeValue(self.axElementRef, accessibilityValueKey, &valueRef);

    if (error != kAXErrorSuccess || !valueRef) return nil;
    if (CFGetTypeID(valueRef) != AXUIElementGetTypeID()) return nil;

    PKAccessibilityElement *element = [[PKAccessibilityElement alloc] initWithAXElement:(AXUIElementRef)valueRef];

    CFRelease(valueRef);

    return element;
}

- (CGRect)frame {
    CFTypeRef positionRef = NULL;
    CFTypeRef sizeRef = NULL;
    CGPoint point = CGPointZero;
    CGSize size = CGSizeZero;

    AXError error = AXUIElementCopyParameterizedAttributeValue(self.axElementRef, kPKAXFrameAttribute, kPKAXMainAttribute, &positionRef);

    if (error == kAXErrorAttributeUnsupported || !positionRef) {
        AXUIElementCopyAttributeValue(self.axElementRef, kAXPositionAttribute, &positionRef);
        AXUIElementCopyAttributeValue(self.axElementRef, kAXSizeAttribute, &sizeRef);
    }

    if (positionRef && CFGetTypeID(positionRef) == AXValueGetTypeID()) {
        AXValueGetValue(positionRef, kAXValueCGPointType, &point);
    }

    if (sizeRef && CFGetTypeID(sizeRef) == AXValueGetTypeID()) {
        AXValueGetValue(sizeRef, kAXValueCGSizeType, &size);
    }

    if (positionRef) CFRelease(positionRef);
    if (sizeRef) CFRelease(sizeRef);

    if (CGSizeEqualToSize(size, CGSizeZero)) return CGRectNull;

    return (CGRect){ point, size };
}

- (void)setFrame:(CGRect)frame {
    CGSize threshold = { .width = 25, .height = 25 };
    [self setFrame:frame withThreshold:threshold];
}

- (void)setFrame:(CGRect)frame withThreshold:(CGSize)threshold {
    CGRect currentFrame = self.frame;
    BOOL shouldSetSize = self.isResizable && (fabs(currentFrame.size.width - frame.size.width) >= threshold.width || fabs(currentFrame.size.height - frame.size.height) >= threshold.height);
    BOOL shouldMove = !CGPointEqualToPoint(currentFrame.origin, frame.origin);

    if (!shouldSetSize && !shouldMove) return;

    PKApplication *application = [self app];
    BOOL enhancedUI = [[application numberForKey:kAXEnhancedUserInterfaceKey] boolValue];
    if (enhancedUI) {
        [application setFlag:NO forKey:kAXEnhancedUserInterfaceKey];
    }

    AXValueRef frameValue = AXValueCreate(kAXValueCGRectType, &frame);
    if (frameValue) {
        AXError error = PKLAXSetParameterizedValue(self.axElementRef, kPKAXFrameAttribute, kPKAXMainAttribute, frameValue);

        if (error == kAXErrorAttributeUnsupported) {
            if (shouldSetSize) {
                [self setSize:frame.size];
            }
            if (shouldMove) {
                [self setPosition:frame.origin];
            }
        } else if (error != kAXErrorSuccess) {
            #if DEBUG
                //NSLog(@"[PaneKit] Failed to set frame: (%.1f, %.1f, %.1f, %.1f) (error %d)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, error);
            #endif
        }

        CFRelease(frameValue);
    }

    if (enhancedUI) {
        [application setFlag:YES forKey:kAXEnhancedUserInterfaceKey];
    }
}

- (void)setPosition:(CGPoint)position {
    if (CGPointEqualToPoint(position, [self frame].origin)) return;

    if (!self.axElementRef || CFGetTypeID(self.axElementRef) != AXUIElementGetTypeID()) {
        //NSLog(@"⚠️ [PaneKit] Invalid or nil AXUIElementRef – cannot set position");
        return;
    }

    AXValueRef positionRef = AXValueCreate(kAXValueCGPointType, &position);
    if (!positionRef) {
        //NSLog(@"⚠️ [PaneKit] Failed to create AXValue for position");
        return;
    }

    CFArrayRef attrNames = NULL;
    AXError attrError = AXUIElementCopyAttributeNames(self.axElementRef, &attrNames);
    if (attrError == kAXErrorSuccess && attrNames) {
        NSArray *attributes = CFBridgingRelease(attrNames);
        if (![attributes containsObject:(__bridge NSString *)kAXPositionAttribute]) {
            //NSLog(@"⚠️ [PaneKit] Element does not support kAXPositionAttribute");
            CFRelease(positionRef);
            return;
        }
    }

    AXError error = PKLAXSetParameterizedValue(self.axElementRef, kPKAXFrameAttribute, kPKAXMainAttribute, positionRef);

    if (error == kAXErrorAttributeUnsupported) {
        error = AXUIElementSetAttributeValue(self.axElementRef, kAXPositionAttribute, positionRef);
    }

    if (error != kAXErrorSuccess) {
        NSString *errorContext = [NSString stringWithFormat:@"setPosition (%.1f, %.1f)", position.x, position.y];
        [self logAXError:error context:errorContext];
    } else {
        //NSLog(@"✅ [PaneKit] Successfully set position to (%.1f, %.1f)", position.x, position.y);
    }

    CFRelease(positionRef);
}
- (void)setSize:(CGSize)size {
    if (CGSizeEqualToSize(size, [self frame].size)) return;

    AXValueRef sizeRef = AXValueCreate(kAXValueCGSizeType, &size);
    if (!sizeRef) return;

    AXError error = PKLAXSetParameterizedValue(self.axElementRef, kPKAXFrameAttribute, kPKAXMainAttribute, sizeRef);

    if (error == kAXErrorAttributeUnsupported) {
        error = AXUIElementSetAttributeValue(self.axElementRef, kAXSizeAttribute, sizeRef);
    }

    if (error != kAXErrorSuccess) {
        [self logAXError:error context:[NSString stringWithFormat:@"set size: (%.1f, %.1f)", size.width, size.height]];
    }

    CFRelease(sizeRef);
}

- (void)logAXError:(AXError)error context:(NSString *)context {
    if (error == kAXErrorSuccess) return;

    NSString *message = nil;
    switch (error) {
        case kAXErrorFailure: message = @"Generic accessibility API failure"; break;
        case kAXErrorIllegalArgument: message = @"Illegal argument to AX API"; break;
        case kAXErrorInvalidUIElement: message = @"Invalid AXUIElement reference"; break;
        case kAXErrorInvalidUIElementObserver: message = @"Invalid AXUIElement observer"; break;
        case kAXErrorCannotComplete: message = @"AX request could not complete"; break;
        case kAXErrorNotImplemented: message = @"AX API not implemented"; break;
        case kAXErrorNotificationAlreadyRegistered: message = @"Notification already registered"; break;
        case kAXErrorNotificationNotRegistered: message = @"Notification not registered"; break;
        case kAXErrorAPIDisabled: message = @"Accessibility API disabled"; break;
        case kAXErrorNoValue: message = @"No value returned"; break;
        case kAXErrorParameterizedAttributeUnsupported: message = @"Parameterized attribute unsupported"; break;
        default: message = @"Unknown accessibility error"; break;
    }

    #if DEBUG
        //NSLog(@"[PaneKit] AXError %d (%@) in context: %@", error, message, context);
    #endif
}

- (BOOL)setFlag:(BOOL)flag forKey:(CFStringRef)accessibilityValueKey {
    if (!accessibilityValueKey) return NO;

    AXError error = AXUIElementSetAttributeValue(self.axElementRef, accessibilityValueKey, flag ? kCFBooleanTrue : kCFBooleanFalse);

    if (error == kAXErrorSuccess) {
        return YES;
    }

    [self logAXError:error context:[NSString stringWithFormat:@"set flag for key %@", accessibilityValueKey]];

    return NO;
}

- (pid_t)processIdentifier {
    pid_t processIdentifier;
    AXError error;
    
    error = AXUIElementGetPid(self.axElementRef, &processIdentifier);
    
    if (error != kAXErrorSuccess) return -1;
    
    return processIdentifier;
}

- (PKApplication *)app {
    NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier];
    if (!runningApplication) {
        return nil;
    }
    return [PKApplication applicationWithRunningApplication:runningApplication];
}

@end
