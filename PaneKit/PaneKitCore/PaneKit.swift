import Foundation
import AppKit

@MainActor
public final class PaneKit {
    public static let shared = PaneKit()
    private let manager = PaneKitManager.shared

    public init(notifyOnMainThread: Bool = true, enableLogging: Bool = false, includingTabs: Bool = false) {
        Task {
            await manager.start(includingTabs: includingTabs)
            AXPermissionHelper.ensurePermission()
        }
    }
    
    public func runningApps() async -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications
    }
}
