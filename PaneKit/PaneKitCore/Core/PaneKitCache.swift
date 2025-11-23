import Foundation
import CoreGraphics

@MainActor
public final class PaneKitCache {
    public static let shared = PaneKitCache()
    private var cache: [String: PaneKitWindow] = [:]
    
    private init() {}
    
    public func store(_ window: PaneKitWindow) {
        cache[window.stableID] = window
        notifyUpdate()
    }
    
    public func store(_ windows: [PaneKitWindow]) {
        for window in windows {
            cache[window.stableID] = window
        }
        notifyUpdate()
    }
    
    public func get(_ stableID: String) -> PaneKitWindow? {
        cache[stableID]
    }
    
    public func all() -> [PaneKitWindow] {
        Array(cache.values)
    }
    
    public func focusedWindow() -> PaneKitWindow? {
        cache.values.first(where: { $0.isFocused })
    }
    
    public func remove(_ stableID: String) {
        cache.removeValue(forKey: stableID)
        notifyUpdate()
    }
    
    public func removeAll(where predicate: (PaneKitWindow) -> Bool) {
        cache = cache.filter { !predicate($0.value) }
        notifyUpdate()
    }
    
    public func clear() {
        cache.removeAll()
        notifyUpdate()
    }
    
    public func contains(_ stableID: String) -> Bool {
        cache.keys.contains(stableID)
    }
    
    public func count() -> Int {
        cache.count
    }
    
    // ✅ NEU: Notification senden bei Cache-Updates
    private func notifyUpdate() {
        NotificationCenter.default.post(name: .paneKitCacheDidUpdate, object: nil)
    }
    
    func debugDump() -> String {
        guard !cache.isEmpty else {
            return "🪶 PaneKitCache leer"
        }
        var output = "📦 PaneKitCache Inhalt (\(cache.count) Elemente):\n"
        for window in cache.values.sorted(by: { $0.stableID < $1.stableID }) {
            let type = window.windowType.rawValue
            let focusMark = window.isFocused ? "⭐️" : " "
            let parent = window.parentID ?? "—"
            output += "• [\(type)] \(focusMark) ID: \(window.stableID) | Parent: \(parent) | App: \(window.bundleID)\n"
        }
        return output
    }
}

// ✅ Notification Name Extension
extension Notification.Name {
    static let paneKitCacheDidUpdate = Notification.Name("PaneKitCacheDidUpdate")
}
