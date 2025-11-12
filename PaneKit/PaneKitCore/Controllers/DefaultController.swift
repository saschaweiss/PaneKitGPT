import ApplicationServices
import Foundation

@MainActor
open class DefaultController {
    public let window: PaneKitWindow

    public required init(window: PaneKitWindow) {
        self.window = window
    }

    open func focus(window: PaneKitWindow) {
        window.pkWindow.focus()
    }

    open func close(window: PaneKitWindow) {
        _ = AXUIElementPerformAction(window.pkWindow.axElement, AXAction.close)
    }

    open func minimize(window: PaneKitWindow) {
        window.pkWindow.minimize()
    }

    open func maximize(window: PaneKitWindow) {
        window.pkWindow.maximize()
    }
    
    open func move(window: PaneKitWindow, point: CGPoint, animated: Bool = false, duration: TimeInterval = 0.25) async {
        if animated {
            await window.animatePosition(to: point, duration: duration)
            return
        }

        var pos = point
        guard let axValue = AXValueCreate(.cgPoint, &pos) else {
            return
        }

        let result = AXUIElementSetAttributeValue(window.pkWindow.axElement, AXAttr.position.raw, axValue)
        if result == .success {
            window.frame.origin = point
        }
    }

    open func resize(window: PaneKitWindow, to size: CGSize, animated: Bool = false, duration: TimeInterval = 0.25) async {
        if animated {
            await window.animateResize(to: size, duration: duration)
            return
        }

        var newSize = size
        guard let axValue = AXValueCreate(.cgSize, &newSize) else {
            return
        }

        let result = AXUIElementSetAttributeValue(window.pkWindow.axElement, AXAttr.size.raw, axValue)
        if result == .success {
            window.frame.size = size
        }
    }

    open func selectTab(at index: Int) async -> Bool {
        return false
    }
    
    open func selectTab(_ axElement: AXUIElement) async -> Bool {
        return false
    }

    open func closeTab(at index: Int) async -> Bool {
        return false
    }
}
