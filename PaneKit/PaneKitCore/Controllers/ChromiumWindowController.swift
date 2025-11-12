import Foundation
import ApplicationServices

@MainActor
class ChromiumWindowController: DefaultController {
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
        
    func reloadCurrentTab() async {
        await performAXPressOnMenuItem(where: isReloadMenuItem)
    }
    
    private func isReloadMenuItem(_ element: AXUIElement) -> Bool {
        guard let cmdChar = safeAXAttribute(element, AXAttr.menuItemCmdChar) as? String, let modifiers = safeAXAttribute(element, AXAttr.menuItemCmdModifiers) as? Int else {
            return false
        }

        let isCommandPressed = (modifiers & 1048576) != 0
        return isCommandPressed && cmdChar.lowercased() == "r"
    }
        
    private func performAXPressOnMenuItem(where matcher: (AXUIElement) -> Bool) async {
        let systemWide = AXUIElementCreateSystemWide()
        var menuBarRef: CFTypeRef?

        if AXUIElementCopyAttributeValue(systemWide, AXAttr.menuBar, &menuBarRef) == .success, let menuBarRef = menuBarRef, CFGetTypeID(menuBarRef) == AXUIElementGetTypeID() {
            let menuBar = menuBarRef as! AXUIElement
            await recursivelyPressMenuItem(in: menuBar, where: matcher)
        }
    }

    private func recursivelyPressMenuItem(in element: AXUIElement, where matcher: (AXUIElement) -> Bool) async {
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.children, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                if matcher(child) {
                    _ = AXUIElementPerformAction(child, AXAction.press)
                    return
                }
                await recursivelyPressMenuItem(in: child, where: matcher)
            }
        }
    }
}
