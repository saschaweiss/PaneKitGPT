import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PaneKitEventManager {
    static let shared = PaneKitEventManager()
    
    private var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching && app.isActive {
            attachToApp(app)
        }
        
        setupWorkspaceObservers()
    }
    
    func stop() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        isRunning = false
    }
}

extension PaneKitEventManager {
    private func attachToApp(_ app: NSRunningApplication) {
        guard let axApp = AXUIElementCreateApplication(app.processIdentifier) as AXUIElement? else { return }
        var observer: AXObserver?
        
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let notification = notification as? String else { return }
            Task { @MainActor in
                PaneKitEventManager.shared.handleAXNotification(notification, element: element)
            }
        }
        
        if AXObserverCreate(app.processIdentifier, callback, &observer) == .success, let observer = observer {
            observers[app.processIdentifier] = observer
            
            let notifications = [
                kAXMovedNotification,
                kAXResizedNotification,
                kAXFocusedWindowChangedNotification,
                kAXCreatedNotification,
                kAXUIElementDestroyedNotification
            ]
            
            for note in notifications {
                AXObserverAddNotification(observer, axApp, note as CFString, nil)
            }
            
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
    
    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attachToApp(app)
        }
        
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.detachApp(app)
        }
    }
    
    private func detachApp(_ app: NSRunningApplication) {
        guard let observer = observers.removeValue(forKey: app.processIdentifier) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

extension PaneKitEventManager {
    private func handleAXNotification(_ name: String, element: AXUIElement) {
        switch name {
        case AXNotify.focusedWindowChanged.string:
            if let window = PaneKitWindow.fromAXElement(element) {
                PaneKitCache.shared.store(window)
                handleEvent(.focusChanged(stableID: window.stableID))
            }
            
        case AXNotify.moved.string:
            if let window = PaneKitWindow.fromAXElement(element) {
                handleEvent(.windowMoved(stableID: window.stableID, frame: window.frame, screen: window.screen ?? NSScreen.main!))
            }
            
        case AXNotify.resized.string:
            if let window = PaneKitWindow.fromAXElement(element) {
                handleEvent(.windowResized(stableID: window.stableID, frame: window.frame, screen: window.screen ?? NSScreen.main!))
            }
            
        case AXNotify.created.string:
            if let window = PaneKitWindow.fromAXElement(element) {
                handleEvent(.windowCreated(window))
            }
            
        case AXNotify.uiElementDestroyed.string:
            if let window = PaneKitWindow.fromAXElement(element) {
                handleEvent(.windowClosed(stableID: window.stableID))
            }
            
        default:
            break
        }
    }
}

extension PaneKitEventManager {
    func handleEvent(_ event: PaneKitEvent) {
        switch event {
        case .windowCreated(let window), .tabCreated(let window):
            print(window.appName)
            PaneKitCache.shared.store(window)
            
        case .windowClosed(let stableID), .tabClosed(let stableID):
            print(stableID)
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
        print("updateFocus")
        for window in PaneKitCache.shared.all() {
            window.isFocused = (window.stableID == stableID)
        }
    }
    
    private func updateWindowPosition(stableID: String, frame: CGRect, screen: NSScreen) {
        print("updateWindowPosition")
        guard let window = PaneKitCache.shared.get(stableID) else { return }
        window.frame = frame
        window.screen = screen
        window.zIndex = fetchZIndex(for: window)
    }
    
    private func fetchZIndex(for window: PaneKitWindow) -> Int {
        print("fetchZIndex")
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
