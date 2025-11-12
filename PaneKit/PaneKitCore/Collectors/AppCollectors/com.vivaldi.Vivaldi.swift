import Foundation
import ApplicationServices

@MainActor
final class com_vivaldi_vivaldi_AppCollector: PaneKitCollector, @unchecked Sendable {
    static let bundleIdent = "com.vivaldi.Vivaldi"

    public override func _collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        guard let pkApp = Application.app(forBundleIdentifier: bundleID) else {
            return []
        }

        let pid = pkApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        guard let axWindows = safeAXChildren(of: axApp), !axWindows.isEmpty else { return [] }

        var results: [PaneKitWindow] = []

        for win in axWindows {
            let pkWin = PKWindow(axuiElement: win)
            if let paneWin = PaneKitWindow(pkWindow: pkWin) {
                results.append(paneWin)
            }
        }

        return results
    }
    
    public override func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        guard let app = NSRunningApplication(processIdentifier: pid_t(window.pid)) else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        let tabTitles = Self.extractTabsFromMenu(for: axApp)

        var tabElements: [AXUIElement] = []
        if !tabTitles.isEmpty {
            let axElement = window.pkWindow.axElement
            tabElements = Self.findTabButtons(in: axElement)
        }

        guard !tabElements.isEmpty else {
            return []
        }

        var results: [PaneKitWindow] = []
        for (index, element) in tabElements.enumerated() {
            let pkTab = PKWindow(
                axuiElement: element,
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

        return results
    }

    private class func findTabButtons(in element: AXUIElement, depth: Int = 0, insideTabContainer: Bool = false) -> [AXUIElement] {
        guard depth < 14 else { return [] }
        var results: [AXUIElement] = []

        var roleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, AXAttr.role, &roleValue)
        let role = roleValue as? String ?? ""

        var identifier: String = ""
        var idValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AX.identifier, &idValue) == .success, let id = idValue as? String {
            identifier = id.lowercased()
        }

        var isTabContainer = insideTabContainer
        if role == "AXGroup" && (identifier.contains("tab") || identifier.contains("strip") || identifier.contains("tabscontainer")) {
            isTabContainer = true
        }

        let blacklist = ["toolbar", "address", "buttonbar", "panel", "status", "sidebar", "bookmark"]
        if blacklist.contains(where: { identifier.contains($0) }) {
            return []
        }

        if isTabContainer && (role == "AXButton" || role == "AXRadioButton" || role == "AXGroup") {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, AXAttr.title, &titleValue) == .success, let title = titleValue as? String, !title.isEmpty { results.append(element)
            } else if AXUIElementCopyAttributeValue(element, AXAttr.description, &titleValue) == .success, let desc = titleValue as? String, !desc.isEmpty {
                results.append(element)
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.children, &childrenValue) == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                results.append(contentsOf: findTabButtons(in: child, depth: depth + 1, insideTabContainer: isTabContainer))
            }
        }

        return results
    }

    private class func extractTabsFromMenu(for appElement: AXUIElement) -> [String] {
        var titles: [String] = []

        var menuBarRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, AXAttr.menuBar, &menuBarRef) == .success, let menuBar = menuBarRef.map({ unsafeDowncast($0, to: AXUIElement.self) }), let menuItems = safeAXChildren(of: menuBar) {
            for item in menuItems {
                guard let subMenuValue = safeAXValue(of: item, attribute: AXAttr.menu) else { continue }
                let subMenu: AXUIElement = unsafeBitCast(subMenuValue, to: AXUIElement.self)
                let childTitles = safeAXChildren(of: subMenu)?.map { safeAXTitle(of: $0).lowercased() } ?? []

                let looksLikeWindowMenu = childTitles.contains {
                    $0.contains(".") || $0.contains("|") || $0.contains(" - ") || $0.contains("http")
                }

                if looksLikeWindowMenu {
                    titles.append(contentsOf: extractTabsFromWindowMenu(subMenu))
                }
            }
        }

        return Array(Set(titles))
    }

    private class func extractTabsFromWindowMenu(_ menu: AXUIElement) -> [String] {
        var result: [String] = []
        guard let items = safeAXChildren(of: menu) else { return [] }

        for item in items {
            let title = safeAXTitle(of: item).trimmingCharacters(in: .whitespacesAndNewlines)

            if let subMenuValue = safeAXValue(of: item, attribute: AXAttr.menu) {
                let subMenu: AXUIElement = unsafeBitCast(subMenuValue, to: AXUIElement.self)
                result.append(contentsOf: extractTabsFromWindowMenu(subMenu))
                continue
            }

            guard !title.isEmpty else { continue }
            let lower = title.lowercased()

            let skipKeywords = ["window", "pane", "panel", "workspace", "tool", "menu", "preferences", "settings"]
            if skipKeywords.contains(where: { lower.contains($0) }) { continue }
            if lower.hasSuffix("...") || lower.hasPrefix("•") || lower.hasPrefix("-") { continue }

            if title.count > 2 && !title.hasSuffix(":") {
                result.append(title)
            }
        }

        return result
    }
}
