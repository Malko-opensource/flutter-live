# macOS fullscreen caption overlay

The caption window uses public AppKit collection behaviors available on the app's macOS 13 minimum target:

- `canJoinAllSpaces` and `canJoinAllApplications` let a floating window join other applications' fullscreen Spaces.
- `fullScreenAuxiliary` allows the caption to accompany fullscreen content. Conflicting primary/none/tiling flags are removed.
- The window remains at floating level and does not hide when the app deactivates.
- It is created hidden and unfocused, then configured and ordered on the AppKit main thread with `orderFrontRegardless`. Showing captions does not intentionally activate the app or make the caption the key window.

The implementation preserves Tauri's native window class and the application's normal activation policy. No NSPanel class replacement, private AppKit API, accessibility permission, or system security change is required. Main-window activation remains intentional when the user presses “메인 창 열기”.

## Native regression test

From the repository root on a Mac with Xcode installed:

```sh
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  src-tauri/native/OverlayWindow.swift \
  src-tauri/native/tests/OverlayWindowTests.swift \
  -o /tmp/flutter-overlay-window-tests
/tmp/flutter-overlay-window-tests
```

This exercises real AppKit window configuration, conflicting flag removal, floating level, inactive visibility, repeat configuration, and a null C-bridge argument. It does not open the test window or capture audio. Run the normal frontend checks and `npm run tauri -- build --debug` separately.

## Manual fullscreen check

1. Open the built app, select subtitle overlay mode, and start **디자인 미리보기**. No credentials or audio are required.
2. Show the caption and hide the main window.
3. In a separate Chrome window showing `about:blank`, enter macOS native fullscreen with Control-Command-F.
4. Confirm the caption remains visibly above Chrome, Chrome retains keyboard focus, and no desktop switch occurs.
5. Exit/re-enter fullscreen, hide/reopen the caption, and verify main-window return and quit.
6. Close only the temporary Chrome window and stop the preview.

On macOS 26.3.1 arm64, the debug bundle and native test passed. CUA exercised preview, show/hide/reopen, main-window return, Chrome native fullscreen entry/exit, and app quit. Its screenshots captured Chrome and the caption separately; this does **not** conclusively establish their composited z-order or focus retention. Those two checks remain a visual validation item. Chrome's original remote-desktop tab was left intact and the QA window was closed. No live translation/audio test was performed. Older supported macOS versions and multiple-display Spaces are not yet tested.


The final v0.2.2 Release bundle was also launched after ad-hoc signing. Offline preview, caption show/main hide, main return, caption hide/reopen, preview stop, and app quit passed. No credentials or audio were used. Chrome fullscreen was not repeated for that final bundle; the cross-app compositing and keyboard-focus limitations above still apply.
