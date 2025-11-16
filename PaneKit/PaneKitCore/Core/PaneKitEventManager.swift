import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PaneKitEventManager {
    static let shared = PaneKitEventManager()
    
    private(set) var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    private var lastEventTimestamp: Date = .now
    private var recoveryTimer: Timer?
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        observers.removeAll()
        
        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching && app.isActive {
            attachToApp(app)
        }
        
        setupWorkspaceObservers()
        print("👂 PaneKitEventManager gestartet")
    }
    
    func stop() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        isRunning = false
        print("🛑 PaneKitEventManager gestoppt")
    }
    
    var isHealthy: Bool {
        let timeout: TimeInterval = 30
        let delta = Date().timeIntervalSince(lastEventTimestamp)
        return isRunning && !observers.isEmpty && delta < timeout
    }
}

extension PaneKitEventManager {
    private func attachToApp(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var observer: AXObserver?
        
        let callback: AXObserverCallback = { _, element, notification, _ in
            guard let notification = notification as? String else { return }
            Task { @MainActor in
                PaneKitEventManager.shared.handleAXNotification(notification, element: element)
            }
        }
        
        let result = AXObserverCreate(app.processIdentifier, callback, &observer)
        
        guard result == .success, let observer = observer else {
            print("⚠️ AXObserver konnte nicht für \(app.localizedName ?? "Unbekannt") erstellt werden.")
            PaneKitManager.shared.scheduleRecoveryIfNeeded()
            return
        }
        
        observers[app.processIdentifier] = observer
            
        let notifications = [
            AXNotify.moved.string,
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
    
    func detachApp(_ app: NSRunningApplication) {
        guard let observer = observers.removeValue(forKey: app.processIdentifier) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    
    public func observeWorkspaceEvents() {
        let nc = NSWorkspace.shared.notificationCenter
        
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            print("🆕 App gestartet: \(app.localizedName ?? "Unbekannt")")
            self.attachToApp(app)
        }
        
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            print("❌ App geschlossen: \(app.localizedName ?? "Unbekannt")")
            self.detachApp(app)
        }
    }
    
    func scheduleRecoveryIfNeeded() {
        guard recoveryTimer == nil else { return }
        
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recoverIfNeeded()
            }
        }
        
        print("🩺 Recovery-Timer aktiviert (alle 20s).")
    }
    
    public func recoverIfNeeded() {
        if !self.isHealthy {
            print("⚠️ EventManager inaktiv – versuche Neuverbindung...")
            self.stop()
            self.start()
        }
    }
    
    public func stopRecoveryTimer() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }
}

extension PaneKitEventManager {
    private func handleAXNotification(_ name: String, element: AXUIElement) {
        lastEventTimestamp = .now
        
        switch name {
            case kAXFocusedWindowChangedNotification:
                if let window = PaneKitWindow.fromAXElement(element) {
                    PaneKitCache.shared.store(window)
                    handleEvent(.focusChanged(stableID: window.stableID))
                }
                
            case kAXMovedNotification:
                if let window = PaneKitWindow.fromAXElement(element),
                   let screen = window.screen {
                    handleEvent(.windowMoved(stableID: window.stableID, frame: window.frame, screen: screen))
                }
                
            case kAXResizedNotification:
                if let window = PaneKitWindow.fromAXElement(element),
                   let screen = window.screen {
                    handleEvent(.windowResized(stableID: window.stableID, frame: window.frame, screen: screen))
                }
                
            case kAXCreatedNotification:
                if let window = PaneKitWindow.fromAXElement(element) {
                    handleEvent(.windowCreated(window))
                }
                
            case kAXUIElementDestroyedNotification:
                if let window = PaneKitWindow.fromAXElement(element) {
                    handleEvent(.windowClosed(stableID: window.stableID))
                }
                
            default:
                break
        }
    }
    
    func handleEvent(_ event: PaneKitEvent) {
        switch event {
            case .windowCreated(let window), .tabCreated(let window):
                PaneKitCache.shared.store(window)
                
            case .windowClosed(let stableID), .tabClosed(let stableID):
                PaneKitCache.shared.remove(stableID)
                
            case .focusChanged(let stableID):
                updateFocus(for: stableID)
                
            case .windowMoved(let stableID, let frame, let screen),
                 .windowResized(let stableID, let frame, let screen):
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
