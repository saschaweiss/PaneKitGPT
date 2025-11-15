import Foundation
import AppKit
import ApplicationServices
import CoreGraphics


@MainActor
public final class PaneKitCore {
    public static let shared = PaneKitCore()
    private var isInitialized = false
    
    private init() {}

    public func start() async {
        guard !isInitialized else { return }
        isInitialized = true
        
        print("🟦 PaneKitCore: Initializing system...")
    }
}

public enum PaneKitWindowType: String, Codable, Sendable {
    case window
    case tab
}

public struct PaneKitConfiguration: Sendable {
    public static let shared = PaneKitConfiguration()
    public var notifyOnMainThread: Bool
    public var enableLogging: Bool

    public init(notifyOnMainThread: Bool = true, enableLogging: Bool = true) {
        self.notifyOnMainThread = notifyOnMainThread
        self.enableLogging = enableLogging
    }
}

@MainActor
public final class PaneKitWindow: Identifiable, Hashable, @unchecked Sendable {
    public private(set) var stableID: String
    public nonisolated let idForHashing: String

    public let pkWindow: PKWindow
    public let pid: pid_t
    public let element: AXUIElement

    public var bundleID: String
    public var appName: String
    public var title: String
    public var frame: CGRect
    public var role: String
    public var subrole: String
    public var screen: NSScreen?
    public var zIndex: Int
    public var isVisible: Bool
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var isFocused: Bool
    public var windowType: PaneKitWindowType = .window
    public var tabs: [PaneKitWindow]? = nil
    public var tabIndex: Int?
    public var parentID: String?
    
    public private(set) var lastUpdate: Date = .distantPast
    public var lastKnownFrame: CGRect = .zero
    
    private static var invalidPIDs = Set<pid_t>()
    
    @MainActor
    public var isPendingReplacement: Bool = false

    public init?(pkWindow: PKWindow) {
        var pid = pkWindow.pid
        let actualPID = pid
        if actualPID <= 0 {
            var axPid: pid_t = 0
            if AXUIElementGetPid(pkWindow.axElement, &axPid) == .success {
                pid = axPid
            }
        }
        
        guard pkWindow.axElement != nil as AXUIElement? else {
            return nil
        }
        if CFGetTypeID(pkWindow.axElement) != AXUIElementGetTypeID() {
            return nil
        }
        if CFGetTypeID(pkWindow.axElement) == AXUIElementGetTypeID() {
            var pidCheck: pid_t = 0
            if AXUIElementGetPid(pkWindow.axElement, &pidCheck) == .success {
                //print("🧩 Init check PID=\(pid) AX PID=\(pidCheck) AXElement(valid)")
            }
        }

        guard pid > 0 else {
            return nil
        }
        
        var testAttr: CFTypeRef?
        let axCheck = AXUIElementCopyAttributeValue(pkWindow.axElement, AXAttr.role, &testAttr)
        if axCheck != .success {
            return nil
        }

        guard !pkWindow.stableID.isEmpty else {
            return nil
        }
        
        self.pkWindow       = pkWindow
        self.pid            = pid
        self.element        = pkWindow.axElement

        self.stableID       = pkWindow.stableID
        self.idForHashing   = pkWindow.stableID

        self.bundleID       = pkWindow.bundleID.ifEmpty("unknown.bundle.id")
        self.appName        = pkWindow.ownerName.ifEmpty("Unbekannte App")
        self.title          = pkWindow.title.ifEmpty("").cleanedWindowTitle(for: pkWindow.bundleID)

        self.windowType     = pkWindow.isTab ? .tab : .window
        self.role           = pkWindow.role.ifEmpty("AXWindow")
        self.subrole        = pkWindow.subrole.ifEmpty("")

        self.frame          = pkWindow.frame.isEmpty ? .zero : pkWindow.frame
        self.isVisible      = pkWindow.isOnScreen
        self.isMinimized    = pkWindow.isWindowMinimized
        self.isFullscreen   = !pkWindow.isNormalWindow && pkWindow.isOnScreen
        self.isFocused      = pkWindow.isFocused
        self.zIndex         = pkWindow.zIndex
        self.screen         = pkWindow.screen() ?? NSScreen.main
        
        self.parentID       = pkWindow.parentTabHost
        
        self.lastUpdate = Date()
        
        //print("create PaneKitWindow (\(self.windowType)): \(self.appName) - \(self.title)")

        var isSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(pkWindow.axElement, AXAttr.title.raw, &isSettable) == .success {
            if !isSettable.boolValue {
                //Log.debug("ℹ️ \(appName): AXTitle is read-only (normal for most apps)")
            }
        }
    }
    
    private func refresh() {
        pkWindow.refreshMetadata()
    }

    public func updateAll() async {
        refresh()
        lastUpdate = Date()

        //title           = pkWindow.title
        frame           = frameFromAXElement()
        lastKnownFrame  = frame
        isVisible       = pkWindow.isOnScreen
        isMinimized     = pkWindow.isWindowMinimized
        isFullscreen    = !pkWindow.isNormalWindow && pkWindow.isOnScreen
        isFocused       = pkWindow.isFocused
        zIndex          = pkWindow.zIndex
        role            = pkWindow.role
        subrole         = pkWindow.subrole
        screen          = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
    }
    
    public func update(attributes: [CFString]) async {
        refresh()
        var changed = false
        
        for attr in attributes {
            switch attr {
                case AXAttr.title.rawValue:
                    let newTitle = pkWindow.title
                    if newTitle != title {
                        title = newTitle
                        changed = true
                    }

                case AXAttr.position.rawValue, AXAttr.size.rawValue:
                    let newFrame = frameFromAXElement()
                    if newFrame != frame {
                        frame = newFrame
                        lastKnownFrame = newFrame
                        changed = true
                    }

                case AXAttr.visible.rawValue:
                    let newVisible = pkWindow.isOnScreen
                    if newVisible != isVisible {
                        isVisible = newVisible
                        changed = true
                    }

                case AXAttr.minimized.rawValue:
                    let newMin = pkWindow.isWindowMinimized
                    if newMin != isMinimized {
                        isMinimized = newMin
                        changed = true
                    }

                case AXAttr.fullScreen.rawValue:
                    let newFull = !pkWindow.isNormalWindow && pkWindow.isOnScreen
                    if newFull != isFullscreen {
                        isFullscreen = newFull
                        changed = true
                    }

                case AXAttr.focused.rawValue:
                    let newFocus = pkWindow.isFocused
                    if newFocus != isFocused {
                        isFocused = newFocus
                        changed = true
                    }

                default:
                    continue
            }
        }
        
        lastUpdate = Date()
    }
    
    @MainActor
    public func updateStableID(_ newID: String) {
        self.stableID = newID
    }
    
    public func getTabs() async -> [PaneKitWindow] {
        guard windowType == .window else {
            return []
        }
        
        if let existingTabs = tabs, !existingTabs.isEmpty {
            return existingTabs
        }

        let tabElements = await PaneKitCollector.collectTabs(for: self)
        guard !tabElements.isEmpty else {
            return []
        }

        self.tabs = tabElements

        return tabElements
    }
    
    private func frameFromAXElement() -> CGRect {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var result = CGRect.zero

        let posStatus = AXUIElementCopyAttributeValue(element, AXAttr.position, &positionRef)
        if posStatus == .success, let posValue = positionRef, CFGetTypeID(posValue) == AXValueGetTypeID(){
            var cgPoint = CGPoint.zero
            if AXValueGetType(posValue as! AXValue) == .cgPoint, AXValueGetValue(posValue as! AXValue, .cgPoint, &cgPoint) {
                result.origin = cgPoint
            }
        }

        let sizeStatus = AXUIElementCopyAttributeValue(element, AXAttr.size, &sizeRef)
        if sizeStatus == .success, let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            var cgSize = CGSize.zero
            if AXValueGetType(sizeValue as! AXValue) == .cgSize, AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize) {
                result.size = cgSize
            }
        }

        if result.width < 0 || result.height < 0 {
            result = .zero
        }

        return result
    }

    nonisolated public static func == (lhs: PaneKitWindow, rhs: PaneKitWindow) -> Bool {
        lhs.idForHashing == rhs.idForHashing
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(idForHashing)
    }
    
    public var isValid: Bool {
        var isValid = DarwinBoolean(false)
        let result = AXUIElementIsValid(element, &isValid)
        return result == .success && isValid.boolValue
    }
}

@MainActor
public final class TabLoader: ObservableObject {
    @Published public var tabs: [String: [PaneKitWindow]] = [:]

    public init() {}

    public func loadTabs(for windows: [PaneKitWindow]) {
        Task {
            var loaded: [String: [PaneKitWindow]] = [:]
            for window in windows {
                let tabs = await window.getTabs()
                loaded[window.stableID] = tabs
            }

            await MainActor.run {
                self.tabs = loaded
            }
        }
    }
}

@MainActor
public extension PaneKitWindow {
    func focus() async {
        guard pkWindow.focus() else {
            return
        }
    }

    func raise() async {
        guard pkWindow.raise() else {
            return
        }
    }

    func minimize() async {
        pkWindow.minimize()
    }

    func restore() async {
        pkWindow.unMinimize()
    }

    func maximize() async {
        pkWindow.maximize()
    }

    func moveTo(screen: NSScreen) async {
        pkWindow.move(to: screen)
    }

    func moveTo(space: UInt) async {
        pkWindow.move(toSpace: space)
    }

    func moveToSpace(with event: NSEvent) async {
        pkWindow.moveToSpace(with: event)
    }

    func setMinimized(_ flag: Bool) async {
        pkWindow.setWindowMinimized(flag)
    }

    func setProperty(_ type: String, value: Any) async {
        pkWindow.setWindowProperty(type, withValue: value)
    }
    
    func close() async {
        _ = AXUIElementPerformAction(pkWindow.axElement, AXAction.close)
    }
    
    func resize(to size: CGSize, animated: Bool = false, duration: TimeInterval = 0.25) async {
        guard let controller = PaneKitControllerResolver.shared.controller(for: self) else {
            let fallback = DefaultController(window: self)
            await fallback.resize(window: self, to: size, animated: animated, duration: duration)
            return
        }

        await controller.resize(window: self, to: size, animated: animated, duration: duration)
    }

    func move(_ point: CGPoint, animated: Bool = false, duration: TimeInterval = 0.25) async {
        guard let controller = PaneKitControllerResolver.shared.controller(for: self) else {
            let fallback = DefaultController(window: self)
            await fallback.move(window: self, point: point, animated: animated, duration: duration)
            return
        }

        await controller.move(window: self, point: point, animated: animated, duration: duration)
    }
    
    func animatePosition(to target: CGPoint, duration: TimeInterval) async {
        let start = frame.origin
        let steps = max(1, Int(duration / 0.016))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = t * (2 - t)
            let intermediate = CGPoint(
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased
            )
            var p = intermediate
            if let v = AXValueCreate(.cgPoint, &p) {
                AXUIElementSetAttributeValue(pkWindow.axElement, AXAttr.position.raw, v)
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        frame.origin = target
        lastUpdate = Date()
    }

    func animateResize(to target: CGSize, duration: TimeInterval) async {
        let start = frame.size
        let steps = max(1, Int(duration / 0.016))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = t * (2 - t)
            let intermediate = CGSize(
                width: start.width + (target.width - start.width) * eased,
                height: start.height + (target.height - start.height) * eased
            )
            var s = intermediate
            if let v = AXValueCreate(.cgSize, &s) {
                AXUIElementSetAttributeValue(pkWindow.axElement, AXAttr.size.raw, v)
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        frame.size = target
        lastUpdate = Date()
    }
}

extension PaneKitWindowType {
    var description: String { self == .window ? "Window" : "Tab" }
}

extension PaneKitWindow {
    public var isTab: Bool { windowType == .tab }
    public var isWindow: Bool { windowType == .window }
    public var screenName: String { screen?.localizedName ?? "Unknown screen" }
    
    static func fromAXElement(_ element: AXUIElement) -> PaneKitWindow? {
        var frame = CGRect.zero
        var bundleID = "unknown"
        var title = "Untitled"
        var screen: NSScreen? = NSScreen.main
        var parentID: String?
        
        if let position = copyAXValue(for: kAXPositionAttribute, of: element) as? CGPoint,
           let size = copyAXValue(for: kAXSizeAttribute, of: element) as? CGSize {
            frame = CGRect(origin: position, size: size)
        }
        
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if let app = NSRunningApplication(processIdentifier: pid), let bid = app.bundleIdentifier {
            bundleID = bid
        }
        
        windowTitle = copyAXValue(for: AXAttr.title.raw, of: element) as? String
        screen = NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) }) ?? NSScreen.main
        
        if let parent = copyAXValue(for: AXAttr.parent.raw, of: element) as? AXUIElement {
            parentID = stableID(for: parent)
        }
        
        let stableID = stableID(for: element)
        
        let window = PaneKitWindow(
            stableID: stableID,
            bundleID: appBundleID ?? "unknown",
            title: windowTitle ?? "Untitled",
            frame: windowFrame,
            screen: screen,
            parentID: parentID,
            isFocused: false,
            zIndex: 0,
            windowType: .window
        )
        
        return window
    }
    
    private static func copyAXValue(for attribute: CFString, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, attribute, &value)
        return value
    }
    
    private static func stableID(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let ptr = Unmanaged.passUnretained(element).toOpaque()
        return "pid:\(pid)-ptr:\(UInt(bitPattern: ptr))"
    }
}

public struct AppCollectorResult {
    public let bundleID: String
    public let windows: [WindowGroup]

    public struct WindowGroup {
        public let window: PaneKitWindow
        public let tabs: [PaneKitWindow]
    }
}

extension PaneKitWindow: PaneKitControllable {
    public func move(to point: CGPoint) async {
        await move(point, animated: false, duration: 0.25)
    }

    public func resize(to size: CGSize) async {
        await resize(to: size, animated: false, duration: 0.25)
    }
}

@MainActor
public protocol PaneKitControllable: AnyObject, Identifiable, Sendable {
    associatedtype Identifier: Hashable
    var stableID: Identifier { get }
    var title: String { get }
    var isValid: Bool { get }

    func focus() async
    func minimize() async
    func restore() async
    func close() async
    func move(to point: CGPoint) async
    func resize(to size: CGSize) async
}

extension String {
    func cleanedWindowTitle(for bundleID: String) -> String {
        var title = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if title.contains("darwin-debug") || title.contains("bash -c") || title.contains("/Applications/Xcode.app") {
            if let dashRange = title.range(of: "—", options: .backwards) {
                title = String(title[dashRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
            } else if let appRange = title.range(of: #"\.app"#, options: .regularExpression) {
                title = String(title.prefix(upTo: appRange.upperBound))
            }
        }
        
        if title.contains("/"), title.components(separatedBy: "/").count > 2 {
            let last = title.components(separatedBy: "/").last ?? title
            if last.count < 50 { title = last }
        }

        let possibleAppName = bundleID.components(separatedBy: ".") .last?.replacingOccurrences(of: "[^A-Za-z]", with: " ", options: .regularExpression) .trimmingCharacters(in: .whitespacesAndNewlines).capitalized ?? ""

        if !possibleAppName.isEmpty {
            title = title.replacingOccurrences(of: #" ?[-—–] ?\b\#(possibleAppName)\b$"#, with: "", options: [.regularExpression, .caseInsensitive])
        }

        title = title.replacingOccurrences(of: #"([-—–]\s*)+\b[A-Z][a-zA-Z]+\b$"#, with: "", options: .regularExpression)

        if title.count > 120 {
            let trimmed = title.prefix(117)
            title = trimmed + "…"
        }

        title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty {
            title = possibleAppName.isEmpty ? "Unknown Window" : possibleAppName
        }

        return title
    }
}
