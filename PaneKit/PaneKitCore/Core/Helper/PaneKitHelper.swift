import Foundation
import AppKit
import ApplicationServices
import os

public struct AX: RawRepresentable, Hashable, @unchecked Sendable {
    public let rawValue: CFString
    public var raw: CFString { rawValue }
    public var string: String { rawValue as String }
    public init(rawValue: CFString) { self.rawValue = rawValue }

    public static let main = AX(rawValue: "AXMain" as CFString)
    
    public static let title = AX(rawValue: "AXTitle" as CFString)
    public static let titleUIElement = AX(rawValue: "AXTitleUIElement" as CFString)
    public static let role = AX(rawValue: "AXRole" as CFString)
    public static let subrole = AX(rawValue: "AXSubrole" as CFString)
    public static let roleDescription = AX(rawValue: "AXRoleDescription" as CFString)
    public static let identifier = AX(rawValue: "AXIdentifier" as CFString)
        
    public static let enabled = AX(rawValue: "AXEnabled" as CFString)
    public static let focused = AX(rawValue: "AXFocused" as CFString)
    public static let minimized = AX(rawValue: "AXMinimized" as CFString)
    public static let fullscreen = AX(rawValue: "AXFullScreen" as CFString)
    public static let modal = AX(rawValue: "AXModal" as CFString)
    public static let hidden = AX(rawValue: "AXHidden" as CFString)
    public static let visible = AX(rawValue: "AXVisible" as CFString)
    
    public static let parent = AX(rawValue: "AXParent" as CFString)
    public static let children = AX(rawValue: "AXChildren" as CFString)
    public static let visibleChildren = AX(rawValue: "AXVisibleChildren" as CFString)
    public static let selectedChildren = AX(rawValue: "AXSelectedChildren" as CFString)
    
    public static let position = AX(rawValue: "AXPosition" as CFString)
    public static let size = AX(rawValue: "AXSize" as CFString)
    public static let frame = AX(rawValue: "AXFrame" as CFString)
    
    public static let windows = AX(rawValue: "AXWindows" as CFString)
    public static let mainWindow = AX(rawValue: "AXMainWindow" as CFString)
    public static let focusedWindow = AX(rawValue: "AXFocusedWindow" as CFString)
    public static let window = AX(rawValue: "AXWindow" as CFString)
    public static let windowRole = AX(rawValue: "AXWindowRole" as CFString)
    public static let windowNumber = AX(rawValue: "AXWindowNumber" as CFString)
    public static let document = AX(rawValue: "AXDocument" as CFString)
    
    public static let closeButton = AX(rawValue: "AXCloseButton" as CFString)
    public static let minimizeButton = AX(rawValue: "AXMinimizeButton" as CFString)
    public static let zoomButton = AX(rawValue: "AXZoomButton" as CFString)
    public static let fullScreenButton = AX(rawValue: "AXFullScreenButton" as CFString)
    public static let toolbarButton = AX(rawValue: "AXToolbarButton" as CFString)
    
    public static let sheets = AX(rawValue: "AXSheets" as CFString)
    public static let tabGroup = AX(rawValue: "AXTabGroup" as CFString)
    public static let tabs = AX(rawValue: "AXTabs" as CFString)
    public static let selectedTabs = AX(rawValue: "AXSelectedTabs" as CFString)
    public static let selected = AX(rawValue: "AXSelected" as CFString)
    
    public static let menuBar = AX(rawValue: "AXMenuBar" as CFString)
    public static let menuBarItems = AX(rawValue: "AXMenuBarItems" as CFString)
    public static let menu = AX(rawValue: "AXMenu" as CFString)
    public static let menuItem = AX(rawValue: "AXMenuItem" as CFString)
    public static let toolbar = AX(rawValue: "AXToolbar" as CFString)
    
    public static let applicationRole = AX(rawValue: "AXApplication" as CFString)
    public static let windowRoleString = AX(rawValue: "AXWindow" as CFString)
    public static let buttonRole = AX(rawValue: "AXButton" as CFString)
    public static let groupRole = AX(rawValue: "AXGroup" as CFString)
    public static let tabGroupRole = AX(rawValue: "AXTabGroup" as CFString)
    public static let tabButtonRole = AX(rawValue: "AXTabButton" as CFString)
    public static let sheetRole = AX(rawValue: "AXSheet" as CFString)
    public static let dialogRole = AX(rawValue: "AXDialog" as CFString)
    public static let drawerRole = AX(rawValue: "AXDrawValueer" as CFString)
    public static let toolbarRole = AX(rawValue: "AXToolbar" as CFString)
    public static let menuBarRole = AX(rawValue: "AXMenuBar" as CFString)
    public static let menuRole = AX(rawValue: "AXMenu" as CFString)
    public static let menuItemRole = AX(rawValue: "AXMenuItem" as CFString)
    
    public static let standardWindowSubrole = AX(rawValue: "AXStandardWindow" as CFString)
    public static let documentWindowSubrole = AX(rawValue: "AXDocumentWindow" as CFString)
    public static let dialogSubrole = AX(rawValue: "AXDialog" as CFString)
    public static let sheetSubrole = AX(rawValue: "AXSheet" as CFString)
    public static let systemDialogSubrole = AX(rawValue: "AXSystemDialogSubrole" as CFString)
    public static let floatingWindowSubrole = AX(rawValue: "AXFloatingWindow" as CFString)
    public static let utilityWindowSubrole = AX(rawValue: "AXUtilityWindow" as CFString)
    public static let drawerSubrole = AX(rawValue: "AXDrawValueer" as CFString)
    
    public static let url = AX(rawValue: "AXURL" as CFString)
    public static let childrenInNavigationOrder = AX(rawValue: "AXChildrenInNavigationOrder" as CFString)
    public static let zoomWindow = AX(rawValue: "AXZoomWindow" as CFString)
}

public struct AXAttr: RawRepresentable, Hashable, @unchecked Sendable {
    public let rawValue: CFString
    public var raw: CFString { rawValue }
    public var string: String { rawValue as String }
    public init(rawValue: CFString) { self.rawValue = rawValue }
    
    public static let position = AXAttr(rawValue: kAXPositionAttribute as CFString)
    public static let size = AXAttr(rawValue: kAXSizeAttribute as CFString)
    public static let title = AXAttr(rawValue: kAXTitleAttribute as CFString)
    public static let role = AXAttr(rawValue: kAXRoleAttribute as CFString)
    public static let subrole = AXAttr(rawValue: kAXSubroleAttribute as CFString)
    public static let frame = AXAttr(rawValue: "AXFrameAttribute" as CFString)
    public static let minimized = AXAttr(rawValue: kAXMinimizedAttribute as CFString)
    public static let tabs = AXAttr(rawValue: "AXTabsAtribute" as CFString)
    public static let windows = AXAttr(rawValue: kAXWindowsAttribute as CFString)
    public static let window = AXAttr(rawValue: kAXWindowAttribute as CFString)
    public static let children = AXAttr(rawValue: kAXChildrenAttribute as CFString)
    public static let visibleChildren = AXAttr(rawValue: kAXVisibleChildrenAttribute as CFString)
    public static let parent = AXAttr(rawValue: kAXParentAttribute as CFString)
    public static let description = AXAttr(rawValue: kAXDescriptionAttribute as CFString)
    public static let value = AXAttr(rawValue: kAXValueAttribute as CFString)
    public static let document = AXAttr(rawValue: kAXDocumentAttribute as CFString)
    public static let roleDescription = AXAttr(rawValue: kAXRoleDescriptionAttribute as CFString)
    public static let identifier = AXAttr(rawValue: kAXIdentifierAttribute as CFString)
    public static let menu = AXAttr(rawValue: "AXMenuAttribute" as CFString)
    public static let menuBar = AXAttr(rawValue: "AXMenuBarAttribute" as CFString)
    public static let help = AXAttr(rawValue: kAXHelpAttribute as CFString)
    public static let url = AXAttr(rawValue: kAXURLAttribute as CFString)
    public static let focused = AXAttr(rawValue: kAXFocusedAttribute as CFString)
    public static let focusedUIElement = AXAttr(rawValue: kAXFocusedUIElementAttribute as CFString)
    public static let focusedWindow = AXAttr(rawValue: kAXFocusedWindowAttribute as CFString)
    public static let minimizeButton = AXAttr(rawValue: kAXMinimizeButtonAttribute as CFString)
    public static let closeButton = AXAttr(rawValue: kAXCloseButtonAttribute as CFString)
    public static let zoomButton = AXAttr(rawValue: kAXZoomButtonAttribute as CFString)
    public static let fullScreen = AXAttr(rawValue: "AXFullScreenAttribute" as CFString)
    public static let visible = AXAttr(rawValue: "AXVisibleAttribute" as CFString)
    public static let menuItemCmdChar = AXAttr(rawValue: kAXMenuItemCmdCharAttribute as CFString)
    public static let menuItemCmdModifiers = AXAttr(rawValue: kAXMenuItemCmdModifiersAttribute as CFString)
    public static let tabGroup = AXAttr(rawValue: "AXTabGroupAttribute" as CFString)
    public static let selectedChildren = AXAttr(rawValue: kAXSelectedChildrenAttribute as CFString)
}

public struct AXAction: RawRepresentable, Hashable, @unchecked Sendable {
    public let rawValue: CFString
    public var raw: CFString { rawValue }
    public var string: String { rawValue as String }
    public init(rawValue: CFString) { self.rawValue = rawValue }

    public static let zoom = AXAction(rawValue: "kAXZoomAction" as CFString)
    public static let close = AXAction(rawValue: "AXClose" as CFString)
    public static let press = AXAction(rawValue: kAXPressAction as CFString)
    public static let raise = AXAction(rawValue: kAXRaiseAction as CFString)
    public static let minimize = AXAction(rawValue: "AXMinimizeAction" as CFString)
    public static let minimizeWindow = AXAction(rawValue: "kAXMinimizeWindowAction" as CFString)
    public static let zoomWindow = AXAction(rawValue: "kAXZoomWindowAction" as CFString)
}

public struct AXRole: RawRepresentable, Hashable, @unchecked Sendable  {
    public let rawValue: CFString
    public var raw: CFString { rawValue }
    public var string: String { rawValue as String }
    public init(rawValue: CFString) { self.rawValue = rawValue }
    
    public static let window = AXNotify(rawValue: kAXWindowRole as CFString)
    public static let radioButton = AXRole(rawValue: kAXRadioButtonRole as CFString)
    public static let radioButton = AXRole(rawValue: kAXTabGroupRole as CFString)
}

public struct AXNotify: RawRepresentable, Hashable, @unchecked Sendable {
    public let rawValue: CFString
    public var raw: CFString { rawValue }
    public var string: String { rawValue as String }
    public init(rawValue: CFString) { self.rawValue = rawValue }
    
    public static let focusedWindowChanged = AXNotify(rawValue: kAXFocusedWindowChangedNotification as CFString)
    public static let focusedUIElementChanged = AXNotify(rawValue: kAXFocusedUIElementChangedNotification as CFString)
    public static let mainWindowChanged = AXNotify(rawValue: kAXMainWindowChangedNotification as CFString)
    public static let titleChanged = AXNotify(rawValue: kAXTitleChangedNotification as CFString)
    public static let created = AXNotify(rawValue: kAXCreatedNotification as CFString)
    public static let windowCreated = AXNotify(rawValue: kAXWindowCreatedNotification as CFString)
    public static let windowMiniaturized = AXNotify(rawValue: kAXWindowMiniaturizedNotification as CFString)
    public static let windowDeminiaturized = AXNotify(rawValue: kAXWindowDeminiaturizedNotification as CFString)
    public static let moved = AXNotify(rawValue: kAXMovedNotification as CFString)
    public static let windowMoved = AXNotify(rawValue: kAXWindowMovedNotification as CFString)
    public static let resized = AXNotify(rawValue: kAXResizedNotification as CFString)
    public static let windowResized = AXNotify(rawValue: kAXWindowResizedNotification as CFString)
    public static let selectedChildrenChanged = AXNotify(rawValue: kAXSelectedChildrenChangedNotification as CFString)
    public static let uiElementDestroyed = AXNotify(rawValue: kAXUIElementDestroyedNotification as CFString)
    
    public static let tabOpened = AXNotify(rawValue: "AXNewTabOpenedNotification" as CFString)
    public static let tabCreated = AXNotify(rawValue: "AXTabCreatedNotification" as CFString)
    public static let tabClosed = AXNotify(rawValue: "AXTabClosedNotification" as CFString)
    public static let tabSelected = AXNotify(rawValue: "AXTabSelectedNotification" as CFString)
    public static let focusedTabChanged = AXNotify(rawValue: "AXFocusedTabChangedNotification" as CFString)
    
    public static let applicationActivated = AXNotify(rawValue: kAXApplicationActivatedNotification as CFString)
    public static let applicationDeactivated = AXNotify(rawValue: kAXApplicationDeactivatedNotification as CFString)
    public static let applicationHidden = AXNotify(rawValue: kAXApplicationHiddenNotification as CFString)
    public static let applicationShown = AXNotify(rawValue: kAXApplicationShownNotification as CFString)
    public static let applicationTerminated = AXNotify(rawValue: "AXApplicationTerminatedNotification" as CFString)
}

public enum CG {
    static let windowOwnerPID                                                   : String = kCGWindowOwnerPID                        as String
    static let windowOwnerName                                                  : String = kCGWindowOwnerName                       as String
    static let nullWindowID                                                     : UInt32 = kCGNullWindowID                          as UInt32
    static let windowLayer                                                      : String = kCGWindowLayer                           as String
    static let windowBounds                                                     : String = kCGWindowBounds                          as String
    static let windowNumber                                                     : String = kCGWindowNumber                          as String
}

// MARK: - Thread Helpers
@MainActor
func runOnMain(_ block: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async { @MainActor in block() }
    }
}

@MainActor
@discardableResult
func runSafelyOnMain<T>(delay: TimeInterval = 0, _ block: @escaping @Sendable () -> T) -> T? {
    if Thread.isMainThread {
        return block()
    } else {
        var result: T?
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { @MainActor in
            result = block()
        }
        return result
    }
}

@discardableResult
func runAsyncOnMain<T: Sendable>(delay: TimeInterval = 0, _ block: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
    if delay > 0 {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    return try await Task { @MainActor in
        try await block()
    }.value
}

// MARK: - Universal Extensions

extension Optional where Wrapped == String {
    func or(_ replacement: String) -> String {
        self?.ifEmpty(replacement) ?? replacement
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func insetBy(_ amount: CGFloat) -> CGRect {
        insetBy(dx: amount, dy: amount)
    }
    
    var shortDescription: String {
        "x:\(Int(origin.x)) y:\(Int(origin.y)) w:\(Int(size.width)) h:\(Int(size.height))"
    }
    
    func intersectsVisibleScreen() -> Bool {
        NSScreen.screens.contains(where: { $0.visibleFrame.intersects(self) })
    }

    func dominantScreen() -> NSScreen? {
        NSScreen.screens.max(by: { overlapArea(with: $0.frame) < overlapArea(with: $1.frame) })
    }

    private func overlapArea(with rect: CGRect) -> CGFloat {
        intersection(rect).size.width * intersection(rect).size.height
    }
}

extension Array where Element: Equatable {
    var unique: [Element] {
        reduce(into: [Element]()) { acc, next in
            if !acc.contains(next) { acc.append(next) }
        }
    }

    func first(whereNotNil predicate: (Element) -> Bool) -> Element? {
        first(where: predicate)
    }
    
    func asyncMap<T>(_ transform: @escaping (Element) async -> T) async -> [T] {
        var results = [T]()
        results.reserveCapacity(count)
        for element in self {
            let value = await transform(element)
            results.append(value)
        }
        return results
    }
}

extension String {
    var sanitizedBundleID: String {
        replacingOccurrences(of: ".", with: "_")
    }

    var isValidBundleID: Bool {
        contains(".") && !contains(" ")
    }
    
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }

    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func truncated(to length: Int, suffix: String = "…") -> String {
        count > length ? String(prefix(length)) + suffix : self
    }
    
    var stripped: String {
        components(separatedBy: .controlCharacters).joined()
    }

    var isLikelyURL: Bool {
        hasPrefix("http://") || hasPrefix("https://")
    }

    var toURL: URL? {
        URL(string: self)
    }
}

extension Bundle {
    static var currentName: String {
        main.infoDictionary?["CFBundleName"] as? String ?? "Unbekannt"
    }
    
    static var versionInfo: (version: String, build: String) {
        (main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0", main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
    }
}

extension NSRunningApplication {
    var safeBundleIdentifier: String {
        bundleIdentifier ?? "unknown.bundle.id"
    }
    
    var safeName: String {
        localizedName ?? "Unknown App"
    }
}

extension AXValue {
    var cgPointValue: CGPoint? {
        var p = CGPoint.zero
        return AXValueGetType(self) == .cgPoint ? (AXValueGetValue(self, .cgPoint, &p) ? p : nil) : nil
    }
    
    var cgSizeValue: CGSize? {
        var s = CGSize.zero
        return AXValueGetType(self) == .cgSize ? (AXValueGetValue(self, .cgSize, &s) ? s : nil) : nil
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func windowID() -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(self, &windowID)
        return result == .success ? windowID : nil
    }
}

@frozen
public struct SafeCFString: @unchecked Sendable {
    public let value: CFString
    public init(_ value: CFString) { self.value = value }
}

struct SafeAXObserver: @unchecked Sendable {
    let ref: AXObserver
}

// MARK: - Safe AX Accessors
@discardableResult
func safeAXValue<T>(_ attribute: CFString, from element: AXUIElement, as type: T.Type = T.self) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else { return nil }
    return value as? T
}

func safeAXArray(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, attribute, &value)
    return value as? [AXUIElement] ?? []
}

func safeAXPerform(_ action: CFString, on element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, action) == .success
}

func safeAXSetValue<T>(_ attribute: CFString, on element: AXUIElement, to value: T) -> Bool {
    AXUIElementSetAttributeValue(element, attribute, value as AnyObject) == .success
}

func safeAXIsAttributeSettable(_ attribute: CFString, for element: AXUIElement) -> Bool {
    var settable: DarwinBoolean = false
    AXUIElementIsAttributeSettable(element, attribute, &settable)
    return settable.boolValue
}

@inlinable
func safeAXAttribute(_ element: AXUIElement, _ attribute: AXAttr) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute.raw, &value)
    guard result == .success, let value = value else { return nil }
    return value
}

@inlinable
func safeAXAttribute(_ element: AXUIElement, _ attribute: AX) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute.raw, &value)
    guard result == .success, let value = value else { return nil }
    return value
}

@inline(__always)
func safeAXChildren(of element: AXUIElement) -> [AXUIElement]? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, AXAttr.children, &value) == .success, let children = value as? [AXUIElement] {
        return children
    }
    return nil
}

@inline(__always)
func safeAXRole(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, AXAttr.role, &value) == .success, let str = value as? String {
        return str
    }
    return ""
}

func safeAXSubrole(_ element: AXUIElement) -> String {
    safeAXValue(AXAttr.subrole.raw, from: element) ?? ""
}

@inline(__always)
func safeAXValue(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, AXAttr.value, &value) == .success, let str = value as? String {
        return str
    }
    return ""
}

@inline(__always)
func safeAXValue(of element: AXUIElement, attribute: AXAttr = .value) -> Any? {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, attribute.raw, &value) == .success {
        return value
    }
    return nil
}

@inline(__always)
func safeAXTitle(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, AXAttr.title, &value) == .success, let str = value as? String {
        return str
    }
    return ""
}

@inline(__always)
func safeAXDescription(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, AXAttr.description, &value) == .success, let str = value as? String {
        return str
    }
    return ""
}

@inline(__always)
func safeAXIdentifier(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, AXAttr.identifier, &value)
    if result == .success, let identifier = value as? String {
        return identifier
    }
    return ""
}

func safeAXInt(_ attribute: CFString, from element: AXUIElement) -> Int? {
    safeAXValue(attribute, from: element, as: Int.self)
}

@inlinable
func asAXElement(_ value: Any?) -> AXUIElement? {
    guard let val = value else { return nil }
    let cfVal = val as CFTypeRef
    return CFGetTypeID(cfVal) == AXUIElementGetTypeID() ? (val as! AXUIElement) : nil
}

@MainActor
@inline(__always)
func safeAXFrame(_ element: AXUIElement) -> CGRect {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    var position = CGPoint.zero
    var size = CGSize.zero

    if AXUIElementCopyAttributeValue(element, AXAttr.position, &posRef) == .success, let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID() {
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
    }

    if AXUIElementCopyAttributeValue(element, AXAttr.size, &sizeRef) == .success, let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
    }

    return CGRect(origin: position, size: size)
}

func safeAXBool(_ attribute: CFString, from element: AXUIElement) -> Bool? {
    if let num = safeAXValue(attribute, from: element, as: NSNumber.self) {
        return num.boolValue
    }
    return safeAXValue(attribute, from: element, as: Bool.self)
}

func safeAXCGRect(_ element: AXUIElement) -> CGRect? {
    guard
        let pos = safeAXValue(AXAttr.position.raw, from: element, as: CGPoint.self),
        let size = safeAXValue(AXAttr.size.raw, from: element, as: CGSize.self)
    else { return nil }
    return CGRect(origin: pos, size: size)
}

@inlinable
func AXUIElementHasAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool {
    var names: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &names)
    guard result == .success, let attrs = names as? [String] else { return false }
    return attrs.contains(attribute as String)
}

@inline(__always)
func AXUIElementHasAttribute(_ element: AXUIElement, _ attribute: AXAttr) -> Bool {
    AXUIElementHasAttribute(element, attribute.raw)
}

@inline(__always)
func AXUIElementHasAttribute(_ element: AXUIElement, _ attribute: AX) -> Bool {
    AXUIElementHasAttribute(element, attribute.raw)
}

@inline(__always)
func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: AXAttr, _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    AXUIElementCopyAttributeValue(element, attribute.raw, value)
}

@inline(__always)
func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: AX, _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    AXUIElementCopyAttributeValue(element, attribute.raw, value)
}

@inline(__always)
func AXUIElementPerformAction(_ element: AXUIElement, _ action: AXAction) -> AXError {
    AXUIElementPerformAction(element, action.raw)
}

@MainActor
@inline(__always)
func AXElementsEqual(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
    CFEqual(a, b)
}

@inlinable
@discardableResult
func AXUIElementSetValue<T>(_ element: AXUIElement, _ attribute: AXAttr, _ value: T) -> AXError {
    var cfValue: CFTypeRef?
    var mutable = value

    switch mutable {
    case var point as CGPoint:
        cfValue = AXValueCreate(.cgPoint, &point)
    case var size as CGSize:
        cfValue = AXValueCreate(.cgSize, &size)
    case var rect as CGRect:
        cfValue = AXValueCreate(.cgRect, &rect)
    default:
        cfValue = value as CFTypeRef
    }

    guard let cfValue else { return .illegalArgument }
    return AXUIElementSetAttributeValue(element, attribute.rawValue as CFString, cfValue)
}

func AXUIElementIsValid(_ element: AXUIElement, _ isValid: inout DarwinBoolean) -> AXError {
    var dummy: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, AXAttr.position, &dummy)
}

public struct AnySendable: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}
