import Foundation
import ApplicationServices

@MainActor
final class com_apple_safari_AppCollector: WebKitCollectorBase, @unchecked Sendable {
    override class var WebKitBundleID: String { "com.apple.Safari" }
    
    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axElement = window.pkWindow.axElement
        var tabs: [PaneKitWindow] = []
        var foundTabButtons: [AXUIElement] = []

        func findSafariTabs(in element: AXUIElement, depth: Int = 0) {
            guard depth < 10 else { return }
            let role = safeAXRole(of: element)

            if role == "AXRadioButton" {
                var idValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, AX.identifier, &idValue) == .success, let identifier = idValue as? String, identifier.lowercased().contains("tabbartab") {
                    foundTabButtons.append(element)
                    return
                }
            }

            if role == "AXWindow" || role == "AXGroup" || role == "AXTabGroup" || role == "AXRadioButton" {
                if let children = safeAXChildren(of: element) {
                    for child in children {
                        findSafariTabs(in: child, depth: depth + 1)
                    }
                }
            }
        }
        
        findSafariTabs(in: axElement)

        for (index, tabEl) in foundTabButtons.enumerated() {
            let title = Self.resolveTabTitle(for: tabEl)
            guard !title.isEmpty else { continue }

            let pkTab = PKWindow(
                axuiElement: tabEl,
                isTab: true,
                parentTabHost: window.stableID,
                pid: window.pid,
                bundleID: window.bundleID
            )

            if let tab = PaneKitWindow(pkWindow: pkTab) {
                tab.tabIndex = index
                tabs.append(tab)
            }
        }

        if tabs.isEmpty,
           let pid = pid_t(exactly: window.pid),
           let app = NSRunningApplication(processIdentifier: pid) {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let menuTitles = Self.extractTabTitlesFromMenus(axApp)

            for (index, _) in menuTitles.enumerated() {
                let pkTab = PKWindow(
                    axuiElement: axElement,
                    isTab: true,
                    parentTabHost: window.stableID,
                    pid: window.pid,
                    bundleID: window.bundleID
                )

                if let tab = PaneKitWindow(pkWindow: pkTab) {
                    tab.tabIndex = index
                    tabs.append(tab)
                }
            }
        }

        return tabs
    }
        
    override class func resolveTabTitle(for element: AXUIElement) -> String {
        var value: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(element, AXAttr.title, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }
        if AXUIElementCopyAttributeValue(element, AXAttr.value, &value) == .success, let valueStr = value as? String, !valueStr.isEmpty {
            return valueStr
        }
        if AXUIElementCopyAttributeValue(element, AXAttr.help, &value) == .success, let helpStr = value as? String, !helpStr.isEmpty {
            return helpStr
        }
        
        return "(Safari Tab)"
    }
}
