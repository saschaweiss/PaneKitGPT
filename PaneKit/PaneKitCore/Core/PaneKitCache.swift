import Foundation
import CoreGraphics

final class PaneKitCache {
    static let shared = PaneKitCache()
    private var cache: [String: PaneKitWindow] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    func store(_ window: PaneKitWindow) {
        lock.lock()
        cache[window.stableID] = window
        lock.unlock()
    }
    
    func store(_ windows: [PaneKitWindow]) {
        lock.lock()
        for window in windows {
            cache[window.stableID] = window
        }
        lock.unlock()
    }
    
    func get(_ stableID: String) -> PaneKitWindow? {
        lock.lock()
        let result = cache[stableID]
        lock.unlock()
        return result
    }
    
    func all() -> [PaneKitWindow] {
        lock.lock()
        let result = Array(cache.values)
        lock.unlock()
        return result
    }
    
    func focusedWindow() -> PaneKitWindow? {
        lock.lock()
        let result = cache.values.first(where: { $0.isFocused })
        lock.unlock()
        return result
    }
    
    func remove(_ stableID: String) {
        lock.lock()
        cache.removeValue(forKey: stableID)
        lock.unlock()
    }
    
    func removeAll(where predicate: (PaneKitWindow) -> Bool) {
        lock.lock()
        cache = cache.filter { !predicate($0.value) }
        lock.unlock()
    }
    
    func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
    
    func contains(_ stableID: String) -> Bool {
        lock.lock()
        let result = cache.keys.contains(stableID)
        lock.unlock()
        return result
    }
    
    func count() -> Int {
        lock.lock()
        let result = cache.count
        lock.unlock()
        return result
    }
    
    func debugDump() -> String {
        lock.lock()
        guard !cache.isEmpty else {
            lock.unlock()
            return "🪶 PaneKitCache leer"
        }
        var output = "📦 PaneKitCache Inhalt (\(cache.count) Elemente):\n"
        for window in cache.values.sorted(by: { $0.stableID < $1.stableID }) {
            let type = window.windowType.rawValue
            let focusMark = window.isFocused ? "⭐️" : " "
            let parent = window.parentID ?? "—"
            output += "• [\(type)] \(focusMark) ID: \(window.stableID) | Parent: \(parent) | App: \(window.bundleID)\n"
        }
        lock.unlock()
        return output
    }
}
