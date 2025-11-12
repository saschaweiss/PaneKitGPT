import Foundation
import ApplicationServices

@MainActor
final class com_operasoftware_opera_AppCollector: ChromiumCollectorBase, @unchecked Sendable {
    override class var chromiumBundleID: String { "com.operasoftware.Opera" }

    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axElement = window.pkWindow.axElement
        var visited = Set<AXUIElement>()
        let tabElements = Self.findOperaTabs(in: axElement, depth: 0, visited: &visited)
        let uniqueTabs = Array(Set(tabElements))
        let orderedTabs = Self.orderTabsInVisualOrder(uniqueTabs, under: axElement)

        var tabs: [PaneKitWindow] = []
        for (index, el) in orderedTabs.enumerated() {
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

    private class func findOperaTabs(in element: AXUIElement, depth: Int = 0, visited: inout Set<AXUIElement>) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        if visited.contains(element) { return [] }
        visited.insert(element)
        var found: [AXUIElement] = []

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.role, &roleValue) != .success {
            return found
        }
        let role = roleValue as? String ?? ""
        let subrole = safeAXSubrole(element)

        if role == AXRole.radioButton.string && subrole == AX.tabButtonRole.string {
            found.append(element)
            return found
        }

        if !["AXTabGroup", "AXTabStrip", "AXToolbar", "AXGroup", "AXWindow"].contains(role) {
            return found
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.children, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                found.append(contentsOf: findOperaTabs(in: child, depth: depth + 1, visited: &visited))
            }
        }

        if depth < 3 {
            var navChildrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, AX.childrenInNavigationOrder, &navChildrenRef) == .success, let navChildren = navChildrenRef as? [AXUIElement] {
                for child in navChildren {
                    found.append(contentsOf: findOperaTabs(in: child, depth: depth + 1, visited: &visited))
                }
            }
        }

        return found
    }
    
    override class func orderTabsInVisualOrder(_ tabs: [AXUIElement], under window: AXUIElement) -> [AXUIElement] {
        var stripRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, AXAttr.children, &stripRef) == .success, let children = stripRef as? [AXUIElement] {

            for child in children {
                let role = safeAXRole(of: child)
                if role == "AXTabGroup" || role == "AXTabStrip" {
                    var navRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, AX.childrenInNavigationOrder, &navRef) == .success, let navChildren = navRef as? [AXUIElement] {
                        let filtered = navChildren.filter { tabs.contains($0) }
                        if !filtered.isEmpty { return filtered }
                    }

                    var subRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, AXAttr.children, &subRef) == .success, let subChildren = subRef as? [AXUIElement] {
                        let filtered = subChildren.filter { tabs.contains($0) }
                        if !filtered.isEmpty { return filtered }
                    }
                }
            }
        }
        
        let orderedByPosition = tabs.sorted {
            let f1 = safeAXFrame($0)
            let f2 = safeAXFrame($1)
            if f1.origin.y == f2.origin.y {
                return f1.origin.x < f2.origin.x
            } else {
                return f1.origin.y < f2.origin.y
            }
        }

        return orderedByPosition
    }

    override class func resolveTabTitle(for tabElement: AXUIElement) -> String {
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(tabElement, AXAttr.value, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }

        if AXUIElementCopyAttributeValue(tabElement, AXAttr.description, &value) == .success, let desc = value as? String, !desc.isEmpty {
            return desc
        }

        if AXUIElementCopyAttributeValue(tabElement, AX.titleUIElement, &value) == .success, let titleEl = value, CFGetTypeID(titleEl) == AXUIElementGetTypeID() {
            let titleAX = unsafeDowncast(titleEl, to: AXUIElement.self)
            var inner: CFTypeRef?
            if AXUIElementCopyAttributeValue(titleAX, AXAttr.value, &inner) == .success, let innerTitle = inner as? String, !innerTitle.isEmpty {
                return innerTitle
            }
        }

        if let children = safeAXChildren(of: tabElement) {
            for child in children {
                let role = safeAXRole(of: child)
                if ["AXStaticText", "AXTextField"].contains(role) {
                    let title = safeAXTitle(of: child)
                    if !title.isEmpty { return title }
                }
            }
        }

        return "(Opera Tab)"
    }
}
