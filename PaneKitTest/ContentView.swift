import SwiftUI
import PaneKitCore

@main
struct ContentView: App {
    
    /*
    @State private var paneKit = PaneKit(notifyOnMainThread: true, enableLogging: true, includingTabs: true)
    @State private var windows: [PaneKitWindow] = []
    @State private var isLoading = false
    @State private var showTabs = true
    @StateObject private var cacheModel = PaneKitCacheModel()
    
    init() {
        Task {
            await setupPaneKit()
        }
    }
    
    private func setupPaneKit() async {
        await PaneKitCore.shared.start()

        let allWindows = await PaneKitCache.shared.allWindows()
        await MainActor.run {
            cacheModel.windows = allWindows
            print("✅ PaneKit initialized with \(allWindows.count) windows.")
        }

        await PaneKitEventCenter.shared.subscribe(event: "focusChange") { event in
            guard let id = event.windowID else { return }
            guard let win = await PaneKitCache.shared.window(forStableID: id) else { return }
            print("🎯 Global Focus change: \(win.appName) – \(win.title)")
        }

        await PaneKitEventCenter.shared.subscribe(event: "close") { event in
            guard let id = event.windowID else { return }
            guard let win = await PaneKitCache.shared.window(forStableID: id) else { return }
            print("🧹 Window closed: \(win.appName)")
        }

        for window in allWindows {
            await Self.registerWindowEvents(for: window)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainContentView(cacheModel: cacheModel, isLoading: $isLoading, showTabs: $showTabs)
        }
    }
     */
}

extension ContentView {
    static func registerWindowEvents(for window: PaneKitWindow) async {
        await window.onEvent("focus") { snapshot in
            await MainActor.run {
                print("⭐ Window focused: \(snapshot.title)")
            }
        }

        await window.onEvent("minimize") { snapshot in
            await MainActor.run {
                print("💤 Window minimized: \(snapshot.title)")
            }
        }

        await window.onEvent("close") { snapshot in
            await MainActor.run {
                print("🧹 Window closed: \(snapshot.title)")
            }
        }
    }

    static func registerTabEvents(for tab: PaneKitWindow) async {
        await tab.onEvent("focus") { tab in
            await MainActor.run {
                print("📑 Tab focused: \(tab.title)")
            }
        }

        await tab.onEvent("titleChanged") { changedTab in
            await MainActor.run {
                print("📝 Tab title changed: \(changedTab.title)")
            }
        }
    }
}

struct MainContentView: View {
    @ObservedObject var cacheModel: PaneKitCacheModel
    @Binding var isLoading: Bool
    @Binding var showTabs: Bool
    
    private var windows: [PaneKitWindow] {
        cacheModel.windows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()

            if isLoading {
                ProgressView("Loading windows…").padding(.top, 20)
            } else if windows.isEmpty {
                Text("No windows found.").foregroundStyle(.secondary).padding(.top, 30)
            } else {
                tableSection
            }

            Spacer()
        }
        .padding(20)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .paneKitCacheDidUpdate) {
                let windows = await PaneKitCache.shared.allWindows()
                await MainActor.run {
                    cacheModel.updateWindows(windows)
                }
            }
        }
    }
    
    private func initialLoad() async {
        isLoading = true
        defer { isLoading = false }

        //let cached = await PaneKitCache.shared.allWindows(includeTabs: true)

        await MainActor.run {
            //cacheModel.windows = cached
            //print("🪟 Loaded \(cached.count) windows from cache (including tabs).")
        }

        //await PaneKitCache.shared.debugDumpWindows()
    }

    private var headerSection: some View {
        HStack {
            Text("PaneKit Window overview").font(.title2).fontWeight(.semibold)
            Spacer()
            
            //Button { Task { await refreshCache() } } label: { Label("Reload", systemImage: "arrow.clockwise") }.disabled(isLoading)

            //Button { Task { await clearCache() } } label: { Label("Clear", systemImage: "trash") }

            Toggle("Show tabs", isOn: $showTabs).toggleStyle(.switch).frame(width: 150)
        }
    }

    private var tableSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groupedWindows, id: \.screenName) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🖥 \(group.screenName)").font(.headline).padding(.bottom, 4)

                        ForEach(group.windows, id: \.stableID) { win in
                            windowRow(for: win)

                            Divider()
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 4)
        }
    }
    
    private var groupedWindows: [(screenName: String, windows: [PaneKitWindow])] {
        let all = cacheModel.windows

        let mainWindows = all.filter { $0.windowType == .window }

        let tabsByHost: [String: [PaneKitWindow]] = Dictionary(
            grouping: all.filter { $0.windowType == .tab },
            by: { $0.pkWindow.parentTabHost }
        )

        let groups = Dictionary(grouping: mainWindows) { win in
            win.screen?.localizedName ?? "Unknown Screen"
        }

        let result: [(String, [PaneKitWindow])] = groups.map { (screenName, windows) in
            let sortedWindows = windows.sorted {
                $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }

            let enriched: [PaneKitWindow] = sortedWindows.map { win in
                let copy = win
                copy.tabs = tabsByHost[win.stableID] ?? []
                return copy
            }

            return (screenName, enriched)
        }
        
        return result.sorted {
            $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }
    
    private var allDisplayWindows: [PaneKitWindow] {
        let mainWindows = cacheModel.windows.filter { $0.windowType != .tab }

        if showTabs {
            return mainWindows
        } else {
            return mainWindows
        }
    }
    
    @ViewBuilder
    private func windowRow(for win: PaneKitWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(win.appName).font(.headline)
                Spacer()
                Text("PID: \(win.pid)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("🪟 \(win.title)")
                Text(win.isVisible ? "👁 sichtbar" : "🚫 versteckt")
                Text(win.isMinimized ? "💤 minimiert" : "🟢 aktiv")
                if win.isFocused { Text("⭐ Fokus") }
            }
            .font(.caption).foregroundStyle(.secondary)

            Text("📐 \(Int(win.frame.origin.x)), \(Int(win.frame.origin.y)) – \(Int(win.frame.size.width))×\(Int(win.frame.size.height))").font(.caption2).foregroundStyle(.gray)

            if let tabs = win.tabs, !tabs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tabs, id: \.stableID) { tab in
                        HStack {
                            Text("↳ \(tab.title)").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if tab.isFocused {
                                Image(systemName: "star.fill").font(.caption2)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func refreshCache() async {
        isLoading = true
        defer { isLoading = false }

        //await PaneKitCache.shared.refreshAllWindows()
        print("🔄 Cache refreshed (triggered manually)")
    }

    private func clearCache() async {
        //await PaneKitCache.shared.clear()
        print("🧹 Cache cleared")
    }
}
