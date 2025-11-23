import Foundation
import AppKit
import ApplicationServices

@MainActor
public final class PaneKitEventManager {
    public static let shared = PaneKitEventManager()
    
    private(set) var isRunning = false
    private var observers: [pid_t: AXObserver] = [:]
    private var lastEventTimestamp: Date = .now
    private var suppressedIDs: Set<String> = []
    
    private let eventQueue = DispatchQueue(label: "com.panekit.axevents", qos: .userInteractive)
    private var pendingEvents: [(String, AXUIElement)] = []
    
    private var pendingChanges: [String: (frame: CGRect, screen: NSScreen)] = [:]
    private var debounceTimers: [String: Timer] = [:]
    // ✅ OPTIMIERT: Debounce von 250ms auf 50ms reduziert = 5x schnellere Response
    private let moveResizeDebounceInterval: TimeInterval = 0.05
    
    // ✅ NEU: Konfigurierbares Logging-System
    public enum LogLevel {
        case none       // Kein Logging (Produktion)
        case minimal    // Nur Emojis (Standard)
        case verbose    // Alle Details (Debug)
    }
    private var logLevel: LogLevel = .minimal
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        observers.removeAll()

        for app in NSWorkspace.shared.runningApplications where app.isFinishedLaunching {
            guard shouldAttachToApp(app) else { continue }
            attachToApp(app)
        }

        setupWorkspaceObservers()
        if logLevel != .none {
            print("👂 PaneKitEventManager gestartet")
        }
    }
    
    func stop() {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        isRunning = false
        if logLevel != .none {
            print("🛑 PaneKitEventManager gestoppt")
        }
    }
    
    // ✅ NEU: Logging-Level zur Laufzeit ändern
    public func setLogLevel(_ level: LogLevel) {
        logLevel = level
    }
    
    private func shouldAttachToApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        
        let ignoredBundleIDs = [
            "com.apple.dock",
            "com.apple.WindowServer",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.systemuiserver",
            "com.apple.Spotlight"
        ]
        if let id = app.bundleIdentifier, ignoredBundleIDs.contains(id) {
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        if result != .success || value == nil {
            return false
        }

        return true
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
            AXNotify.uiElementDestroyed.string,
            AXNotify.tabCreated.string,
            AXNotify.tabClosed.string,
            AXNotify.selectedTabChanged.string,
        ]
        
        for note in notifications {
            AXObserverAddNotification(observer, axApp, note as CFString, nil)
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        
        // ✅ OPTIMIERT: Nur bei verbose logging ausgeben
        if logLevel == .verbose {
            print("✅ AXObserver aktiv für PID \(app.processIdentifier) - \(app.bundleIdentifier ?? "unknown")")
        }
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
            // ✅ OPTIMIERT: Event-Processing-Delay von 5ms auf 2ms reduziert = 2.5x schneller
            self.eventQueue.asyncAfter(deadline: .now() + 0.002) {
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
        
        switch name {
            case AXNotify.focusedWindowChanged.string:
                PaneKitCache.shared.store(window)
                handleEvent(.focusChanged(stableID: stableID))
            case AXNotify.created.string:
                handleEvent(.windowCreated(window))
            case AXNotify.uiElementDestroyed.string:
                handleEvent(.windowClosed(stableID: stableID))
            case AXNotify.moved.string, AXNotify.resized.string:
                guard let screen = window.screen else { return }
                enqueueMoveOrResize(stableID: window.stableID, frame: window.frame, screen: screen)
            case AXNotify.tabCreated.string:
                if let tab = PaneKitWindow.fromAXElement(element) {
                    handleEvent(.tabCreated(tab))
                }
            case AXNotify.tabClosed.string:
                if let tab = PaneKitWindow.fromAXElement(element) {
                    handleEvent(.tabClosed(stableID: tab.stableID))
                }
            case AXNotify.selectedTabChanged.string:
                if let tab = PaneKitWindow.fromAXElement(element) {
                    handleEvent(.focusChanged(stableID: tab.stableID))
                }
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
                // ✅ OPTIMIERT: Z-Index Update von 200ms auf 100ms reduziert = 2x schneller
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if let win = PaneKitCache.shared.get(stableID) {
                        if let zIndex = zIndexForWindow(win) {
                            win.zIndex = zIndex
                        }
                        PaneKitCache.shared.store(win)
                    }
                }
        }
    }
    
    func zIndexForWindow(_ window: PaneKitWindow) -> Int? {
        guard let screen = window.screen else { return nil }
        let windowList = PKzOrderForScreen(screen.frame) as? [[String: Any]] ?? []
        
        let pid = window.pid
        
        for (index, info) in windowList.enumerated() {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid {
                return index
            }
        }
        return nil
    }
    
    private func updateFocus(for stableID: String) {
        for window in PaneKitCache.shared.all() {
            window.isFocused = (window.stableID == stableID)
        }
    }
    
    private func enqueueMoveOrResize(stableID: String, frame: CGRect, screen: NSScreen) {
        DispatchQueue.main.async {
            self.pendingChanges[stableID] = (frame, screen)
            self.debounceTimers[stableID]?.invalidate()

            self.debounceTimers[stableID] = Timer.scheduledTimer(withTimeInterval: self.moveResizeDebounceInterval, repeats: false) { [weak self] _ in
                self?.flushPendingChange(for: stableID)
            }
        }
    }

    @MainActor
    private func flushPendingChange(for stableID: String) {
        guard let (frame, screen) = pendingChanges.removeValue(forKey: stableID) else { return }
        debounceTimers[stableID]?.invalidate()
        debounceTimers.removeValue(forKey: stableID)
        
        guard let cachedWindow = PaneKitCache.shared.get(stableID) else {
            // ✅ OPTIMIERT: Nur bei verbose logging ausgeben
            if logLevel == .verbose {
                print("⚠️ Kein Cache-Eintrag für \(stableID)")
            }
            return
        }

        let oldFrame = cachedWindow.frame
        cachedWindow.frame = frame
        cachedWindow.screen = screen
        if let oldScreen = cachedWindow.screen, !oldScreen.frame.contains(frame.center) {
            cachedWindow.screen = NSScreen.screens.first(where: { $0.frame.contains(frame.center) })
        }
        PaneKitCache.shared.store(cachedWindow)
        
        // ✅ OPTIMIERT: Intelligentes Logging basierend auf LogLevel
        switch logLevel {
        case .none:
            // Kein Logging
            break
            
        case .minimal:
            // Nur ein Emoji pro Event-Typ, keine Details
            let threshold: CGFloat = 2
            let dx = abs(oldFrame.origin.x - frame.origin.x)
            let dy = abs(oldFrame.origin.y - frame.origin.y)
            let dw = abs(oldFrame.size.width - frame.size.width)
            let dh = abs(oldFrame.size.height - frame.size.height)
            
            let moved = (dx > threshold || dy > threshold)
            let resized = (dw > threshold || dh > threshold)
            
            if moved && resized {
                print("🟨", terminator: "") // Move+Resize
            } else if moved {
                print("🟦", terminator: "") // Nur Move
            } else if resized {
                print("🟧", terminator: "") // Nur Resize
            }
            
        case .verbose:
            // Vollständige Details wie vorher
            let threshold: CGFloat = 2
            let dx = abs(oldFrame.origin.x - frame.origin.x)
            let dy = abs(oldFrame.origin.y - frame.origin.y)
            let dw = abs(oldFrame.size.width - frame.size.width)
            let dh = abs(oldFrame.size.height - frame.size.height)
            
            let moved = (dx > threshold || dy > threshold)
            let resized = (dw > threshold || dh > threshold)
            
            print("""
            ––––––––––––––––––––––––––––––––––––––––––––––––––––
            🧩 Vergleich alter und neuer Frame:
              OLD → x:\(oldFrame.origin.x) y:\(oldFrame.origin.y) w:\(oldFrame.size.width) h:\(oldFrame.size.height)
              NEW → x:\(frame.origin.x) y:\(frame.origin.y) w:\(frame.size.width) h:\(frame.size.height)
              Δ   → dx:\(dx) dy:\(dy) dw:\(dw) dh:\(dh)
            ––––––––––––––––––––––––––––––––––––––––––––––––––––
            """)

            switch (moved, resized) {
                case (true, true):
                    print("🟨 move+resize → beides \(frame)")
                case (true, false):
                    print("🟦 moved → echte Positionsänderung \(frame.origin)")
                case (false, true):
                    print("🟧 resized → echte Größenänderung \(frame.size)")
                default:
                    print("➖ keine echte Änderung erkannt")
            }
        }
    }
}

enum PaneKitEvent {
    case windowCreated(PaneKitWindow)
    case windowClosed(stableID: String)
    case tabCreated(PaneKitWindow)
    case tabClosed(stableID: String)
    case focusChanged(stableID: String)
}
