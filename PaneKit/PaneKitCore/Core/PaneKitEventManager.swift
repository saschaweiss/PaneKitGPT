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
        observers.removeAll()
        isRunning = false
    }
}

// MARK: - Event Dispatch

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

// MARK: - Internal Update Logic

extension PaneKitEventManager {
    private func updateFocus(for stableID: String) {
        for window in PaneKitCache.shared.all() {
            window.isFocused = (window.stableID == stableID)
        }
    }
    
    private func updateWindowPosition(stableID: String, frame: CGRect, screen: String) {
        guard let window = PaneKitCache.shared.get(stableID) else { return }
        window.frame = frame
        window.screen = screen
        window.zIndex = fetchZIndex(for: window)
    }
    
    private func fetchZIndex(for window: PaneKitWindow) -> Int {
        // Später durch echte AX/CGWindowList API ersetzen
        return 0
    }
}

// MARK: - Event Type Definition

enum PaneKitEvent {
    case windowCreated(PaneKitWindow)
    case windowClosed(stableID: String)
    case tabCreated(PaneKitWindow)
    case tabClosed(stableID: String)
    case focusChanged(stableID: String)
    case windowMoved(stableID: String, frame: CGRect, screen: String)
    case windowResized(stableID: String, frame: CGRect, screen: String)
}
