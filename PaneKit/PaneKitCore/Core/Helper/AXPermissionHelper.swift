import AppKit
import ApplicationServices

enum AXPermissionHelper {
    @MainActor
    static func ensurePermission() {
        guard !AXIsProcessTrusted() else { return }

        let alert = NSAlert()
        alert.messageText = "PaneKit requires accessibility access"
        alert.informativeText = """
        Please allow the app access under:
        System Settings → Security → Privacy → Accessibility.
        """
        alert.addButton(withTitle: "Open settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
