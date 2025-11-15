import Foundation
import AppKit

@MainActor
open class PaneKitCollector: @unchecked Sendable {
    public static let shared = PaneKitCollector()
    public required init() {}

    @discardableResult
    public static func collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        let collector = collector(for: bundleID)
        return await collector._collectWindows(for: bundleID)
    }

    @discardableResult
    public static func collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let bundle = await MainActor.run { window.bundleID }
        let collector = collector(for: bundle)
        return await collector._collectTabs(for: window)
    }

    open func _collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        guard let pkApp = Application.app(forBundleIdentifier: bundleID) else {
            return []
        }

        let pkWindows = PKWindow.filteredRealWindows(for: pkApp)
        if pkWindows.isEmpty {
            return []
        }
        
        var collected: [PaneKitWindow] = []

        for pk in pkWindows {
            guard let win = PaneKitWindow(pkWindow: pk) else {
                continue
            }

            await ensureStableID(for: win)

            win.screen = NSScreen.screens.first(where: { $0.frame.intersects(win.frame) })

            collected.append(win)
        }

        return collected
    }

    open func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, AXAttr.tabs.raw, &value) == .success else {
            return []
        }
        
        print("_collectTabs")
        let tabElements = safeAXArray(AXAttr.tabs.rawValue, from: window.element)
        if tabElements.isEmpty {
            return []
        }

        var tabs: [PaneKitWindow] = []

        for element in tabElements {
            let pkTab = PKWindow(
                axuiElement: element,
                isTab: true,
                parentTabHost: window.stableID
            )

            guard let tab = PaneKitWindow(pkWindow: pkTab) else { continue }

            tab.windowType = .tab
            await self.ensureStableID(for: tab)

            tab.screen = NSScreen.screens.first(where: { $0.frame.intersects(tab.frame) })
            await PaneKitCache.shared.store(tab)

            tabs.append(tab)
        }

        let uniqueTabs = Dictionary(grouping: tabs, by: \.stableID).compactMap { $0.value.first }
        return uniqueTabs
    }

    public static func collector(for bundleID: String) -> PaneKitCollector {
        let normalized = bundleID.replacingOccurrences(of: ".", with: "_").lowercased()
        let collectorName = "\(normalized)_AppCollector"

        if let type = NSClassFromString(collectorName) as? PaneKitCollector.Type {
            return type.init()
        }
        
        if let type = NSClassFromString("PaneKitCore.\(collectorName)") as? PaneKitCollector.Type {
            return type.init()
        }

        let webKitBundles = ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.mail", "com.apple.WebKit", "com.apple.dt.Xcode"]
        if webKitBundles.contains(bundleID.lowercased()) || bundleID.lowercased().contains("webkit") {
            if let webkit = NSClassFromString("WebKitCollector") as? PaneKitCollector.Type {
                return webkit.init()
            }
        }

        if bundleID.contains("chrome") || bundleID.contains("brave") || bundleID.contains("opera") || bundleID.contains("edge") {
            if let chromium = NSClassFromString("ChromiumCollector") as? PaneKitCollector.Type {
                return chromium.init()
            }
        }

        let systemBundles = ["com.apple.finder", "com.apple.SystemSettings", "com.apple.preference", "com.apple.systempreferences", "com.apple.activitymonitor", "com.apple.Console"]
        if systemBundles.contains(where: { bundleID.starts(with: $0) }) {
            if let sys = NSClassFromString("SystemCollector") as? PaneKitCollector.Type {
                return sys.init()
            }
        }

        return PaneKitCollector.shared
    }

    open func ensureStableID(for window: PaneKitWindow) async {
        guard window.stableID.isEmpty || window.stableID.contains("invalid") else {
            return
        }

        let newID: String
        if window.windowType == .tab {
            newID = window.pkWindow.computeStableIdentifierForTab() ?? "tab-\(UUID().uuidString)"
        } else {
            newID = window.pkWindow.computeStableIdentifierForWindow() ?? "win-\(UUID().uuidString)"
        }

        window.updateStableID(newID)
    }
}

extension Application {
    static func app(forBundleIdentifier bundleID: String) -> Application? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).compactMap { Application(running: $0) }.first
    }
}
