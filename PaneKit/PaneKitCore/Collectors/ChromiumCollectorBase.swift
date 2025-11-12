import Foundation
import ApplicationServices

@MainActor
class ChromiumCollectorBase: PaneKitCollector, @unchecked Sendable {
    class var chromiumBundleID: String {
        fatalError("Subclasses must override chromiumBundleID")
    }

    open override func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let lowerTitle = window.title.lowercased()
        if lowerTitle.contains("devtools") || lowerTitle.contains("inspector") || lowerTitle.contains("debugger") {
            if PaneKitConfiguration.shared.enableLogging {
                print("⚠️ Skip tab collection for DevTool window: \(window.title)")
            }
            return []
        }
        
        let axWindow = window.pkWindow.axElement
        var tabs: [PaneKitWindow] = []

        let tabElements = Self.findTabs(in: axWindow)
        for (index, el) in tabElements.enumerated() {
            let tabTitle = Self.resolveTabTitle(for: el)
            
            let pkTab = PKWindow(
                axuiElement: el,
                isTab: true,
                parentTabHost: window.stableID,
                pid: window.pid,
                bundleID: window.bundleID
            )

            guard let paneTab = PaneKitWindow(pkWindow: pkTab) else { continue }

            paneTab.windowType = .tab
            paneTab.tabIndex = index
            paneTab.title = tabTitle
            tabs.append(paneTab)
        }

        return tabs
    }
    
    class func isLikelyDevToolsWindow(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?

        let hasTabGroup = hasChild(ofRole: "AXTabGroup", in: element)
        if hasTabGroup {
            return false
        }

        let hasWebArea = hasChild(ofRole: "AXWebArea", in: element)
        if !hasWebArea {
            return false
        }

        if AXUIElementCopyAttributeValue(element, AXAttr.title, &value) == .success, let title = value as? String, title.count < 5 {
            return true
        }

        return true
    }

    private class func hasChild(ofRole role: String, in element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.children, &value) == .success, let children = value as? [AXUIElement] {
            for child in children {
                var childRole: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, AXAttr.role, &childRole) == .success, let roleStr = childRole as? String, roleStr == role {
                    return true
                }
                if hasChild(ofRole: role, in: child) {
                    return true
                }
            }
        }
        return false
    }

    class func findTabs(in element: AXUIElement, depth: Int = 0, insideTabGroup: Bool = false) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var value: CFTypeRef?
        var isInside = insideTabGroup

        if AXUIElementCopyAttributeValue(element, AXAttr.role, &value) == .success, let role = value as? String {
            if role == "AXTabGroup" {
                isInside = true
            }

            if isInside {
                var subroleVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, AXAttr.subrole, &subroleVal) == .success, let subrole = subroleVal as? String, role == "AXRadioButton", subrole == "AXTabButton" {
                    found.append(element)
                }
            }
            else if role == "AXRadioButton" {
                var subroleVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, AXAttr.subrole, &subroleVal) == .success, let subrole = subroleVal as? String, subrole == "AXTabButton" {
                    found.append(element)
                }
            }
        }

        if AXUIElementCopyAttributeValue(element, AXAttr.children, &value) == .success, let children = value as? [AXUIElement] {
            for child in children {
                var roleVal: CFTypeRef?
                var subroleVal: CFTypeRef?
                var descVal: CFTypeRef?
                var nextInside = isInside

                if AXUIElementCopyAttributeValue(child, AXAttr.role, &roleVal) == .success, let role = roleVal as? String {
                    if role == "AXTabGroup" {
                        nextInside = true
                    }

                    _ = AXUIElementCopyAttributeValue(child, AXAttr.subrole, &subroleVal)
                    let subrole = (subroleVal as? String) ?? "-"
                    _ = AXUIElementCopyAttributeValue(child, AXAttr.description, &descVal)

                    if nextInside, (role == "AXRadioButton" || role == "AXTab"), subrole == "AXTabButton" {
                        found.append(child)
                    }
                }

                let nested = findTabs(in: child, depth: depth + 1, insideTabGroup: nextInside)
                if !nested.isEmpty {
                    found.append(contentsOf: nested)
                }
            }
        }
        
        var unique: [AXUIElement] = []
        var seen = Set<CFHashCode>()
        for el in found {
            let hash = CFHash(el)
            if !seen.contains(hash) {
                seen.insert(hash)
                unique.append(el)
            }
        }
        return unique
    }

    class func resolveTabTitle(for tabElement: AXUIElement) -> String {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(tabElement, AXAttr.value, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }
        if AXUIElementCopyAttributeValue(tabElement, AXAttr.description, &value) == .success, let desc = value as? String, !desc.isEmpty {
            return desc
        }
        if AXUIElementCopyAttributeValue(tabElement, "AXTitleUIElement" as CFString, &value) == .success, let titleEl = value, CFGetTypeID(titleEl) == AXUIElementGetTypeID() {
            let axTitleEl = unsafeDowncast(titleEl, to: AXUIElement.self)
            var innerValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(axTitleEl, AXAttr.value, &innerValue) == .success, let innerTitle = innerValue as? String, !innerTitle.isEmpty {
                return innerTitle
            }
        }
        return "(untitled)"
    }
    
    class func orderTabsInVisualOrder(_ tabs: [AXUIElement], under parent: AXUIElement) -> [AXUIElement] {
        let positioned = tabs.compactMap { el -> (AXUIElement, CGRect)? in
            let frame = safeAXFrame(el)
            guard !frame.isNull else { return nil }
            return (el, frame)
        }

        let sorted = positioned.sorted { lhs, rhs in
            if abs(lhs.1.origin.y - rhs.1.origin.y) < 5 {
                return lhs.1.origin.x < rhs.1.origin.x
            }
            return lhs.1.origin.y < rhs.1.origin.y
        }

        return sorted.map { $0.0 }
    }
}
