import Foundation
import ApplicationServices

@MainActor
class WebKitCollectorBase: PaneKitCollector, @unchecked Sendable {
    class var WebKitBundleID: String {
        fatalError("Subclasses must override WebKitBundleID")
    }
    
    open override func _collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        guard let pkApp = Application.app(forBundleIdentifier: bundleID) else {
            return []
        }
        let pid = pkApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        guard let axWindows = safeAXChildren(of: axApp), !axWindows.isEmpty else { return [] }
        
        var results: [PaneKitWindow] = []
        for win in axWindows {
            let pkWin = PKWindow(axuiElement: win)
            if let window = PaneKitWindow(pkWindow: pkWin) {
                results.append(window)
            }
        }
        return results
    }
        
    open override func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axWindow = window.pkWindow.axElement
        var tabs: [PaneKitWindow] = []
        let tabGroups = Self.deepFindTabGroups(in: axWindow)
        var tabElements: [AXUIElement] = []
        
        for group in tabGroups {
            if let children = safeAXChildren(of: group) {
                for child in children {
                    let role = safeAXRole(of: child)
                    if role == "AXRadioButton" || role == "AXButton" {
                        tabElements.append(child)
                    }
                }
            }
        }
        
        if tabElements.isEmpty {
            if let pid = pid_t(exactly: window.pid), let app = NSRunningApplication(processIdentifier: pid) {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                let menuTabs = Self.extractTabTitlesFromMenus(axApp)

                for title in menuTabs {let pkTab = PKWindow(axuiElement: axWindow, isTab: true, parentTabHost: window.stableID)
                    pkTab.title = title
                    pkTab.windowType = .tab

                    if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                        tabs.append(paneTab)
                    }
                }
            }
            return tabs
        }
        
        for (index, el) in tabElements.enumerated() {
            let title = Self.resolveTabTitle(for: el)

            let pkTab = PKWindow(axuiElement: el, isTab: true, parentTabHost: window.stableID)
            pkTab.title = title
            pkTab.windowType = .tab
            pkTab.tabIndex = index

            if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                tabs.append(paneTab)
            }
        }
        
        return tabs
    }
    
    internal class func deepFindTabGroups(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 10 else { return [] }
        var results: [AXUIElement] = []
        guard let children = safeAXChildren(of: element), !children.isEmpty else { return [] }
        
        for child in children {
            let role = safeAXRole(of: child)
            if role == "AXTabGroup" || role == "AXGroup" {
                results.append(child)
            }
            results.append(contentsOf: deepFindTabGroups(in: child, depth: depth + 1))
        }
        return results
    }
    
    internal class func extractTabTitlesFromMenus(_ appElement: AXUIElement) -> [String] {
        var titles: [String] = []
        var menuBarRef: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(appElement, AXAttr.menuBar, &menuBarRef) == .success,
           let menuBar = menuBarRef.map({ unsafeDowncast($0, to: AXUIElement.self) }),
           let items = safeAXChildren(of: menuBar) {
            
            for item in items {
                if let subMenu = safeAXValue(of: item, attribute: AXAttr.menu) {
                    let menuEl = unsafeDowncast(subMenu as CFTypeRef, to: AXUIElement.self)
                    titles.append(contentsOf: extractTitlesRecursively(from: menuEl))
                }
            }
        }
        
        return Array(Set(titles))
    }
    
    internal class func extractTitlesRecursively(from menu: AXUIElement) -> [String] {
        guard let items = safeAXChildren(of: menu) else { return [] }
        var titles: [String] = []
        
        for item in items {
            let title = safeAXTitle(of: item).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            
            let lower = title.lowercased()
            let skip = ["window", "pane", "panel", "workspace", "tool", "preferences", "settings", "hilfe", "menu", "tab group", "navigation"]
            if skip.contains(where: { lower.contains($0) }) { continue }
            if title.hasPrefix("•") || title.hasPrefix("-") || title.hasSuffix("…") { continue }
            
            titles.append(title)
            
            if let subMenu = safeAXValue(of: item, attribute: AXAttr.menu) {
                let menuEl = unsafeDowncast(subMenu as CFTypeRef, to: AXUIElement.self)
                titles.append(contentsOf: extractTitlesRecursively(from: menuEl))
            }
        }
        return titles
    }
    
    internal class func resolveTabTitle(for element: AXUIElement) -> String {
        var value: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(element, AXAttr.title, &value) == .success,
           let title = value as? String, !title.isEmpty {
            return title
        }
        if AXUIElementCopyAttributeValue(element, AXAttr.description, &value) == .success,
           let desc = value as? String, !desc.isEmpty {
            return desc
        }
        return "(untitled tab)"
    }
}
