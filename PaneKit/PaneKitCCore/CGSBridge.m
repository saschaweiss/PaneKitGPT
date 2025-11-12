#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma mark - CGS Type Definitions

typedef int32_t CGSConnectionID;
typedef uint32_t CGSWindowID;
typedef int32_t CGSError;

typedef CGSConnectionID (*CGSMainConnectionIDFn)(void);
typedef CGSError (*CGSGetOnScreenWindowListFn)(CGSConnectionID cid, CGSConnectionID owner, int maxCount, CGSWindowID *list, int *outCount);
typedef CGSError (*CGSGetWindowLevelFn)(CGSConnectionID cid, CGSWindowID wid, int *level);
typedef CGSError (*CGSOrderWindowFn)(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
typedef CGSError (*CGSGetWindowBoundsFn)(CGSConnectionID cid, CGSWindowID wid, CGRect *outBounds);
typedef CGSError (*CGSMoveWindowFn)(CGSConnectionID cid, CGSWindowID wid, float x, float y);
typedef CGSError (*CGSSetWindowAlphaFn)(CGSConnectionID cid, CGSWindowID wid, float alpha);
typedef CGSError (*CGSSetWindowLevelFn)(CGSConnectionID cid, CGSWindowID wid, int level);

#pragma mark - Static Function Pointers

static CGSMainConnectionIDFn _CGSMainConnectionID = NULL;
static CGSGetOnScreenWindowListFn _CGSGetOnScreenWindowList = NULL;
static CGSGetWindowLevelFn _CGSGetWindowLevel = NULL;
static CGSOrderWindowFn _CGSOrderWindow = NULL;
static CGSGetWindowBoundsFn _CGSGetWindowBounds = NULL;
static CGSMoveWindowFn _CGSMoveWindow = NULL;
static CGSSetWindowAlphaFn _CGSSetWindowAlpha = NULL;
static CGSSetWindowLevelFn _CGSSetWindowLevel = NULL;

#pragma mark - Symbol Loader

__attribute__((constructor))
static void _PaneKitLoadPrivateCGS(void) {
    void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    if (!handle) return;

    _CGSMainConnectionID = (CGSMainConnectionIDFn)dlsym(handle, "CGSMainConnectionID");
    _CGSGetOnScreenWindowList = (CGSGetOnScreenWindowListFn)dlsym(handle, "CGSGetOnScreenWindowList");
    _CGSGetWindowLevel = (CGSGetWindowLevelFn)dlsym(handle, "CGSGetWindowLevel");
    _CGSOrderWindow = (CGSOrderWindowFn)dlsym(handle, "CGSOrderWindow");
    _CGSGetWindowBounds = (CGSGetWindowBoundsFn)dlsym(handle, "CGSGetWindowBounds");
    _CGSMoveWindow = (CGSMoveWindowFn)dlsym(handle, "CGSMoveWindow");
    _CGSSetWindowAlpha = (CGSSetWindowAlphaFn)dlsym(handle, "CGSSetWindowAlpha");
    _CGSSetWindowLevel = (CGSSetWindowLevelFn)dlsym(handle, "CGSSetWindowLevel");

    #if DEBUG
        //NSLog(@"[PaneKit] ✅ CGSBridge loaded private CoreGraphics symbols (extended mode).");
    #endif
}

#pragma mark - Public CGS Wrapper API

CGSConnectionID CGSMainConnection(void) {
    return _CGSMainConnectionID ? _CGSMainConnectionID() : 0;
}

NSArray<NSNumber *> *CGSAllWindowIDs(void) {
    if (!_CGSGetOnScreenWindowList) return @[];
    CGSConnectionID cid = CGSMainConnection();
    CGSWindowID list[8192];
    int count = 0;
    CGError err = _CGSGetOnScreenWindowList(cid, cid, 8192, list, &count);
    if (err != 0 || count <= 0) return @[];

    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [ids addObject:@(list[i])];
    }
    return [ids copy];
}

NSInteger CGSWindowLevelForID(CGSWindowID wid) {
    if (!_CGSGetWindowLevel) return -1;
    CGSConnectionID cid = CGSMainConnection();
    int level = 0;
    CGError err = _CGSGetWindowLevel(cid, wid, &level);
    if (err != 0) return -1;
    return level;
}

BOOL CGSBringWindowToFront(CGSWindowID wid) {
    if (!_CGSOrderWindow) return NO;
    CGSConnectionID cid = CGSMainConnection();
    CGError err = _CGSOrderWindow(cid, wid, 1, 0);
    return (err == 0);
}

CGRect CGSWindowBoundsForID(CGSWindowID wid) {
    CGRect bounds = CGRectZero;
    if (!_CGSGetWindowBounds) return bounds;
    CGSConnectionID cid = CGSMainConnection();
    _CGSGetWindowBounds(cid, wid, &bounds);
    return bounds;
}

BOOL CGSMoveWindowTo(CGSWindowID wid, CGFloat x, CGFloat y) {
    if (!_CGSMoveWindow) return NO;
    CGSConnectionID cid = CGSMainConnection();
    return (_CGSMoveWindow(cid, wid, (float)x, (float)y) == 0);
}

BOOL CGSSetWindowAlphaForID(CGSWindowID wid, CGFloat alpha) {
    if (!_CGSSetWindowAlpha) return NO;
    CGSConnectionID cid = CGSMainConnection();
    return (_CGSSetWindowAlpha(cid, wid, (float)alpha) == 0);
}

BOOL CGSSetWindowLevelForID(CGSWindowID wid, NSInteger level) {
    if (!_CGSSetWindowLevel) return NO;
    CGSConnectionID cid = CGSMainConnection();
    return (_CGSSetWindowLevel(cid, wid, (int)level) == 0);
}
