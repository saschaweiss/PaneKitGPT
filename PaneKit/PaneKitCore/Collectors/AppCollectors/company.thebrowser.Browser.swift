import Foundation
import ApplicationServices

@MainActor
final class company_thebrowser_browser_AppCollector: WebKitCollectorBase, @unchecked Sendable {
    override class var WebKitBundleID: String { "company.thebrowser.Browser" }

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
                        let title = Self.resolveTabTitle(for: child)
                        if !title.isEmpty && !title.lowercased().contains("space") {
                            foundElements.append(child)
                        }
                    }
                }
            }
        }

        if foundElements.isEmpty {
            if window.pid > 0, let app = NSRunningApplication(processIdentifier: window.pid) {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                
                let menuTitles = await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        let titles = Self.extractTabTitlesFromMenus(axApp)
                        continuation.resume(returning: titles)
                    }
                }

                for (index, title) in menuTitles.enumerated() where !title.trimmingCharacters(in: .whitespaces).isEmpty {
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
            } else {
                //print("⚠️ ArcCollector: no valid PID for \(window)")
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
        if AXUIElementCopyAttributeValue(element, AXAttr.help, &value) == .success, let help = value as? String, !help.isEmpty {
            return help
        }

        return "(Arc Tab)"
    }
}
