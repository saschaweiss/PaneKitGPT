import Foundation
import CoreGraphics

@MainActor
final class PaneKitEventManager {
    static let shared = PaneKitEventManager()
    
    private var isRunning = false
    private var observers: [Any] = [] // Platzhalter für AXObserver / NSWorkspace Notifications etc.
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        setupAccessibilityObservers()
        setupWorkspaceObservers()
    }
    
    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        isRunning = false
    }
}

extension PaneKitEventManager {
    private func setupAccessibilityObservers() {
        // Placeholder – später AXObserver integration
        // Hier könnten AXObserverCreate + CFRunLoopAddSource etc. folgen
    }
    
    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        
        // Beispielhafte Workspace-Events:
        observers.append(
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                           object: nil,
                           queue: .main) { _ in
                // später App Activation Event
            }
        )
        
        observers.append(
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil,
                           queue: .main) { _ in
                // später App Termination Event
            }
        )
    }
}

extension PaneKitEventManager {
    func handleEvent(_ event: PaneKitEvent) {
        switch event {
        case .windowCreated(let window),
             .tabCreated(let window):
            PaneKitCache.shared.store(window)
            
        case .windowClosed(let stableID),
             .tabClosed(let stableID):
            PaneKitCache.shared.remove(stableID)
            
        case .focusChanged(let stableID):
            updateFocus(for: stableID)
            
        case .windowMoved(let stableID, let frame, let screen):
            updateWindowPosition(stableID: stableID, frame: frame, screen: screen)
            
        case .windowResized(let stableID, let frame, let screen):
            updateWindowPosition(stableID: stableID, frame: frame, screen: screen)
        }
    }
}

extension PaneKitEventManager {
    private func updateFocus(for stableID: String) {
        for window in PaneKitCache.shared.all() {
            window.isFocused = (window.stableID == stableID)
        }
    }
    
    private func updateWindowPosition(stableID: String, frame: CGRect, screen: NSScreen) {
        guard let window = PaneKitCache.shared.get(stableID) else { return }
        window.frame = frame
        window.screen = screen
        window.zIndex = fetchZIndex(for: window)
    }
    
    private func fetchZIndex(for window: PaneKitWindow) -> Int {
        // TODO: Replace with CGWindowListCopyWindowInfo logic
        return 0
    }
}

enum PaneKitEvent {
    case windowCreated(PaneKitWindow)
    case windowClosed(stableID: String)
    case tabCreated(PaneKitWindow)
    case tabClosed(stableID: String)
    case focusChanged(stableID: String)
    case windowMoved(stableID: String, frame: CGRect, screen: NSScreen)
    case windowResized(stableID: String, frame: CGRect, screen: NSScreen)
}
