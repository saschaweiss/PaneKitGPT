import Foundation
import AppKit
import ApplicationServices

@MainActor
final class com_apple_dt_xcode_AppCollector: SystemCollectorBase, @unchecked Sendable {
    override class var SystemBundleID: String { "com.apple.dt.Xcode" }

    override public func _collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        guard let pkApp = Application.app(forBundleIdentifier: bundleID) else {
            return []
        }
        
        let pid = pkApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindows = safeAXChildren(of: axApp), !axWindows.isEmpty else { return [] }

        var results: [PaneKitWindow] = []

        for win in axWindows {
            let title = safeAXTitle(of: win)
            guard !title.isEmpty, !title.lowercased().contains("alert") else { continue }

            let pkWin = PKWindow(axuiElement: win)
            if let paneWin = PaneKitWindow(pkWindow: pkWin) {
                results.append(paneWin)
            }
        }

        return results
    }

    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axElement = window.pkWindow.axElement
        var tabElements: [AXUIElement] = []
        var results: [PaneKitWindow] = []

        func scan(_ element: AXUIElement, depth: Int = 0) {
            guard depth < 25 else { return }

            let role = safeAXRole(of: element)
            let subrole = safeAXSubrole(element)

            if role == "AXRadioButton" || (role == "AXButton" && subrole == "AXTabButton") {
                tabElements.append(element)
                return
            }

            if let children = safeAXChildren(of: element) {
                for child in children { scan(child, depth: depth + 1) }
            }
        }

        scan(axElement)

        tabElements = tabElements.filter {
            let frame = safeAXFrame($0)
            let title = safeAXTitle(of: $0)
            return frame.width > 10 && frame.height > 10 && !title.isEmpty
        }

        tabElements.sort { safeAXFrame($0).origin.x < safeAXFrame($1).origin.x }

        for (index, tabElement) in tabElements.enumerated() {
            let title = resolveXcodeTabTitle(for: tabElement)
            guard !title.isEmpty else { continue }

            let pkTab = PKWindow(
                axuiElement: tabElement,
                isTab: true,
                parentTabHost: window.stableID,
                pid: window.pid,
                bundleID: window.bundleID
            )

            if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                paneTab.tabIndex = index
                results.append(paneTab)
            }
        }

        if let menuBar = asAXElement(safeAXValue(of: axElement, attribute: AXAttr.menuBar)) {
            let fallbackTabs = await extractTabsFromRecentMenu(menuBar, parentWindow: window)
            results.append(contentsOf: fallbackTabs)
        }

        return results
    }

    private func extractTabsFromRecentMenu(_ menu: AXUIElement, parentWindow: PaneKitWindow) async -> [PaneKitWindow] {
        guard let items = safeAXChildren(of: menu), !items.isEmpty else { return [] }
        var tabs: [PaneKitWindow] = []

        for (index, item) in items.enumerated() {
            let role = safeAXRole(of: item)
            let ident = safeAXIdentifier(of: item)
            let title = safeAXTitle(of: item)

            if role == "AXMenuItem", ident == "_recentItemRequested:", !title.isEmpty {
                let pkTab = PKWindow(
                    axuiElement: item,
                    isTab: true,
                    parentTabHost: parentWindow.stableID,
                    pid: parentWindow.pid,
                    bundleID: parentWindow.bundleID
                )

                if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                    paneTab.tabIndex = index
                    tabs.append(paneTab)
                }
            }

            if let subMenu = asAXElement(safeAXValue(of: item, attribute: AXAttr.menu)) {
                let nested = await extractTabsFromRecentMenu(subMenu, parentWindow: parentWindow)
                tabs.append(contentsOf: nested)
            }
        }

        return tabs
    }

    private func resolveXcodeTabTitle(for element: AXUIElement) -> String {
        let title = safeAXTitle(of: element)
        if !title.isEmpty { return title }

        if let children = safeAXChildren(of: element) {
            for child in children {
                if let value = safeAXValue(of: child, attribute: AXAttr.value) as? String, value.hasSuffix(".swift") || value.hasSuffix(".m") || value.hasSuffix(".h") || value.hasSuffix(".cpp") {
                    return value
                }

                let childTitle = safeAXTitle(of: child)
                if !childTitle.isEmpty { return childTitle }
            }
        }

        if let desc = safeAXValue(of: element, attribute: AXAttr.description) as? String, !desc.isEmpty {
            return desc
        }

        return "(Xcode Tab)"
    }
}
