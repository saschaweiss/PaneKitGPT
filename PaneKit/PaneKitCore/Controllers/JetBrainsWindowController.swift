import Foundation
import ApplicationServices

@MainActor
class JetBrainsWindowController: DefaultController {
    required init(window: PaneKitWindow) {
        super.init(window: window)
    }
    
    override func selectTab(at index: Int) async -> Bool {
        guard let tabs = window.tabs, index >= 0, index < tabs.count else {
            return false
        }

        let tab = tabs[index]

        let pkWindow = tab.pkWindow
        return await selectTab(pkWindow.axElement)
    }
        
    func focusEditor() async {
        let pkWindow = window.pkWindow
        let axWindow = pkWindow.axElement

        if let editor = await findElement(role: "AXTextArea", in: axWindow) {
            AXUIElementPerformAction(editor, AXAction.press.raw)
        }
    }
        
    private func findElement(role: String, in element: AXUIElement, depth: Int = 0) async -> AXUIElement? {
        guard depth < 8 else { return nil }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.children, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                if safeAXRole(of: child) == role { return child }
                if let found = await findElement(role: role, in: child, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }
}
