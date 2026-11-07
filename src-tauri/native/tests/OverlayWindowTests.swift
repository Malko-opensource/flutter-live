import AppKit

@main
struct OverlayWindowTests {
    static func main() {
        _ = NSApplication.shared
        let policy = NSApp.activationPolicy()
        let host = NSWindow(contentRect: NSRect(x: 50, y: 100, width: 900, height: 160),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.title = "Caption test"
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 160))
        let child = NSView(frame: content.bounds)
        child.autoresizingMask = [.width, .height]
        content.addSubview(child)
        host.contentView = content
        let controller = CaptionOverlayController(host: host)!
        let panel = controller.panel
        assert((panel as NSWindow) is NSPanel)
        assert(panel.styleMask.contains(.nonactivatingPanel))
        assert(!panel.canBecomeKey && !panel.canBecomeMain)
        assert(panel.becomesKeyOnlyIfNeeded && panel.isFloatingPanel)
        assert(panel.level == .floating && !panel.hidesOnDeactivate)
        assert(!panel.isReleasedWhenClosed)
        assert(panel.contentView === content && content.window === panel)
        assert(host.contentView != nil && host.contentView !== content)
        assert(!host.isVisible && !panel.isVisible)
        assert(NSApp.activationPolicy() == policy, "Do not change app-wide activation")
        let required: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        assert(panel.collectionBehavior.isSuperset(of: required))
        let behavior = panel.collectionBehavior
        configureCaptionOverlay(panel)
        assert(panel.collectionBehavior == behavior)
        let origin = panel.frame.origin
        controller.resize(height: 260)
        assert(panel.frame.height == 260 && panel.frame.origin == origin)
        assert(child.frame.height == 260, "Rehosted content must resize with panel")
        controller.resize(height: 999)
        assert(panel.frame.height == 340)
        controller.resize(height: .nan)
        assert(panel.frame.height == 340)
        controller.resize(height: 1)
        assert(panel.frame.height == 160)
        controller.hide()
        panel.close()
        assert(!panel.isVisible)
        controller.detach()
        controller.detach()
        assert(host.contentView === content && content.window === host)
        assert(panel.contentView == nil)
        showCaptionOverlay(nil)
        hideCaptionOverlay()
        resizeCaptionOverlay(200)
        dragCaptionOverlay()
        destroyCaptionOverlay()
        print("OverlayWindowTests passed: real panel, ownership, resize, detach, null lifecycle")
    }
}
