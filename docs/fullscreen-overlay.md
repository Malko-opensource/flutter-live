# macOS fullscreen caption overlay

## v0.2.3 fix

v0.2.2 only changed collection behaviors on Tauri's ordinary NSWindow. A user confirmed that this did not keep captions above Chrome fullscreen. The previous per-window screenshots were not proof of composited visibility.

The caption now lives in a real AppKit `NSPanel`, created with `nonactivatingPanel` from the start. Its floating level, `canJoinAllSpaces`, `canJoinAllApplications` and `fullScreenAuxiliary` behaviors allow it to accompany other apps' fullscreen Spaces. It does not become the key or main window, hide on deactivation, or intentionally activate Flutter Live. The app's normal activation policy remains unchanged.

The existing Tauri content view moves into the panel, retaining the same webview and event label. The original hidden host keeps a placeholder view because Tao's window callbacks require one. No Objective-C runtime class replacement is used. Hide, resize and drag commands operate on the panel, and closing it hides rather than destroys it. First mouse events are accepted while Chrome is active. The caption starts near the screen's lower edge; edge resizing and content sizing are preserved.

No separate overlay permission, accessibility grant, or OS security setting change is required by this implementation. Microphone/system-audio permissions remain separate audio features. The main window's explicit “메인 창 열기” action still intentionally activates Flutter Live.

Apple references:
- [Nonactivating panel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [Joining other applications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [How panels work](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/WinPanel/Concepts/UsingPanels.html)

## Regression tests

```sh
npm test
npm run check
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  src-tauri/native/OverlayWindow.swift \
  src-tauri/native/tests/OverlayWindowTests.swift \
  -o /tmp/flutter-overlay-window-tests
/tmp/flutter-overlay-window-tests
npm run tauri -- build
```

The native test checks actual NSPanel type/style, non-key behavior, collection flags, content ownership, non-nil host placeholder, resizing, initial placement, detach restoration and null lifecycle calls. It does not replace visual WKWebView or fullscreen testing.

## Visual verification

On macOS 26.3.1 arm64, the Debug implementation displayed preview captions above Google Slides' actual slideshow fullscreen in Chrome. This was verified with a macOS whole-screen capture opened in Preview, rather than separate captures of Chrome and Flutter Live. Google's [public sample presentation](https://docs.google.com/presentation/d/1EAYk18WDjIG-zp_0vLm3CsfQh_i8eXc67Jo2O9C6Vuc/edit), linked from its [Slides API quickstart](https://developers.google.com/workspace/slides/api/quickstart/javascript), was used without editing or publishing any slides.

Final v0.2.3 Release verification is recorded in the release notes. Live Gemini translation/audio, older macOS versions, multiple displays/Spaces and prolonged presentation sessions remain outside this fullscreen check. macOS 13 cannot disable hidden webview background throttling; keep the main window visible there.

To repeat without credentials or audio: select subtitle mode, start **디자인 미리보기**, show the caption and hide the main window, then start Google Slides' slideshow in Chrome. Check caption visibility, slide navigation, caption close/reopen, main-window return and app quit. Showing the main window intentionally returns focus to Flutter Live.
