import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PaneKitEventManager {
    static let shared = PaneKitEventManager()
    
    private(set) var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    private var lastEventTimestamp: Date = .now
    private var suppressedIDs: Set<String> = []
    
    private var lastKnownFrames: [String: CGRect] = [:]
    private let eventQueue = DispatchQueue(label: "com.panekit.axevents", qos: .userInteractive)
    private var pendingEvents: [(String, AXUIElement)] = []
    private let stabilizationDelay: TimeInterval = 0.1
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        observers.removeAll()
        
        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching {
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
    
    private func attachToApp(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var observer: AXObserver?
        
        let callback: AXObserverCallback = { _, element, notification, _ in
            let notificationName = notification as String
            PaneKitEventManager.shared.enqueueAXEvent(name: notificationName, element: element)
        }
        
        let result = AXObserverCreate(app.processIdentifier, callback, &observer)
        guard result == .success, let observer else { return }
        
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] {
                for win in windows {
                    AXObserverAddNotification(observer, win, kAXMovedNotification as CFString, nil)
                    AXObserverAddNotification(observer, win, kAXResizedNotification as CFString, nil)
                }
                print("🪟 Beobachte \(windows.count) Fenster in \(app.localizedName ?? "Unbekannt")")
            }
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        print("✅ AXObserver aktiv für PID \(app.processIdentifier)")
    }
    
    private func enqueueAXEvent(name: String, element: AXUIElement) {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.pendingEvents.append((name, element))
            if self.pendingEvents.count == 1 {
                self.processNextAXEvent()
            }
        }
    }

    private func processNextAXEvent() {
        guard !pendingEvents.isEmpty else { return }
        let (name, element) = pendingEvents.removeFirst()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleAXNotification(name, element: element)
            self.eventQueue.asyncAfter(deadline: .now() + 0.005) {
                self.processNextAXEvent()
            }
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
    
    private func handleAXNotification(_ name: String, element: AXUIElement) {
        lastEventTimestamp = .now
        guard let window = PaneKitWindow.fromAXElement(element) else { return }
        let stableID = window.stableID
        if suppressedIDs.contains(stableID) { return }

        if name == AXNotify.moved.string || name == AXNotify.resized.string {
            guard let screen = window.screen else { return }
            let newFrame = window.frame
            let oldFrame = lastKnownFrames[stableID] ?? .zero
            guard !newFrame.equalTo(oldFrame) else { return }
            
            lastKnownFrames[stableID] = newFrame
            
            // Stabilisiere und unterdrücke Flood
            DispatchQueue.main.asyncAfter(deadline: .now() + stabilizationDelay) { [weak self] in
                guard let self else { return }
                let latestFrame = window.frame
                if latestFrame.equalTo(newFrame) {
                    let dx = abs(newFrame.origin.x - oldFrame.origin.x)
                    let dy = abs(newFrame.origin.y - oldFrame.origin.y)
                    let dw = abs(newFrame.size.width  - oldFrame.size.width)
                    let dh = abs(newFrame.size.height - oldFrame.size.height)
                    
                    if dw > 1 || dh > 1 {
                        self.handleEvent(.windowResized(stableID: stableID, frame: newFrame, screen: screen))
                    } else if dx > 1 || dy > 1 {
                        self.handleEvent(.windowMoved(stableID: stableID, frame: newFrame, screen: screen))
                    }
                }
            }
            return
        }
        
        switch name {
        case AXNotify.focusedWindowChanged.string:
            PaneKitCache.shared.store(window)
            handleEvent(.focusChanged(stableID: stableID))
        case AXNotify.created.string:
            handleEvent(.windowCreated(window))
        case AXNotify.uiElementDestroyed.string:
            handleEvent(.windowClosed(stableID: stableID))
        default:
            break
        }
    }
    
    private func handleEvent(_ event: PaneKitEvent) {
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
    
    private func updateFocus(for stableID: String) {
        for window in PaneKitCache.shared.all() {
            window.isFocused = (window.stableID == stableID)
        }
    }
    
    private func updateWindowPosition(stableID: String, frame: CGRect, screen: NSScreen) {
        guard let window = PaneKitCache.shared.get(stableID) else { return }
        if let last = lastKnownFrames[stableID], last.equalTo(frame) { return }
        
        suppressedIDs.insert(stableID)
        lastKnownFrames[stableID] = frame
        window.frame = frame
        window.screen = screen
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.suppressedIDs.remove(stableID)
        }
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
