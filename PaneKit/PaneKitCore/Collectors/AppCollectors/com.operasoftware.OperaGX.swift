import Foundation
import ApplicationServices

@MainActor
final class com_operasoftware_operagx_AppCollector: ChromiumCollectorBase, @unchecked Sendable {
    static let bundleIdent = "com.operasoftware.OperaGX"
    
    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axWindow = window.pkWindow.axElement
        var tabs: [PaneKitWindow] = []
        
        func findTabs(in element: AXUIElement, depth: Int = 0, insideTabGroup: Bool = false) -> [AXUIElement] {
            var found: [AXUIElement] = []
            var value: CFTypeRef?

            var isInsideTabGroup = insideTabGroup
            if AXUIElementCopyAttributeValue(element, AXAttr.role, &value) == .success, let role = value as? String, role == "AXTabGroup" {
                isInsideTabGroup = true
            }

            if AXUIElementCopyAttributeValue(element, AXAttr.children, &value) == .success, let children = value as? [AXUIElement] {
                for child in children {
                    var roleValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, AXAttr.role, &roleValue) == .success, let role = roleValue as? String {
                        if isInsideTabGroup && role == "AXRadioButton" {
                            found.append(child)
                        } else {
                            found.append(contentsOf: findTabs(in: child, depth: depth + 1, insideTabGroup: isInsideTabGroup))
                        }
                    }
                }
            }

            return found
        }
        
        func operagxTabTitle(for tabElement: AXUIElement) -> String {
            var value: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(tabElement, AXAttr.value, &value) == .success, let title = value as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            
            if AXUIElementCopyAttributeValue(tabElement, AXAttr.description, &value) == .success, let desc = value as? String, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return desc
            }
            
            if AXUIElementCopyAttributeValue(tabElement, AX.titleUIElement, &value) == .success, let titleEl = value, CFGetTypeID(titleEl) == AXUIElementGetTypeID() {
                let axTitleEl = unsafeDowncast(titleEl, to: AXUIElement.self)
                var innerValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(axTitleEl, AXAttr.value, &innerValue) == .success, let innerTitle = innerValue as? String, !innerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return innerTitle
                }
            }

            return "(untitled)"
        }

        let tabElements = findTabs(in: axWindow)

        for (index, el) in tabElements.enumerated() {
            let title = operagxTabTitle(for: el)
            
            let pkTab = PKWindow(
                axuiElement: el,
                isTab: true,
                parentTabHost: window.stableID,
                pid: window.pid,
                bundleID: window.bundleID
            )

            let paneTab = PaneKitWindow(pkWindow: pkTab)
            paneTab?.title = title
            paneTab?.tabIndex = index
            if let tab = paneTab { tabs.append(tab) }
        }

        return tabs
    }
}
