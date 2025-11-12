import Foundation
import ApplicationServices

@MainActor
final class org_mozilla_firefox_AppCollector: ChromiumCollectorBase, @unchecked Sendable {
    override class var chromiumBundleID: String { "org.mozilla.firefox" }

    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axElement = window.pkWindow.axElement
        var visited = Set<AXUIElement>()
        let tabElements = Self.findFirefoxTabs(in: axElement, visited: &visited)
        let orderedTabs = Self.orderTabsInVisualOrder(tabElements, under: axElement)

        var tabs: [PaneKitWindow] = []
        for (index, el) in orderedTabs.enumerated() {
            let tabTitle = Self.resolveTabTitle(for: el)
            guard !tabTitle.isEmpty else { continue }

            let pkTab = PKWindow(
                axuiElement: el,
                isTab: true,
                parentTabHost: window.stableID,
                pid: window.pid,
                bundleID: window.bundleID
            )

            if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                paneTab.tabIndex = index
                tabs.append(paneTab)
            }
        }

        return tabs
    }

    private class func findFirefoxTabs(in element: AXUIElement, visited: inout Set<AXUIElement>, depth: Int = 0) -> [AXUIElement] {
        guard depth < 15 else { return [] }
        if visited.contains(element) { return [] }
        visited.insert(element)

        var found: [AXUIElement] = []
        let role = safeAXRole(of: element)

        if role == "AXRadioButton" {
            if hasTabLikeContent(in: element) {
                found.append(element)
            }
        }

        if ["AXWindow", "AXGroup", "AXToolbar", "AXTabGroup"].contains(role) {
            for key in [AXAttr.children.raw, AX.childrenInNavigationOrder.raw, AXAttr.visibleChildren.raw] {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, key, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
                    for child in children {
                        found.append(contentsOf: findFirefoxTabs(in: child, visited: &visited, depth: depth + 1))
                    }
                }
            }
        }

        return found
    }
    
    private class func hasTabLikeContent(in element: AXUIElement) -> Bool {
        guard let children = safeAXChildren(of: element) else { return false }

        for child in children {
            let role = safeAXRole(of: child)
            if role == "AXStaticText" {
                let val = safeAXValue(of: child)
                if val.isEmpty { continue }

                if val.count > 2 && !isGenericTabLabel(val, in: element) {
                    return true
                }
            }
        }
        return false
    }

    private class func isGenericTabLabel(_ text: String, in element: AXUIElement) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        if trimmed.count < 3 { return true }

        if let url = safeAXAttribute(element, AX.url) as? String, !url.isEmpty {
            return false
        }

        if let titleElRef = safeAXAttribute(element, AX.titleUIElement), CFGetTypeID(titleElRef as CFTypeRef) == AXUIElementGetTypeID() {
            let titleEl = unsafeBitCast(titleElRef, to: AXUIElement.self)
            let innerValue = safeAXValue(of: titleEl)
            if !innerValue.isEmpty {
                return false
            }
        }

        if trimmed.range(of: #"^[\p{P}\p{S}\p{Z}]+$"#, options: .regularExpression) != nil {
            return true
        }

        if trimmed.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) == nil {
            return true
        }

        return false
    }

    override class func resolveTabTitle(for tabElement: AXUIElement) -> String {
        let title = safeAXTitle(of: tabElement)
        if !title.isEmpty {
            return title
        }

        let val = safeAXValue(of: tabElement)
        if !val.isEmpty && !isGenericTabLabel(val, in: tabElement) {
            return val
        }

        if let children = safeAXChildren(of: tabElement) {
            for child in children {
                let role = safeAXRole(of: child)
                if role == "AXStaticText" {
                    let text = safeAXValue(of: child)
                    if !text.isEmpty && !isGenericTabLabel(text, in: tabElement) {
                        return text
                    }
                }
            }
        }

        return ""
    }
}
