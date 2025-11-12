import Foundation
import ApplicationServices

@MainActor
class JetBrainsCollectorBase: PaneKitCollector, @unchecked Sendable {
    class var jetBrainsBundleID: String {
        fatalError("Subclasses must override jetBrainsBundleID")
    }

    open override func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axWindow = window.pkWindow.axElement
        var tabs: [PaneKitWindow] = []
        var visited = Set<AXUIElement>()

        let foundTabs = Self.findJetBrainsTabs(in: axWindow, visited: &visited)

        for (index, el) in foundTabs.enumerated() {
            let title = Self.resolveJetBrainsTabTitle(for: el)
            guard !title.isEmpty else { continue }

            let pkTab = PKWindow(axuiElement: el, isTab: true, parentTabHost: window.stableID)
            guard let paneTab = PaneKitWindow(pkWindow: pkTab) else { continue }

            paneTab.windowType = .tab
            paneTab.tabIndex = index
            paneTab.title = title
            tabs.append(paneTab)
        }

        return tabs
    }
    
    private class func findJetBrainsTabs(in element: AXUIElement, visited: inout Set<AXUIElement>) -> [AXUIElement] {
        guard !visited.contains(element) else { return [] }
        visited.insert(element)

        var found: [AXUIElement] = []

        let role = safeAXRole(of: element)
        let desc = safeAXDescription(of: element)
        let title = safeAXTitle(of: element)

        let ignoreRoles: Set<String> = ["AXScrollBar", "AXTextArea", "AXRuler", "AXStaticText"]
        if ignoreRoles.contains(role) { return [] }

        if desc.localizedCaseInsensitiveContains("editor") || desc.localizedCaseInsensitiveContains("code") {
            return []
        }

        if role == "AXRadioButton", (!title.isEmpty || !desc.isEmpty) {
            found.append(element)
        }
        
        let attributeKeys: [CFString] = [AXAttr.children.raw, AX.childrenInNavigationOrder.raw, AXAttr.visibleChildren.raw, AXAttr.parent.raw, AXAttr.focusedUIElement.raw, AXAttr.window.raw]

        for key in attributeKeys {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, key, &value) == .success, let arr = value as? [Any] {
                for item in arr {
                    if CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                        let child = item as! AXUIElement
                        found.append(contentsOf: findJetBrainsTabs(in: child, visited: &visited))
                    }
                }
            }
        }

        return found
    }

    private class func resolveJetBrainsTabTitle(for tab: AXUIElement) -> String {
        let title = safeAXTitle(of: tab)
        if !title.isEmpty { return title }

        let value = safeAXValue(of: tab)
        if !value.isEmpty { return value }

        if let children = safeAXChildren(of: tab) {
            for child in children {
                let role = safeAXRole(of: child)
                if role == "AXStaticText" || role == "AXTextField" {
                    let txt = safeAXValue(of: child)
                    if !txt.isEmpty { return txt }
                }
            }
        }

        let desc = safeAXDescription(of: tab)
        if !desc.isEmpty { return desc }

        return "(untitled)"
    }

    private class func isGenericTabLabel(_ element: AXUIElement) -> Bool {
        let role = safeAXRole(of: element)
        let subrole = safeAXSubrole(element)
        let desc = safeAXDescription(of: element)
        let title = safeAXTitle(of: element)
        let value = safeAXValue(of: element)
        
        if role == "AXRadioButton" || subrole == "AXTabButton" {
            return true
        }

        if desc.lowercased().contains("tab") || subrole.lowercased().contains("tab") {
            return true
        }
        
        let shortTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if shortTitle.count <= 1 || shortValue.count <= 1 {
            return true
        }

        if title.isEmpty && value.isEmpty && desc.isEmpty {
            return true
        }

        return false
    }
}
