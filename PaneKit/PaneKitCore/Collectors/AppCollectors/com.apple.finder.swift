import Foundation
import AppKit
import ApplicationServices

@MainActor
final class com_apple_finder_AppCollector: SystemCollectorBase, @unchecked Sendable {
    override class var SystemBundleID: String { "com.apple.finder" }

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
            guard !title.isEmpty, !title.lowercased().contains("dialog") else { continue }

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

        let tabContainers = Self.deepFindTabGroups(in: axElement)

        for container in tabContainers {
            if let children = safeAXChildren(of: container) {
                for child in children {
                    let role = safeAXRole(of: child)
                    if role == "AXRadioButton" || role == "AXButton" || role == "AXGroup" {
                        tabElements.append(child)
                    }
                }
            }
        }

        for (index, tab) in tabElements.enumerated() {
            let title = resolveFinderTabTitle(for: tab).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title != "+" else { continue }

            var roleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(tab, AXAttr.role, &roleValue)
            let role = (roleValue as? String) ?? ""

            if (role == "AXButton" && !AXUIElementHasAttribute(tab, AXAttr.value)) {
                continue
            }

            let pkTab = PKWindow(
                axuiElement: tab,
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
        
        if results.isEmpty, let menuBar = asAXElement(safeAXValue(of: axElement, attribute: AXAttr.menuBar)) {
            let fallbackTabs = await extractTabsFromFinderMenu(menuBar, parentWindow: window)
            results.append(contentsOf: fallbackTabs)
        }

        return results
    }
    
    private func extractTabsFromFinderMenu(_ menu: AXUIElement, parentWindow: PaneKitWindow) async -> [PaneKitWindow] {
        guard let items = safeAXChildren(of: menu), !items.isEmpty else { return [] }
        var tabs: [PaneKitWindow] = []

        for (index, item) in items.enumerated() {
            let role = safeAXRole(of: item)
            let ident = safeAXIdentifier(of: item)
            let title = safeAXTitle(of: item)

            if role == "AXMenuItem", ident.contains("newWindowForTab"), !title.isEmpty {
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
                let nested = await extractTabsFromFinderMenu(subMenu, parentWindow: parentWindow)
                tabs.append(contentsOf: nested)
            }
        }

        return tabs
    }

    private func resolveFinderTabTitle(for element: AXUIElement) -> String {
        let title = safeAXTitle(of: element)
        if !title.isEmpty { return title }

        if let desc = safeAXValue(of: element, attribute: AXAttr.description) as? String, !desc.isEmpty {
            return desc
        }

        if let children = safeAXChildren(of: element) {
            for child in children {
                if let value = safeAXValue(of: child, attribute: AXAttr.value) as? String, !value.isEmpty {
                    return value
                }

                let childTitle = safeAXTitle(of: child)
                if !childTitle.isEmpty { return childTitle }
            }
        }

        return "(Finder Tab)"
    }

    override class func deepFindTabGroups(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 10 else { return [] }
        var found: [AXUIElement] = []
        guard let children = safeAXChildren(of: element), !children.isEmpty else { return [] }

        for child in children {
            let role = safeAXRole(of: child)
            if role == "AXTabGroup" || role == "AXGroup" {
                let ident = safeAXIdentifier(of: child).lowercased()
                let desc = (safeAXValue(of: child, attribute: AXAttr.description) as? String)?.lowercased() ?? ""

                if ident.contains("tab") || desc.contains("tab") {
                    found.append(child)
                    continue
                }

                if let subChildren = safeAXChildren(of: child),
                   subChildren.contains(where: { safeAXRole(of: $0) == "AXRadioButton" }) {
                    found.append(child)
                    continue
                }
            }

            found.append(contentsOf: deepFindTabGroups(in: child, depth: depth + 1))
        }

        return found
    }
}
