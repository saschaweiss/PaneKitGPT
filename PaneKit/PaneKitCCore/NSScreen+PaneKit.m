#import "NSScreen+PaneKit.h"

@implementation NSScreen (PaneKit)

+ (NSScreen *)originScreen {
    for (NSScreen *screen in self.screens) {
        if (CGPointEqualToPoint(screen.frame.origin, CGPointZero)) {
            return screen;
        }
    }
    return nil;
}

- (CGRect)frameIncludingDockAndMenu {
    NSScreen *primaryScreen = [NSScreen originScreen];
    CGRect f = self.frame;
    f.origin.y = NSHeight([primaryScreen frame]) - NSHeight(f) - f.origin.y;
    return f;
}

- (CGRect)frameWithoutDockOrMenu {
    NSScreen *primaryScreen = [NSScreen originScreen];
    CGRect f = [self visibleFrame];
    f.origin.y = NSHeight([primaryScreen frame]) - NSHeight(f) - f.origin.y;
    return f;
}

- (BOOL)rotateTo:(NSInteger)degrees {
    if (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270) {
        #if DEBUG
            //NSLog(@"[PaneKit] ⚠️ Unsupported rotation value: %ld (only 0, 90, 180, 270 allowed).", (long)degrees);
        #endif
        return NO;
    }

    NSRect frame = self.frame;
    CGDirectDisplayID displayIDs[8];
    CGDisplayCount displayCount = 0;
    CGError err = CGGetDisplaysWithRect(frame, 8, displayIDs, &displayCount);
    if (err != kCGErrorSuccess || displayCount < 1) {
        #if DEBUG
            //NSLog(@"[PaneKit] ❌ Unable to resolve display for frame %@ (err=%d, count=%u).", NSStringFromRect(frame), err, displayCount);
        #endif
        return NO;
    }

    CGDirectDisplayID displayID = displayIDs[0];
    io_service_t service = MACH_PORT_NULL;

    CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS) {
        io_service_t candidate;
        while ((candidate = IOIteratorNext(iter))) {
            CFNumberRef vendorID = IORegistryEntryCreateCFProperty(candidate, CFSTR(kDisplayVendorID), kCFAllocatorDefault, 0);
            CFNumberRef productID = IORegistryEntryCreateCFProperty(candidate, CFSTR(kDisplayProductID), kCFAllocatorDefault, 0);

            uint32_t vID = 0, pID = 0;
            if (vendorID && productID) {
                CFNumberGetValue(vendorID, kCFNumberIntType, &vID);
                CFNumberGetValue(productID, kCFNumberIntType, &pID);

                if (CGDisplayVendorNumber(displayID) == vID && CGDisplayModelNumber(displayID) == pID) {
                    service = candidate;
                    break;
                }
            }
            if (vendorID) CFRelease(vendorID);
            if (productID) CFRelease(productID);
            IOObjectRelease(candidate);
        }
        IOObjectRelease(iter);
    }

    if (service == MACH_PORT_NULL) {
        #if DEBUG
            //NSLog(@"[PaneKit] ❌ Failed to find IOService for display ID %u (vendor/model lookup failed).", displayID);
        #endif
        return NO;
    }

    IOOptionBits rotationFlag = (IOOptionBits)(0x00000400 | (((NSUInteger)degrees / 90) << 16));
    IOReturn result = IOServiceRequestProbe(service, rotationFlag);
    IOObjectRelease(service);

    #if DEBUG
        if (result != kIOReturnSuccess) {
            //NSLog(@"[PaneKit] ⚠️ IOServiceRequestProbe failed (code=0x%x).", result);
        } else {
            //NSLog(@"[PaneKit] ✅ Display rotation %ld° applied to display %u.", (long)degrees, displayID);
        }
    #endif
    return (result == kIOReturnSuccess);
}

- (NSScreen *)nextScreen {
    NSArray *screens = [NSScreen screens];
    NSUInteger idx = [screens indexOfObject:self];

    idx += 1;
    if (idx == [screens count]) idx = 0;

    return [screens objectAtIndex:idx];
}

- (NSScreen *)previousScreen {
    NSArray *screens = [NSScreen screens];
    NSUInteger idx = [screens indexOfObject:self];

    idx -= 1;
    if (idx == -1) idx = [screens count] - 1;

    return [screens objectAtIndex:idx];
}

@end
