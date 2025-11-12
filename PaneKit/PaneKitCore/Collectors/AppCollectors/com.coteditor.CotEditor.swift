import Foundation
import ApplicationServices

@MainActor
final class com_coteditor_coteditor_AppCollector: PaneKitCollector, @unchecked Sendable {
    static let bundleIdent = "com.coteditor.CotEditor"
    
    public override func _collectWindows(for bundleID: String) async -> [PaneKitWindow] {
        guard Application.app(forBundleIdentifier: bundleID) != nil else {
            return []
        }
        
        guard let nsApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return []
        }

        let unifiedResult = await Self.collectUnified(for: nsApp, includeTabs: false)
        return unifiedResult.windows.compactMap { $0.window }
    }
    
    private static func collectUnified(for app: NSRunningApplication, includeTabs: Bool) async -> AppCollectorResult {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        guard let axWindows = safeAXChildren(of: axApp), !axWindows.isEmpty else {
            return AppCollectorResult(bundleID: bundleIdent, windows: [])
        }
        
        var hosts: [(AXUIElement, [(AXUIElement, String)])] = []
        var allTabTitles = Set<String>()
        var standaloneCandidates: [AXUIElement] = []

        for win in axWindows {
            let tabGroups = deepFindAllTabGroups(in: win)
            if !tabGroups.isEmpty {
                var tabs: [(AXUIElement, String)] = []
                for group in tabGroups {
                    if let buttons = safeAXChildren(of: group) {
                        for btn in buttons where safeAXRole(of: btn) == "AXRadioButton" {
                            let title = safeAXTitle(of: btn)
                            if !title.isEmpty {
                                tabs.append((btn, title))
                                allTabTitles.insert(title)
                            }
                        }
                    }
                }
                if !tabs.isEmpty {
                    hosts.append((win, tabs))
                }
            } else {
                standaloneCandidates.append(win)
            }
        }
        
        var windowResults: [PaneKitWindow] = []
        var tabResults: [PaneKitWindow] = []
        var seenHosts = Set<String>()

        for (win, tabs) in hosts {
            let winTitle = safeAXTitle(of: win)
            let hostTitle: String

            if !winTitle.isEmpty {
                hostTitle = winTitle
            } else if let firstTab = tabs.first?.1, !firstTab.isEmpty {
                hostTitle = firstTab
            } else {
                hostTitle = "(untitled)"
            }

            if seenHosts.contains(hostTitle) { continue }
            seenHosts.insert(hostTitle)

            var hostWindow: PaneKitWindow?

            if let hw = PaneKitWindow(pkWindow: PKWindow(axuiElement: win)) {
                hostWindow = hw
                windowResults.append(hw)
            }

            guard let hostWindow else { continue }

            for (index, (tabElement, _)) in tabs.enumerated() {
                let pkTab = PKWindow(
                    axuiElement: tabElement,
                    isTab: true,
                    parentTabHost: hostWindow.stableID,
                    pid: hostWindow.pid,
                    bundleID: hostWindow.bundleID
                )

                if let paneTab = PaneKitWindow(pkWindow: pkTab) {
                    paneTab.tabIndex = index
                    tabResults.append(paneTab)
                }
            }
        }
        
        var standalone: [PaneKitWindow] = []
        for win in standaloneCandidates {
            let title = safeAXTitle(of: win)
            if title.isEmpty || allTabTitles.contains(title) { continue }
            let pkWin = PKWindow(axuiElement: win)
            if let st = PaneKitWindow(pkWindow: pkWin) {
                standalone.append(st)
                windowResults.append(st)
            }
        }

        return AppCollectorResult(
            bundleID: bundleIdent,
            windows: windowResults.map { host in
                let hostTabs = includeTabs
                    ? tabResults.filter { $0.pkWindow.parentTabHost == host.stableID }
                    : []
                return AppCollectorResult.WindowGroup(window: host, tabs: hostTabs)
            }
        )
    }

    private static func deepFindAllTabGroups(in element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 10 else { return [] }
        var found: [AXUIElement] = []
        guard let children = safeAXChildren(of: element), !children.isEmpty else { return [] }
        for child in children {
            let role = safeAXRole(of: child)
            if role == "AXTabGroup" { found.append(child) }
            found.append(contentsOf: deepFindAllTabGroups(in: child, depth: depth + 1))
        }
        return found
    }
}
