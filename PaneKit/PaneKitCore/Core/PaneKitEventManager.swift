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
    
    var isHealthy: Bool {
        let timeout: TimeInterval = 30
        let delta = Date().timeIntervalSince(lastEventTimestamp)
        return isRunning && !observers.isEmpty && delta < timeout
    }
    
    private func refreshWindows(for app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var rawWindows: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &rawWindows) == .success,
           let windowArray = rawWindows as? [Any],
           let windows = windowArray as? [AXUIElement],
           let observer = observers[app.processIdentifier] {
            for win in windows {
                AXObserverAddNotification(observer, win, kAXMovedNotification as CFString, nil)
                AXObserverAddNotification(observer, win, kAXResizedNotification as CFString, nil)
            }
        }
    }
}

extension PaneKitEventManager {
    private func attachToApp(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var observer: AXObserver?
        
        let callback: AXObserverCallback = { observer, element, notification, _ in
            guard let notification = notification as? String else { return }
            PaneKitEventManager.shared.enqueueAXEvent(name: notification, element: element)
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
            AXNotify.uiElementDestroyed.string,
            AXNotify.windowMiniaturized.string,
            AXNotify.windowDeminiaturized.string
        ]
        
        for note in notifications {
            AXObserverAddNotification(observer, axApp, note as CFString, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
               let windowArray = value as? [Any],
               let windows = windowArray as? [AXUIElement] {
                print("🪟 \(windows.count) Fenster beobachtet in \(app.localizedName ?? "Unbekannt")")
                for win in windows {
                    AXObserverAddNotification(observer, win, kAXMovedNotification as CFString, nil)
                    AXObserverAddNotification(observer, win, kAXResizedNotification as CFString, nil)
                }
            } else {
                print("⚠️ Keine Fenster gefunden für \(app.localizedName ?? "Unbekannt")")
            }
        }
        
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    
    private func enqueueAXEvent(name: String, element: AXUIElement) {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.pendingEvents.append((name, element))
            // Wenn kein anderes Event läuft, verarbeiten
            if self.pendingEvents.count == 1 {
                self.processNextAXEvent()
            }
        }
    }

    private func processNextAXEvent() {
        guard !pendingEvents.isEmpty else { return }
        let (name, element) = pendingEvents.removeFirst()

        // Synchron verarbeiten, garantiert auf MainQueue
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleAXNotification(name, element: element)
            // Nächstes Event kurz danach
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

        if suppressedIDs.contains(stableID) { return }

        if name == AXNotify.moved.string || name == AXNotify.resized.string {
            guard let screen = window.screen else { return }
            let newFrame = window.frame
            let oldFrame = lastKnownFrames[stableID] ?? .zero

            guard !newFrame.equalTo(oldFrame) else { return }

            let moved = abs(newFrame.origin.x - oldFrame.origin.x) > 1 || abs(newFrame.origin.y - oldFrame.origin.y) > 1
            let resized = abs(newFrame.size.width - oldFrame.size.width) > 1 || abs(newFrame.size.height - oldFrame.size.height) > 1
            
            lastKnownFrames[stableID] = newFrame
            moveResizeWorkItems[stableID]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let dx = abs(newFrame.origin.x - oldFrame.origin.x)
                    let dy = abs(newFrame.origin.y - oldFrame.origin.y)
                    let dw = abs(newFrame.size.width  - oldFrame.size.width)
                    let dh = abs(newFrame.size.height - oldFrame.size.height)

                    let posChanged = dx > 1 || dy > 1
                    let sizeChanged = dw > 1 || dh > 1

                    // Verlaufspuffer aktualisieren
                    var sizes = resizeSamples[stableID, default: []]
                    var points = moveSamples[stableID, default: []]
                    if sizes.count > 3 { sizes.removeFirst() }
                    if points.count > 3 { points.removeFirst() }
                    sizes.append(newFrame.size)
                    points.append(newFrame.origin)
                    resizeSamples[stableID] = sizes
                    moveSamples[stableID] = points

                    let movedStable = posChanged && !sizeChanged && Set(points.map { $0 }).count > 1 && Set(sizes.map { $0 }).count == 1
                    let resizedStable = sizeChanged && !posChanged && Set(sizes.map { $0 }).count > 1 && Set(points.map { $0 }).count == 1

                    if resizedStable {
                        print("🟩 resize erkannt (stabile Größenänderung)")
                        self.handleEvent(.windowResized(stableID: stableID, frame: newFrame, screen: screen))
                    } else if movedStable {
                        print("🟦 move erkannt (stabile Positionsänderung)")
                        self.handleEvent(.windowMoved(stableID: stableID, frame: newFrame, screen: screen))
                    }
                }
            }

            moveResizeWorkItems[stableID] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + moveResizeDelay, execute: workItem)
            return
        }
        
        switch name {
            case AXNotify.focusedWindowChanged.string:
                PaneKitCache.shared.store(window)
                handleEvent(.focusChanged(stableID: stableID))

            case AXNotify.created.string:
                handleEvent(.windowCreated(window))
                if let observer = observers[window.pid] {
                    AXObserverAddNotification(observer, window.element, AXNotify.moved.raw, nil)
                    AXObserverAddNotification(observer, window.element, AXNotify.resized.raw, nil)
                }

            case AXNotify.uiElementDestroyed.string:
                handleEvent(.windowClosed(stableID: stableID))

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
        if isDragging {
            lastDraggedStableID = stableID
            lastFrameDuringDrag = frame
            lastScreenDuringDrag = screen
            return
        }

        updateWindowPosition(stableID: stableID, frame: frame, screen: screen)
    }
    
    @MainActor
    private func flushPendingWindowChanges() {
        let changes = Self.pendingWindowChanges
        Self.pendingWindowChanges.removeAll()

        for (stableID, change) in changes {
            updateWindowPosition(stableID: stableID, frame: change.frame, screen: change.screen)
        }
    }
    
    private func setupGlobalMouseTracking() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            self.isDragging = true
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in
                self.isDragging = false

                for (stableID, change) in Self.pendingWindowChanges {
                    self.updateWindowPosition(stableID: stableID, frame: change.frame, screen: change.screen)
                }

                Self.pendingWindowChanges.removeAll()
                self.lastDraggedStableID = nil
                self.lastFrameDuringDrag = nil
                self.lastScreenDuringDrag = nil
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
        guard let window = PaneKitCache.shared.get(stableID) else { return }
        if let last = lastKnownFrames[stableID], last.equalTo(frame) { return }

        print("updateWindowPosition (executing once per completed drag)")

        suppressedIDs.insert(stableID)

        lastKnownFrames[stableID] = frame
        window.frame = frame
        window.screen = screen
        window.zIndex = fetchZIndex(for: window)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.suppressedIDs.remove(stableID)
        }
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
