@MainActor
final class com_microsoft_edgemac_AppCollector: ChromiumCollectorBase, @unchecked Sendable {
    override class var chromiumBundleID: String { "com.microsoft.edgemac" }

    override class func resolveTabTitle(for tabElement: AXUIElement) -> String {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(tabElement, AXAttr.title, &value) == .success, let title = value as? String, !title.isEmpty {
            return title
        }
        return super.resolveTabTitle(for: tabElement)
    }
}
