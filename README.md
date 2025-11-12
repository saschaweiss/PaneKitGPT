# PaneKit

PaneKit is a lightweight macOS framework for inspecting, managing, and observing application windows using a unified Swift interface.  
It provides access to real window metadata, supports app-specific collectors, and integrates optional real-time notifications for window and tab changes.

---

## Features

- 🪟 Enumerate all visible windows and tabs across applications  
- 🧩 App-specific collectors for enhanced window detection  
- 🔍 Access complete window metadata (title, PID, bounds, z-index, screen, etc.)  
- ⚡ Optional lazy tab loading and JSON-based caching  
- 🧠 Thread-safe window registry with stable identifiers  
- 📣 Real-time updates via `PaneKitNotificationCenter` (title changes, position, focus, etc.)  
- 🧱 Written in Swift, integrates with private CoreGraphics (CGS) and Accessibility (AX) APIs  
- ⚠️ Uses **private CGS APIs** — not App Store safe

---

## Requirements

- macOS 14.0 or later  
- Swift 6 or later  
- Full Accessibility permissions (System Settings → Privacy & Security → Accessibility)  
- Xcode 15 or later  

---

## Installation

### Swift Package Manager

Add PaneKit to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/saschaweiss/PaneKit.git", from: "1.0.0")
]
```

Then import it in your code:

```swift
import PaneKit
```

---

## Quick Start

Initialize PaneKit and collect all current windows:

```swift
import PaneKit

@main
struct DemoApp {
    private var panekit: PaneKit?

    static func main() async {
        let allResults = Array(try await panekit.getAllWindowsAndTabs())

        for result in allResults {
            print("App: \(result.bundleID)")
            if result.windows.isEmpty {
                print("   ⚠️ No windows found.")
            }
            for windowGroup in result.windows {
                let title = windowGroup.window?.resolvedTitle ?? "?"
                print("   🪟 Window: \(title) [\(windowGroup.stableID)]")
                if windowGroup.tabs.isEmpty {
                    print("      ↳ (no Tabs)")
                } else {
                    for tab in windowGroup.tabs {
                        let tabTitle = tab.resolvedTitle ?? tab.title
                        print("      ↳ Tab: \(tabTitle) [\(tab.stableID) -> \(tab.parentTabHost ?? "no parent")]")
                    }
                }
            }
            print("")
        }
    }
}
```

You can also fetch windows for a specific application:

```swift
if let chromeWindows = await PaneKit.shared.windows(forBundleID: "com.google.Chrome") {
    for win in chromeWindows {
        print("Chrome window:", win.title)
    }
}
```

---

## Observing Window Changes

PaneKit can observe and broadcast changes through the built-in `PaneKitNotificationCenter`.

```swift
import PaneKit

PaneKitNotificationCenter.shared.start()

PaneKitNotificationCenter.shared.observe([.titleChanged, .windowMoved, .windowResized]) { window in
    print("🔔 \(window.title) updated — \(window.bounds)")
}
```

Available event types include:
- `windowCreated`
- `windowDestroyed`
- `windowMoved`
- `windowResized`
- `windowMinimized`
- `windowUnminimized`
- `titleChanged`
- `focusedChanged`
- `activated`
- `deactivated`

---

## Configuration Options

When initializing PaneKit, you can customize its behavior:

| Option | Type | Description |
|--------|------|-------------|
| `enableTabs` | `Bool` | Include tab scanning for supported apps |
| `lazyTabs` | `Bool` | Delay tab loading until explicitly requested |
| `enableCache` | `Bool` | Persist windows in local JSON cache for fast restore |

Example:

```swift
await PaneKit.shared.start(enableTabs: true, lazyTabs: false, enableCache: true)
```

---

## API Overview

### Window Access

Each window is represented by a `PaneKitWindow` structure, backed by a low-level `PKWindow` object.

```swift
let window = PaneKitWindow(axElement: axElement)
print(window.stableID)
print(window.title)
print(window.bounds)
print(window.isMinimized)
```

Windows automatically expose real-time data through the `PKWindow` bridge.

---

### Window Actions

PaneKit can also control windows (if permitted):

```swift
try await PaneKit.shared.focus(window)
try await PaneKit.shared.minimize(window)
try await PaneKit.shared.unminimize(window)
try await PaneKit.shared.move(window, to: CGRect(x: 200, y: 100, width: 800, height: 600))
```

---

## Technical Notes

PaneKit uses a hybrid bridge between **Swift** and **Objective-C**, communicating directly with macOS Accessibility and CoreGraphics systems.

Under the hood:
- Window data originates from `AXUIElement` and `CGWindow` sources.  
- `PKWindow.m` integrates private `CGS` symbols for additional window data such as Z-index and layer order.  
- Because of these private calls, **PaneKit is not suitable for App Store distribution**.  

This approach allows PaneKit to extract window information unavailable to pure Accessibility APIs while remaining lightweight and efficient.

---

## License

Licensed under the **Apache License, Version 2.0**.  
See [LICENSE](LICENSE) for full text and [NOTICE](NOTICE) for attribution requirements.

---

© 2025 **Alexander Streb**  
PaneKit integrates code originally inspired by SilicaSwift, with substantial architectural rewrites and redesigns.
