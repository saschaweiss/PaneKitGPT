import Foundation
import CoreGraphics

/// Thread-sicherer In-Memory-Cache für PaneKitWindow.
/// Identifiziert Fenster eindeutig über `stableID`.
/// Nur PaneKitManager (und später EventManager) darf schreiben.
@unchecked Sendable
final class PaneKitCache {
    
    // MARK: - Singleton
    static let shared = PaneKitCache()
    
    // MARK: - Private Storage
    private var cache: [String: PaneKitWindow] = [:] // stableID -> Window
    private let queue = DispatchQueue(label: "com.panekit.cache", attributes: .concurrent)
    
    private init() {}
    
    func store(_ window: PaneKitWindow) {
        queue.async(flags: .barrier) { [self] in
            cache[window.stableID] = window
        }
    }
    
    func store(_ windows: [PaneKitWindow]) {
        queue.async(flags: .barrier) { [self] in
            for window in windows {
                cache[window.stableID] = window
            }
        }
    }
    
    func get(_ stableID: String) -> PaneKitWindow? {
        queue.sync {
            cache[stableID]
        }
    }
    
    func all() -> [PaneKitWindow] {
        queue.sync {
            Array(cache.values)
        }
    }
    
    func focusedWindow() -> PaneKitWindow? {
        queue.sync {
            cache.values.first(where: { $0.isFocused })
        }
    }
    
    func remove(_ stableID: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: stableID)
        }
    }
    
    func removeAll(where predicate: (PaneKitWindow) -> Bool) {
        queue.async(flags: .barrier) {
            self.cache = self.cache.filter { !predicate($0.value) }
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
    
    func contains(_ stableID: String) -> Bool {
        queue.sync {
            cache.keys.contains(stableID)
        }
    }
    
    func count() -> Int {
        queue.sync {
            cache.count
        }
    }
    
    func debugDump() -> String {
        queue.sync {
            if cache.isEmpty {
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
}
