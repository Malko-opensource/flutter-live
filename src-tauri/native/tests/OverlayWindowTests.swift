import AppKit

@main
struct OverlayWindowTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.collectionBehavior = [.primary, .fullScreenPrimary, .fullScreenAllowsTiling, .moveToActiveSpace]
        configureCaptionOverlay(window)
        let required: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        assert(window.collectionBehavior.isSuperset(of: required))
        let excluded: NSWindow.CollectionBehavior = [.primary, .auxiliary, .fullScreenPrimary, .fullScreenNone, .fullScreenAllowsTiling, .moveToActiveSpace]
        assert(window.collectionBehavior.intersection(excluded).isEmpty)
        assert(window.level == .floating)
        assert(!window.hidesOnDeactivate)
        assert(!window.isVisible, "Configuration must not show or focus the window")
        let behavior = window.collectionBehavior
        configureCaptionOverlay(window)
        assert(window.collectionBehavior == behavior, "Repeated show must remain idempotent")
        showCaptionOverlay(nil)
        print("OverlayWindowTests passed")
    }
}
