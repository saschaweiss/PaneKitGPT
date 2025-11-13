import Foundation
import CoreGraphics

/// Thread-sicherer In-Memory-Cache für PaneKitWindow-Objekte.
/// Jeder Eintrag ist über seine stableID eindeutig identifizierbar.
/// Nur PaneKitManager (und später EventManager) dürfen schreiben.
/// Alle Module dürfen lesen.
final class PaneKitCache {
    
    // MARK: - Singleton
    static let shared = PaneKitCache()
    
    // MARK: - Private Storage
    private var cache: [String: PaneKitWindow] = [:] // stableID -> Window
    private let queue = DispatchQueue(label: "com.panekit.cache", attributes: .concurrent)
    
    private init() {}
    
    // MARK: - Schreiben
    
    /// Speichert oder aktualisiert ein einzelnes Fenster im Cache.
    /// Falls die stableID bereits existiert, wird der Eintrag ersetzt.
    func store(_ window: PaneKitWindow) {
        queue.async(flags: .barrier) {
            self.cache[window.stableID] = window
        }
    }
    
    /// Speichert oder aktualisiert mehrere Fenster atomar.
    /// Alle Objekte werden anhand ihrer stableID dedupliziert.
    func store(_ windows: [PaneKitWindow]) {
        queue.async(flags: .barrier) {
            for window in windows {
                self.cache[window.stableID] = window
            }
        }
    }
    
    // MARK: - Lesen
    
    /// Gibt ein einzelnes Fenster anhand seiner stableID zurück.
    func get(_ stableID: String) -> PaneKitWindow? {
        queue.sync {
            cache[stableID]
        }
    }
    
    /// Gibt alle aktuell im Cache gespeicherten Fenster zurück.
    func all() -> [PaneKitWindow] {
        queue.sync {
            Array(cache.values)
        }
    }
    
    /// Gibt das aktuell fokussierte Fenster zurück, falls bekannt.
    /// Erwartet, dass PaneKitWindow eine Property `isFocused: Bool` besitzt.
    func focusedWindow() -> PaneKitWindow? {
        queue.sync {
            cache.values.first(where: { $0.isFocused })
        }
    }
    
    // MARK: - Entfernen
    
    /// Entfernt ein einzelnes Fenster anhand seiner stableID.
    func remove(_ stableID: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: stableID)
        }
    }
    
    /// Entfernt alle Fenster, die einer bestimmten Bedingung entsprechen.
    func removeAll(where predicate: (PaneKitWindow) -> Bool) {
        queue.async(flags: .barrier) {
            self.cache = self.cache.filter { !predicate($0.value) }
        }
    }
    
    /// Leert den gesamten Cache.
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
    
    // MARK: - Status
    
    /// Prüft, ob ein Fenster mit der angegebenen stableID existiert.
    func contains(_ stableID: String) -> Bool {
        queue.sync {
            cache.keys.contains(stableID)
        }
    }
    
    /// Gibt die aktuelle Anzahl der Fenster im Cache zurück.
    func count() -> Int {
        queue.sync {
            cache.count
        }
    }
    
    // MARK: - Debug
    
    /// Gibt eine formatierte Übersicht des Cache-Inhalts aus.
    /// Ideal für Logging oder Konsolen-Debugging.
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
