import AppKit

// A real nonactivating panel is eligible to accompany other applications'
// fullscreen Spaces. NSWindow collection flags alone do not provide this.
final class CaptionPanel: NSPanel {
    private var mouseDownEvent: NSEvent?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { mouseDownEvent = event }
        super.sendEvent(event)
    }

    func beginCaptionDrag() {
        // Webview IPC runs after the original event dispatch. Retain the actual
        // native mouse-down rather than relying on NSApp.currentEvent.
        guard NSEvent.pressedMouseButtons & 1 != 0, let event = mouseDownEvent else { return }
        performDrag(with: event)
    }

    override func close() { orderOut(nil) }
}

func configureCaptionOverlay(_ panel: NSPanel) {
    precondition(Thread.isMainThread)
    panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications,
                                .fullScreenAuxiliary, .fullScreenDisallowsTiling]
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
}

final class CaptionOverlayController {
    let host: NSWindow
    let panel: CaptionPanel
    private let hostedContent: NSView
    private var detached = false

    init?(host: NSWindow) {
        precondition(Thread.isMainThread)
        guard let content = host.contentView else { return nil }
        self.host = host
        hostedContent = content
        var frame = host.frame
        if let screen = host.screen ?? NSScreen.main {
            frame.origin.x = screen.visibleFrame.midX - frame.width / 2
            frame.origin.y = screen.visibleFrame.minY + 50
        }
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if host.styleMask.contains(.resizable) { style.insert(.resizable) }
        panel = CaptionPanel(contentRect: frame, styleMask: style,
                             backing: .buffered, defer: false)
        panel.title = host.title
        panel.minSize = host.minSize
        configureCaptionOverlay(panel)
        host.orderOut(nil)
        // Tao's delegate and raw-window handle expect a non-nil contentView.
        // Keep its window and delegate intact, with a harmless placeholder.
        host.contentView = NSView(frame: content.frame)
        panel.contentView = content
        content.setFrameSize(panel.contentLayoutRect.size)
    }

    func show() {
        precondition(Thread.isMainThread)
        guard !detached else { return }
        host.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func resize(height: Double) {
        guard height.isFinite, !detached else { return }
        var frame = panel.frame
        // AppKit uses a bottom-left origin. Keep the caption's lower edge fixed.
        frame.size.height = min(340, max(160, height))
        if let screen = panel.screen {
            frame.origin.y = max(screen.visibleFrame.minY,
                                 min(frame.origin.y, screen.visibleFrame.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)
    }

    func detach() {
        guard !detached else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        host.contentView = hostedContent
        detached = true
    }
}

// The Tauri host retains its webview and event label; the controller retains the
// real panel and moved content for the same lifetime. No Objective-C class swap
// or application-wide accessory activation policy is used.
private var captionOverlay: CaptionOverlayController?

@_cdecl("fl_overlay_show")
public func showCaptionOverlay(_ rawWindow: UnsafeMutableRawPointer?) {
    precondition(Thread.isMainThread)
    guard let rawWindow else { return }
    let host = Unmanaged<NSWindow>.fromOpaque(rawWindow).takeUnretainedValue()
    if captionOverlay?.host !== host {
        captionOverlay?.detach()
        captionOverlay = CaptionOverlayController(host: host)
    }
    captionOverlay?.show()
}

@_cdecl("fl_overlay_hide")
public func hideCaptionOverlay() {
    precondition(Thread.isMainThread)
    captionOverlay?.hide()
}

@_cdecl("fl_overlay_resize")
public func resizeCaptionOverlay(_ height: Double) {
    precondition(Thread.isMainThread)
    captionOverlay?.resize(height: height)
}

@_cdecl("fl_overlay_drag")
public func dragCaptionOverlay() {
    precondition(Thread.isMainThread)
    captionOverlay?.panel.beginCaptionDrag()
}

@_cdecl("fl_overlay_destroy")
public func destroyCaptionOverlay() {
    precondition(Thread.isMainThread)
    captionOverlay?.detach()
    captionOverlay = nil
}
