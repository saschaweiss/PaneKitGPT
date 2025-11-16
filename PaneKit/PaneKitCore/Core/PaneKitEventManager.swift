import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PaneKitEventManager {
    static let shared = PaneKitEventManager()
    
    private(set) var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    private var lastEventTimestamp: Date = .now
    
    private var isDragging: Bool = false
    private var lastStableID: String?
    private var lastDraggedStableID: String?
    private static var pendingWindowChanges: [String: (frame: CGRect, screen: NSScreen, lastUpdate: Date)] = [:]
    private static let moveResizeDebounceInterval: TimeInterval = 0.25
    
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
            AXNotify.resized.string,
            AXNotify.focusedWindowChanged.string,
            AXNotify.created.string,
            AXNotify.uiElementDestroyed.string
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
        
        if observers.isEmpty {
            print("⚠️ Keine aktiven AXObserver mehr – Recovery geplant.")
            PaneKitManager.shared.scheduleRecoveryIfNeeded()
        }
    }
    
    @MainActor
    public func observeWorkspaceEvents() {
        let nc = NSWorkspace.shared.notificationCenter
        
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let self = self else { return }
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            
            print("🆕 App gestartet: \(app.localizedName ?? "Unbekannt")")
            self.attachToApp(app)
            
            PaneKitManager.shared.scheduleRecoveryIfNeeded()
        }
        
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let self = self else { return }
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            
            print("❌ App geschlossen: \(app.localizedName ?? "Unbekannt")")
            self.detachApp(app)
            
            if self.observers.isEmpty {
                print("⚠️ Keine aktiven AXObserver mehr – Recovery geplant.")
                PaneKitManager.shared.scheduleRecoveryIfNeeded()
            }
        }
    }
}

extension PaneKitEventManager {
    private static var debounceTimer: Timer?
    private static var suppressedStableIDs: [String: Date] = [:]
    
    private func handleAXNotification(_ name: String, element: AXUIElement) {
        lastEventTimestamp = .now
        guard let window = PaneKitWindow.fromAXElement(element) else { return }
        let stableID = window.stableID

        if isDragging && (name == kAXMovedNotification || name == kAXResizedNotification) {
            if let screen = window.screen {
                Self.pendingWindowChanges[stableID] = (window.frame, screen, Date())
            }
            return
        }
        
        switch name {
            case kAXFocusedWindowChangedNotification:
                if let window = PaneKitWindow.fromAXElement(element) {
                    PaneKitCache.shared.store(window)
                    handleEvent(.focusChanged(stableID: window.stableID))
                }
                
            case kAXMovedNotification:
                if let window = PaneKitWindow.fromAXElement(element), let screen = window.screen {
                    handleEvent(.windowMoved(stableID: window.stableID, frame: window.frame, screen: screen))
                }
                
            case kAXResizedNotification:
                if let window = PaneKitWindow.fromAXElement(element), let screen = window.screen {
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
                handleMoveOrResize(stableID: stableID, frame: frame, screen: screen)
        }
    }
    
    @MainActor
    private func handleMoveOrResize(stableID: String, frame: CGRect, screen: NSScreen) {
        if NSEvent.pressedMouseButtons != 0 {
            isDragging = true
            lastDraggedStableID = stableID
            Self.pendingWindowChanges[stableID] = (frame, screen, Date())
            debounceFlushPendingChanges()
            return
        }

        if isDragging {
            isDragging = false
            if let (finalFrame, finalScreen, _) = Self.pendingWindowChanges[stableID] {
                updateWindowPosition(stableID: stableID, frame: finalFrame, screen: finalScreen)
            }
            Self.pendingWindowChanges.removeAll()
            Self.debounceTimer?.invalidate()
        }
    }
    
    @MainActor
    private func flushPendingWindowChanges() {
        let changes = Self.pendingWindowChanges
        Self.pendingWindowChanges.removeAll()

        for (stableID, change) in changes {
            updateWindowPosition(stableID: stableID, frame: change.frame, screen: change.screen)
        }
    }

    @MainActor
    private func debounceFlushPendingChanges() {
        Self.debounceTimer?.invalidate()

        Self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self else { return }

            if NSEvent.pressedMouseButtons == 0 {
                self.flushPendingWindowChanges()
                Self.debounceTimer?.invalidate()
                Self.debounceTimer = nil
            } else {
                Self.debounceTimer?.invalidate()
                Self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                    self.debounceFlushPendingChanges()
                }
            }
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
        print("updateWindowPosition (executing once per completed drag)")

        Self.suppressedStableIDs[stableID] = Date()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.suppressedStableIDs.removeValue(forKey: stableID)
        }

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
