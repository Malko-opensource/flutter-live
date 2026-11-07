import AppKit

// macOS 13 is the deployment target. Keep Tauri's NSWindow class and the
// app's activation policy intact; only the caption window joins other apps.
func configureCaptionOverlay(_ window: NSWindow) {
    precondition(Thread.isMainThread)
    var behavior = window.collectionBehavior
    behavior.subtract([
        .primary, .auxiliary, .moveToActiveSpace,
        .fullScreenPrimary, .fullScreenNone, .fullScreenAllowsTiling
    ])
    behavior.formUnion([
        .canJoinAllSpaces, .canJoinAllApplications,
        .fullScreenAuxiliary, .fullScreenDisallowsTiling
    ])
    window.collectionBehavior = behavior
    window.level = .floating
    window.hidesOnDeactivate = false
}

@_cdecl("fl_overlay_show")
public func showCaptionOverlay(_ rawWindow: UnsafeMutableRawPointer?) {
    precondition(Thread.isMainThread)
    guard let rawWindow else { return }
    let window = Unmanaged<NSWindow>.fromOpaque(rawWindow).takeUnretainedValue()
    configureCaptionOverlay(window)
    // Unlike makeKeyAndOrderFront, this does not steal focus from the presenter.
    window.orderFrontRegardless()
}
