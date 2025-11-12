import Foundation
import ApplicationServices

@MainActor
enum AppControllerFactory {
    public static func controller(for window: PaneKitWindow) -> DefaultController {
        let bundleID = window.bundleID
        let sanitizedName = sanitizeBundleID(bundleID)
        let specificClassName = "PaneKit.\(sanitizedName)_WindowController"
        
        if let controllerType = NSClassFromString(specificClassName) as? DefaultController.Type {
            return controllerType.init(window: window)
        }

        if isJetBrainsApp(bundleID),
           let jetBrainsType = NSClassFromString("PaneKit.JetBrainsWindowController") as? DefaultController.Type {
            return jetBrainsType.init(window: window)
        }

        if isChromiumApp(bundleID),
           let chromiumType = NSClassFromString("PaneKit.ChromiumWindowController") as? DefaultController.Type {
            return chromiumType.init(window: window)
        }

        return DefaultController(window: window)
    }

    private static func sanitizeBundleID(_ bundleID: String) -> String {
        return bundleID.replacingOccurrences(of: ".", with: "_").lowercased()
    }

    private static func isJetBrainsApp(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.jetbrains.") || bundleID.hasPrefix("org.jetbrains.")
    }

    private static func isChromiumApp(_ bundleID: String) -> Bool {
        let chromiumFragments = ["chrome", "brave", "opera", "vivaldi", "edgemac"]
        return chromiumFragments.contains { bundleID.lowercased().contains($0) }
    }
}

@MainActor
public final class PaneKitControllerResolver {
    public static let shared = PaneKitControllerResolver()
    private var controllers: [String: DefaultController.Type] = [:]

    private init() {}

    public func register(bundleID: String, controller: DefaultController.Type) {
        controllers[bundleID] = controller
    }

    public func controller(for window: PaneKitWindow) -> DefaultController? {
        let bundle = window.bundleID
        if let type = controllers[bundle] {
            return type.init(window: window)
        }
        return DefaultController(window: window)
    }
}
