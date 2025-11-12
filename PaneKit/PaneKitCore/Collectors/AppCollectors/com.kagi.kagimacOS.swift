import Foundation
import ApplicationServices

@MainActor
final class com_kagi_kagimacOS_AppCollector: WebKitCollectorBase, @unchecked Sendable {
    override class var WebKitBundleID: String { "com.kagi.kagimacOS" }

    override public func _collectTabs(for window: PaneKitWindow) async -> [PaneKitWindow] {
        let axElement = window.pkWindow.axElement

        var tabs = await super._collectTabs(for: window)
        if !tabs.isEmpty { return tabs }

        let tabGroups = Self.deepFindTabGroups(in: axElement)
        var foundElements: [AXUIElement] = []

        for group in tabGroups {
            if let children = safeAXChildren(of: group) {
                for child in children {
                    let role = safeAXRole(of: child)
                    if role == "AXButton" || role == "AXRadioButton" {
                        foundElements.append(child)
                    }
                }
            }
        }

        if foundElements.isEmpty {
            if let pid = pid_t(exactly: window.pid), let app = NSRunningApplication(processIdentifier: pid) {
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

                    if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                        paneTab.tabIndex = index
                        tabs.append(paneTab)
                    }
                }
            }
        } else {
            for (index, el) in foundElements.enumerated() {
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
        }

        return tabs
    }

    override class func resolveTabTitle(for element: AXUIElement) -> String {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, AXAttr.title, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }
        if AXUIElementCopyAttributeValue(element, AXAttr.description, &value) == .success, let desc = value as? String, !desc.isEmpty {
            return desc
        }
        return "(Orion Tab)"
    }
}
