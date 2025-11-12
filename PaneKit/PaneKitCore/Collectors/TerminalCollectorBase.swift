import Foundation
import ApplicationServices

@MainActor
class TerminalCollectorBase: PaneKitCollector, @unchecked Sendable {
    class var terminalBundleID: String {
        fatalError("Subclasses must override terminalBundleID")
    }

    open override func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axWindow = window.pkWindow.axElement
        var visited = Set<AXUIElement>()

        let tabElements = Self.findTerminalTabs(in: axWindow, visited: &visited)
        guard !tabElements.isEmpty else { return [] }

        var tabs: [PaneKitWindow] = []
        for (index, el) in tabElements.enumerated() {
            let tabTitle = Self.resolveTerminalTabTitle(for: el)
            
            let pkTab = PKWindow(axuiElement: el, isTab: true, parentTabHost: window.stableID)
            guard let paneTab = PaneKitWindow(pkWindow: pkTab) else { continue }
            
            paneTab.windowType = .tab
            paneTab.tabIndex = index
            paneTab.title = tabTitle
            tabs.append(paneTab)
        }

        return tabs
    }

    class func findTerminalTabs(in element: AXUIElement, depth: Int = 0, visited: inout Set<AXUIElement>) -> [AXUIElement] {
        guard depth < 15 else { return [] }
        if visited.contains(element) { return [] }
        visited.insert(element)

        var found: [AXUIElement] = []
        guard let children = safeAXChildren(of: element) else { return [] }

        for child in children {
            let role = safeAXRole(of: child)
            let subrole = safeAXSubrole(child)

            if role == "AXRadioButton" || (role == "AXButton" && subrole == "AXTabButton") {
                found.append(child)
                continue
            }

            if role == "AXGroup" || role == "AXTabGroup" {
                found.append(contentsOf: findTerminalTabs(in: child, depth: depth + 1, visited: &visited))
                continue
            }

            found.append(contentsOf: findTerminalTabs(in: child, depth: depth + 1, visited: &visited))
        }

        return found
    }

    class func resolveTerminalTabTitle(for tabElement: AXUIElement) -> String {
        var value: CFTypeRef?

        if AXUIElementCopyAttributeValue(tabElement, AXAttr.title, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }

        if AXUIElementCopyAttributeValue(tabElement, AXAttr.description, &value) == .success, let desc = value as? String, !desc.isEmpty {
            return desc
        }

        if let children = safeAXChildren(of: tabElement) {
            for child in children {
                if safeAXRole(of: child) == "AXStaticText" {
                    let t = safeAXTitle(of: child)
                    if !t.isEmpty { return t }
                }
            }
        }

        return "(unnamed session)"
    }
}
