import SwiftUI
import PaneKitCore
import Combine

@main
struct PaneKitApp: App {
    @StateObject private var windowManager = WindowManager()
    
    init() {
        // ✅ Console-Spam beheben
        PaneKitEventManager.shared.setLogLevel(.minimal)
    }
 
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
                .task {
                    await windowManager.initialize()
                }
        }
    }
}

// ✅ Window Manager für State-Management
@MainActor
class WindowManager: ObservableObject {
    @Published var windows: [PaneKitWindow] = []
    @Published var isLoading = false
    private var hasInitialized = false
    
    func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        isLoading = true
        defer { isLoading = false }
        
        // PaneKit starten
        await PaneKitManager.shared.start(includingTabs: true)
        
        // Initiale Fenster laden
        await refreshWindows()
        
        // Auf Cache-Updates lauschen
        Task {
            for await _ in NotificationCenter.default.notifications(named: .paneKitCacheDidUpdate) {
                await refreshWindows()
            }
        }
    }
    
    func refreshWindows() async {
        let allWindows = PaneKitCache.shared.all()
        await MainActor.run {
            self.windows = allWindows
            print("📊 Windows updated: \(allWindows.count) total")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var showTabs = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("PaneKit Window Overview")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Toggle("Show Tabs", isOn: $showTabs)
                    .toggleStyle(.switch)
                    .frame(width: 150)
                
                Button {
                    Task { await windowManager.refreshWindows() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(windowManager.isLoading)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            // Content
            if windowManager.isLoading {
                VStack {
                    ProgressView("Loading windows...")
                    Text("Please wait...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windowManager.windows.isEmpty {
                VStack {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No windows found")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Make sure you've granted Accessibility permissions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WindowListView(
                    windows: windowManager.windows,
                    showTabs: showTabs
                )
            }
            
            // Footer Stats
            Divider()
            HStack {
                Label("\(windowCount) Windows", systemImage: "rectangle")
                if showTabs {
                    Label("\(tabCount) Tabs", systemImage: "square.stack")
                }
                Spacer()
                Text("Last updated: \(Date(), style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private var windowCount: Int {
        windowManager.windows.filter { $0.windowType == .window }.count
    }
    
    private var tabCount: Int {
        windowManager.windows.filter { $0.windowType == .tab }.count
    }
}

struct WindowListView: View {
    let windows: [PaneKitWindow]
    let showTabs: Bool
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupedWindows, id: \.screenName) { group in
                    ScreenGroupView(
                        screenName: group.screenName,
                        windows: group.windows,
                        showTabs: showTabs
                    )
                }
            }
            .padding()
        }
    }
    
    private var groupedWindows: [(screenName: String, windows: [PaneKitWindow])] {
        // Nur Haupt-Fenster
        let mainWindows = windows.filter { $0.windowType == .window }
        
        // Tabs nach Parent gruppieren
        let tabsByParent: [String: [PaneKitWindow]] = Dictionary(
            grouping: windows.filter { $0.windowType == .tab },
            by: { $0.parentID ?? "" }
        )
        
        // Nach Screen gruppieren
        let grouped = Dictionary(grouping: mainWindows) { win in
            win.screen?.localizedName ?? "Unknown Screen"
        }
        
        // Windows mit ihren Tabs verbinden
        let result: [(String, [PaneKitWindow])] = grouped.map { (screenName, wins) in
            let sortedWindows = wins.sorted {
                $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
            
            // Tabs zu jedem Window hinzufügen
            let enriched: [PaneKitWindow] = sortedWindows.map { win in
                let copy = win
                copy.tabs = tabsByParent[win.stableID] ?? []
                return copy
            }
            
            return (screenName, enriched)
        }
        
        return result.sorted {
            $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }
}

struct ScreenGroupView: View {
    let screenName: String
    let windows: [PaneKitWindow]
    let showTabs: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Screen Header
            HStack {
                Image(systemName: "display")
                Text(screenName)
                    .font(.headline)
                Spacer()
                Text("\(windows.count) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            // Windows
            ForEach(windows, id: \.stableID) { window in
                WindowRowView(window: window, showTabs: showTabs)
                
                if window.stableID != windows.last?.stableID {
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WindowRowView: View {
    let window: PaneKitWindow
    let showTabs: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // App Name & PID
            HStack {
                Text(window.appName)
                    .font(.headline)
                
                if window.isFocused {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                
                Spacer()
                
                Text("PID: \(window.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.quaternaryLabelColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            // Title & Status
            HStack(spacing: 8) {
                Image(systemName: "rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(window.title)
                    .font(.body)
                    .lineLimit(1)
                
                Spacer()
                
                // Status Badges
                HStack(spacing: 6) {
                    if window.isVisible {
                        StatusBadge(icon: "eye", color: .green)
                    } else {
                        StatusBadge(icon: "eye.slash", color: .gray)
                    }
                    
                    if window.isMinimized {
                        StatusBadge(icon: "minus.circle", color: .orange)
                    }
                    
                    if window.isFullscreen {
                        StatusBadge(icon: "arrow.up.left.and.arrow.down.right", color: .blue)
                    }
                }
            }
            
            // Frame Info
            HStack(spacing: 12) {
                Label(
                    "x:\(Int(window.frame.origin.x)) y:\(Int(window.frame.origin.y))",
                    systemImage: "location"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                
                Label(
                    "\(Int(window.frame.width))×\(Int(window.frame.height))",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                
                if window.zIndex >= 0 {
                    Label("z:\(window.zIndex)", systemImage: "square.stack")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Tabs
            if showTabs, let tabs = window.tabs, !tabs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 4)
                    
                    ForEach(tabs, id: \.stableID) { tab in
                        TabRowView(tab: tab)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TabRowView: View {
    let tab: PaneKitWindow
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Image(systemName: "square.on.square")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
            
            Spacer()
            
            if tab.isFocused {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let icon: String
    let color: Color
    
    var body: some View {
        Image(systemName: icon)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(4)
            .background(color.opacity(0.15))
            .clipShape(Circle())
    }
}

// ✅ Notification Extension
extension Notification.Name {
    static let paneKitCacheDidUpdate = Notification.Name("PaneKitCacheDidUpdate")
}

#Preview {
    ContentView()
        .environmentObject(WindowManager())
}
