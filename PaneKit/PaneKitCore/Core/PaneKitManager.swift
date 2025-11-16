import Foundation
import AppKit
import ApplicationServices

@MainActor
public final class PaneKitManager: Sendable {
    public static let shared = PaneKitManager()
    
    private var isRunning = false
    private var recoveryTimer: Timer?
    private let eventManager = PaneKitEventManager.shared
    private(set) var config = PaneKitConfiguration.default
    private let cache = PaneKitCache.shared
    
    private init() {}

    public func start(with configuration: PaneKitConfiguration? = nil, includingTabs: Bool = false) async {
        if let cfg = configuration {
            self.config = cfg
        }

        guard !isRunning else { return }
        isRunning = true
        
        cache.clear()
        eventManager.start()
        observeWorkspaceEvents()
        
        guard let pkApps = Application.runningApplications(), !pkApps.isEmpty else {
            return
        }

        await withTaskGroup(of: [PaneKitWindow].self) { group in
            for pkApp in pkApps {
                guard let bundleID = pkApp.runningApplication?.bundleIdentifier, !bundleID.isEmpty else { continue }
                group.addTask {
                    await PaneKitCollector.collectWindows(for: bundleID)
                }
            }

            for await windows in group {
                let realWindows = windows.filter { window in
                    let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let frame = window.frame
                    if title.isEmpty { return false }
                    if frame.width < 10 || frame.height < 10 { return false }
                    if window.pkWindow.role.lowercased() != "axwindow" && window.pkWindow.subrole.lowercased() != "axstandardwindow" {
                        return false
                    }
                    if window.screen == nil { return false }
                    if window.appName.contains("Agent") || window.appName.contains("Service") { return false }
                        
                    let axEl = window.element
                    var parent: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axEl, AXAttr.parent, &parent) == .success, let parentEl = parent {
                        var role: CFTypeRef?
                        if AXUIElementCopyAttributeValue(parentEl as! AXUIElement, AXAttr.role, &role) == .success, let roleStr = role as? String, !roleStr.lowercased().contains("application") {
                            return false
                        }
                    }
                        
                    if !(window.isVisible || window.isMinimized) { return false }

                    let role = window.pkWindow.role.lowercased()
                    if !role.contains("window") { return false }
                    
                    cache.store(window)
                    if config.enableLogging {
                        print("📑 Added window '\(window.title)' for \(window.appName)")
                    }
                    return true
                }
                
                if includingTabs {
                    Task.detached(priority: .background) {
                        for window in realWindows {
                            let tabs = await PaneKitCollector.collectTabs(for: window)
                            for tab in tabs {
                                await cache.store(tab)
                                if await self.config.enableLogging {
                                    print("📑 Added tab \(await window.appName) -> '\(await tab.title)'")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("✅ PaneKitManager gestartet – Cache, EventManager & Kollektoren aktiv.")
    }
}
