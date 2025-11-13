import Foundation
import CoreGraphics

actor PaneKitCache {
    static let shared = PaneKitCache()
    private var cache: [String: PaneKitWindow] = [:]
    
    private init() {}
    
    func store(_ window: PaneKitWindow) {
        cache[window.stableID] = window
    }
    
    func store(_ windows: [PaneKitWindow]) {
        for window in windows {
            cache[window.stableID] = window
        }
    }
    
    func get(_ stableID: String) -> PaneKitWindow? {
        cache[stableID]
    }
    
    func all() -> [PaneKitWindow] {
        Array(cache.values)
    }
    
    func focusedWindow() -> PaneKitWindow? {
        cache.values.first(where: { $0.isFocused })
    }
    
    func remove(_ stableID: String) {
        cache.removeValue(forKey: stableID)
    }
    
    func removeAll(where predicate: (PaneKitWindow) -> Bool) {
        cache = cache.filter { !predicate($0.value) }
    }
    
    func clear() {
        cache.removeAll()
    }
    
    func contains(_ stableID: String) -> Bool {
        cache.keys.contains(stableID)
    }
    
    func count() -> Int {
        cache.count
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
