import Cocoa
import FlutterMacOS
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import CoreAudio
import AudioToolbox

class MainFlutterWindow: NSWindow {
  private var desktop: DesktopHost?
  override func awakeFromNib() {
    let controller = FlutterViewController()
    contentViewController = controller
    setContentSize(NSSize(width: 760, height: 780))
    minSize = NSSize(width: 650, height: 680)
    title = "Flutter Live"
    center()
    RegisterGeneratedPlugins(registry: controller)
    desktop = DesktopHost(window: self, messenger: controller.engine.binaryMessenger)
    super.awakeFromNib()
  }
}

/// Platform UI is kept on the main thread. PCM conversion runs on audioQueue.
final class DesktopHost: NSObject, FlutterStreamHandler, SCStreamOutput, SCStreamDelegate {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var sink: FlutterEventSink?
  private let audioQueue = DispatchQueue(label: "dev.flutterlive.capture", qos: .userInitiated)
  private var microphone = AVAudioEngine()
  private var inputUID = ""
  private var activeInputID = AudioDeviceID(0)
  private var microphoneRequested = false
  private var inputObserver: NSObjectProtocol?
  private var routeRestart: DispatchWorkItem?
  private var deviceListener: AudioObjectPropertyListenerBlock?
  private let deviceSelectors: [AudioObjectPropertySelector] = [
    kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
  ]
  private let playback = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
  private var microphoneTap = false
  private var stream: SCStream?
  private var captureGeneration = 0
  // Only accessed on audioQueue.
  private var converter: AVAudioConverter?
  private var converterFormat: AVAudioFormat?
  private var pendingPCM = Data()
  private var conversionGeneration = -1
  // Only accessed on the main thread.
  private var playbackGeneration = 0
  private var scheduledFrames = 0
  private var statusItem: NSStatusItem!
  private var panel: NSPanel?
  private let originalLabel = NSTextField(wrappingLabelWithString: "")
  private let translationLabel = NSTextField(wrappingLabelWithString: "통역할 준비가 됐어요")
  private let dashView = DashSpriteView()
  private let stateLabel = NSTextField(labelWithString: "한국어 ↔ English")
  private var active = false
  private var state = "준비"
  private var pair = "한국어 ↔ English"
  private var pinned = true

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "flutter_live/desktop", binaryMessenger: messenger)
    super.init()
    let events = FlutterEventChannel(name: "flutter_live/audio", binaryMessenger: messenger)
    events.setStreamHandler(self)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    playback.attach(player)
    playback.connect(player, to: playback.mainMixerNode, format: playbackFormat)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Flutter Live")
    rebuildMenu()
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self = self else { return }
      self.channel.invokeMethod("action", arguments: "inputDevicesChanged")
      if self.microphoneRequested {
        let available = self.inputDevices()
        let target = self.inputUID.isEmpty ? self.defaultInput() : AudioDeviceID(
          available.first(where: { $0["uid"] as? String == self.inputUID })?["id"] as? Int ?? 0)
        if target != self.activeInputID { self.scheduleInputRestart() }
      }
    }
    deviceListener = listener
    for selector in deviceSelectors {
      var address = audioAddress(selector)
      AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
  }

  deinit {
    if let observer = inputObserver { NotificationCenter.default.removeObserver(observer) }
    if let listener = deviceListener {
      for selector in deviceSelectors {
        var address = audioAddress(selector)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "inputDevices": result(inputDevices())
    case "selectInputDevice":
      inputUID = call.arguments as? String ?? ""
      result(nil)
    case "startCapture":
      Task { @MainActor in
        do { try await startCapture(source: call.arguments as? String ?? "microphone"); result(nil) }
        catch { result(FlutterError(code: "capture", message: error.localizedDescription, details: nil)) }
      }
    case "stopCapture": stopCapture(); result(nil)
    case "play":
      guard let args = call.arguments as? [String: Any], let bytes = args["bytes"] as? FlutterStandardTypedData,
            let generation = args["generation"] as? Int else { result(false); return }
      do { result(try enqueue(bytes.data, generation: generation)) }
      catch { result(FlutterError(code: "playback", message: "오디오 출력 장치를 확인해 주세요.", details: nil)) }
    case "clearPlayback":
      playbackGeneration = call.arguments as? Int ?? playbackGeneration + 1
      player.stop(); scheduledFrames = 0; result(nil)
    case "volume": player.volume = Float(call.arguments as? Double ?? 0.7); result(nil)
    case "overlay":
      if call.arguments as? Bool == true { showOverlay() } else { panel?.orderOut(nil); dashView.setAnimating(false) }
      result(nil)
    case "hideMain": window?.orderOut(nil); result(nil)
    case "showMain": showMain(); result(nil)
    case "state":
      if let data = call.arguments as? [String: Any] { updateState(data) }
      result(nil)
    case "permissionSettings":
      let pane = call.arguments as? String == "system" ? "Privacy_ScreenCapture" : "Privacy_Microphone"
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  @MainActor private func startCapture(source: String) async throws {
    stopCapture()
    let generation = captureGeneration
    if source == "system" {
      let content: SCShareableContent
      do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
      catch { throw failure("시스템 오디오 접근이 필요해요. 시스템 설정의 화면 및 시스템 오디오 녹음 권한을 허용해 주세요.") }
      guard generation == captureGeneration else { return }
      guard let display = content.displays.first else { throw failure("캡처할 화면을 찾을 수 없어요.") }
      let filter = SCContentFilter(display: display, excludingWindows: [])
      let config = SCStreamConfiguration()
      config.capturesAudio = true
      config.excludesCurrentProcessAudio = true
      config.sampleRate = 48000
      config.channelCount = 1
      config.width = 2; config.height = 2
      config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
      let newStream = SCStream(filter: filter, configuration: config, delegate: self)
      try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
      stream = newStream
      do { try await newStream.startCapture() }
      catch { if stream === newStream { stream = nil }; throw failure("시스템 오디오 캡처를 시작할 수 없어요. 접근 권한을 확인해 주세요.") }
      if generation != captureGeneration { try? await newStream.stopCapture() }
    } else {
      let granted = await AVCaptureDevice.requestAccess(for: .audio)
      guard generation == captureGeneration else { return }
      guard granted else { throw failure("마이크 접근이 필요해요. 시스템 설정의 마이크 권한을 허용해 주세요.") }
      microphoneRequested = true
      do { try startMicrophoneEngine() }
      catch { stopCapture(); throw error }
    }
  }

  private func stopCapture() {
    captureGeneration += 1
    microphoneRequested = false
    routeRestart?.cancel(); routeRestart = nil
    stopMicrophoneEngine()
    if let old = stream { stream = nil; Task { try? await old.stopCapture() } }
  }

  private func audioAddress(_ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private func deviceString(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
    var address = audioAddress(selector)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return value as String
  }

  private func defaultInput() -> AudioDeviceID {
    var address = audioAddress(kAudioHardwarePropertyDefaultInputDevice)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }

  private func inputDevices() -> [[String: Any]] {
    var address = audioAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
    guard status == noErr else { return [] }
    let current = defaultInput()
    return ids.compactMap { id in
      var streams = audioAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
      var bytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
      let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
      defer { storage.deallocate() }
      guard AudioObjectGetPropertyData(id, &streams, 0, nil, &bytes, storage) == noErr else { return nil }
      let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
      guard buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) > 0 else { return nil }
      let uid = deviceString(id, kAudioDevicePropertyDeviceUID)
      guard !uid.isEmpty else { return nil }
      return ["id": Int(id), "uid": uid, "name": deviceString(id, kAudioObjectPropertyName), "isDefault": id == current]
    }
  }

  private func stopMicrophoneEngine() {
    if let observer = inputObserver { NotificationCenter.default.removeObserver(observer); inputObserver = nil }
    microphone.stop()
    if microphoneTap { microphone.inputNode.removeTap(onBus: 0); microphoneTap = false }
  }

  private func startMicrophoneEngine(recreate: Bool = true) throws {
    stopMicrophoneEngine()
    // Recreate I/O after a device/profile change, before reading its new format.
    if recreate { microphone = AVAudioEngine() }
    var device = defaultInput()
    if !inputUID.isEmpty {
      guard let selected = inputDevices().first(where: { $0["uid"] as? String == inputUID }),
            let id = selected["id"] as? Int else {
        throw failure("선택한 마이크의 연결이 끊겼어요. 마이크를 다시 연결하거나 다른 장치를 선택해 주세요.")
      }
      device = AudioDeviceID(id)
    }
    guard device != 0 else { throw failure("연결된 입력 장치가 없어요. 마이크를 연결해 주세요.") }
    let input = microphone.inputNode
    activeInputID = device
    guard let unit = input.audioUnit,
          AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                               &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
      throw failure("선택한 마이크를 열 수 없어요. 장치 연결을 확인해 주세요.")
    }
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0 && format.channelCount > 0 else { throw failure("마이크가 아직 준비되지 않았어요. 잠시 후 다시 시도해 주세요.") }
    let generation = captureGeneration
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self = self, let copy = self.copyBuffer(buffer) else { return }
      self.audioQueue.async { self.convert(copy, generation: generation) }
    }
    microphoneTap = true
    do { try microphone.start() }
    catch { stopMicrophoneEngine(); throw failure("마이크를 시작하지 못했어요. 입력 장치와 권한을 확인해 주세요.") }
    inputObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: microphone, queue: .main) { [weak self] _ in
      guard let self = self, !self.microphone.isRunning else { return }
      self.scheduleInputRestart()
    }
  }

  private func scheduleInputRestart() {
    guard microphoneRequested else { return }
    routeRestart?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.microphoneRequested else { return }
      self.captureGeneration += 1
      do { try self.startMicrophoneEngine(recreate: false) }
      catch {
        self.stopCapture()
        self.channel.invokeMethod("action", arguments: "captureError")
      }
    }
    routeRestart = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .audio, sampleBuffer.isValid,
          let description = CMSampleBufferGetFormatDescription(sampleBuffer),
          let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
          let format = AVAudioFormat(streamDescription: asbd) else { return }
    let count = CMSampleBufferGetNumSamples(sampleBuffer)
    guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
    buffer.frameLength = AVAudioFrameCount(count)
    let code = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
    guard code == noErr else { return }
    // Capture identity is resolved on main, then conversion goes back to its serial queue.
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.stream === stream else { return }
      let generation = self.captureGeneration
      self.audioQueue.async { self.convert(buffer, generation: generation) }
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.stream === stream else { return }
      self.stopCapture()
      self.channel.invokeMethod("action", arguments: "captureError")
    }
  }

  private func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
    copy.frameLength = source.frameLength
    let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
    let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    for i in 0..<src.count {
      if let from = src[i].mData, let to = dst[i].mData { memcpy(to, from, Int(src[i].mDataByteSize)) }
    }
    return copy
  }

  private func convert(_ input: AVAudioPCMBuffer, generation: Int) {
    // Older callbacks can arrive during source switches; never reset state backwards.
    if generation < conversionGeneration { return }
    if generation != conversionGeneration || converterFormat != input.format {
      conversionGeneration = generation
      converterFormat = input.format
      let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
      converter = AVAudioConverter(from: input.format, to: output)
      pendingPCM.removeAll(keepingCapacity: true)
    }
    guard let converter = converter else { return }
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate) + 32)
    guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
    var supplied = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if supplied { status.pointee = .noDataNow; return nil }
      supplied = true; status.pointee = .haveData; return input
    }
    guard error == nil, output.frameLength > 0, let bytes = output.int16ChannelData?[0] else { return }
    pendingPCM.append(Data(bytes: bytes, count: Int(output.frameLength) * 2))
    while pendingPCM.count >= 640 {
      let chunk = Data(pendingPCM.prefix(640))
      pendingPCM.removeFirst(640)
      DispatchQueue.main.async { [weak self] in
        guard let self = self, generation == self.captureGeneration else { return }
        self.sink?(FlutterStandardTypedData(bytes: chunk))
      }
    }
  }

  private func enqueue(_ data: Data, generation: Int) throws -> Bool {
    guard generation == playbackGeneration, !data.isEmpty, data.count % 2 == 0 else { return false }
    let frames = data.count / 2
    guard frames <= 4800, scheduledFrames + frames <= 4800 else { return false }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)),
          let samples = buffer.floatChannelData?[0] else { return false }
    buffer.frameLength = AVAudioFrameCount(frames)
    data.withUnsafeBytes { raw in
      for i in 0..<frames {
        let value = Int16(bitPattern: UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8))
        samples[i] = Float(value) / 32768.0
      }
    }
    if !playback.isRunning { try playback.start() }
    scheduledFrames += frames
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self, self.playbackGeneration == generation else { return }
        self.scheduledFrames = max(0, self.scheduledFrames - frames)
      }
    }
    if !player.isPlaying { player.play() }
    return true
  }

  private func failure(_ message: String) -> NSError {
    NSError(domain: "FlutterLive", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private var previewing = false
  private func updateState(_ data: [String: Any]) {
    let translated = data["translation"] as? String ?? ""
    let original = data["original"] as? String ?? ""
    state = data["status"] as? String ?? ""
    pair = data["pair"] as? String ?? ""
    active = data["active"] as? Bool ?? false
    translationLabel.stringValue = translated.isEmpty ? state : translated
    originalLabel.stringValue = original
    let preview = data["preview"] as? Bool ?? false
    previewing = preview
    dashView.setClip(data["mascot"] as? String ?? "idle", skin: data["mascotSkin"] as? String ?? "hanbok")
    dashView.setAnimating(panel?.isVisible == true && (active || preview))
    stateLabel.stringValue = preview ? "디자인 미리보기 · 실제 통역 아님" : "\(pair)  ·  \(state)"
    statusItem.button?.toolTip = "Flutter Live · \(state)"
    rebuildMenu()
  }

  private func rebuildMenu() {
    let menu = NSMenu()
    let heading = NSMenuItem(title: "Flutter Live · \(active ? "통역 중" : "준비")", action: nil, keyEquivalent: "")
    menu.addItem(heading)
    menu.addItem(NSMenuItem(title: pair, action: nil, keyEquivalent: ""))
    menu.addItem(.separator())
    for (title, selector) in [
      ("대화 화면 열기", #selector(showMain)),
      ("자막 오버레이 표시", #selector(overlayAction)),
      (active ? "일시 정지" : "통역 시작 / 재개", #selector(toggle)),
      ("통역 종료", #selector(stopAction)),
      ("앱 종료", #selector(quit))
    ] {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self; menu.addItem(item)
    }
    statusItem.menu = menu
  }
  @objc private func showMain() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
  @objc private func toggle() { channel.invokeMethod("action", arguments: "toggle") }
  @objc private func stopAction() { channel.invokeMethod("action", arguments: "stop") }
  @objc private func overlayAction() { channel.invokeMethod("action", arguments: "overlay") }
  @objc private func quit() { stopCapture(); player.stop(); playback.stop(); NSApp.terminate(nil) }
  @objc private func closeOverlay() { panel?.orderOut(nil); dashView.setAnimating(false); channel.invokeMethod("action", arguments: "overlayClosed") }
  @objc private func togglePin(_ sender: NSButton) {
    pinned.toggle(); panel?.level = pinned ? .floating : .normal
    sender.contentTintColor = pinned ? .systemBlue : .white
    sender.toolTip = pinned ? "항상 위 해제" : "항상 위에 표시"
  }

  private func showOverlay() {
    if panel == nil { makeOverlay() }
    panel?.orderFrontRegardless(); dashView.setAnimating(active || previewing)
  }
  private func makeOverlay() {
    let screen = window?.screen ?? NSScreen.main!
    let width = min(980, screen.visibleFrame.width - 48)
    let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 38, width: width, height: 174)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isFloatingPanel = true; panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
    panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    let surface = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
    surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
    surface.appearance = NSAppearance(named: .darkAqua)
    surface.wantsLayer = true; surface.layer?.cornerRadius = 20; surface.layer?.masksToBounds = true
    panel.contentView = surface
    let image = dashView
    image.setAccessibilityRole(.image)
    translationLabel.font = .systemFont(ofSize: 25, weight: .semibold)
    translationLabel.textColor = .white; translationLabel.maximumNumberOfLines = 2
    translationLabel.lineBreakMode = .byTruncatingTail
    originalLabel.font = .systemFont(ofSize: 15); originalLabel.textColor = NSColor(white: 0.82, alpha: 1)
    originalLabel.maximumNumberOfLines = 2; originalLabel.lineBreakMode = .byTruncatingTail
    stateLabel.font = .systemFont(ofSize: 11); stateLabel.textColor = NSColor(white: 0.72, alpha: 1)
    stateLabel.lineBreakMode = .byTruncatingTail
    let text = NSStackView(views: [stateLabel, translationLabel, originalLabel])
    text.orientation = .vertical; text.alignment = .leading; text.spacing = 8
    let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "자막 닫기")!, target: self, action: #selector(closeOverlay))
    let pin = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "항상 위")!, target: self, action: #selector(togglePin(_:)))
    let settings = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "메인 창 열기")!, target: self, action: #selector(showMain))
    for button in [close, pin, settings] { button.isBordered = false; button.contentTintColor = .white }
    pin.contentTintColor = .systemBlue
    let buttons = NSStackView(views: [pin, settings, close]); buttons.spacing = 12
    for view in [image, text, buttons] { view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view) }
    NSLayoutConstraint.activate([
      image.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
      image.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
      image.widthAnchor.constraint(equalToConstant: 136), image.heightAnchor.constraint(equalToConstant: 156),
      text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
      text.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -22),
      text.centerYAnchor.constraint(equalTo: surface.centerYAnchor, constant: 5),
      stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -12),
      buttons.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
      buttons.topAnchor.constraint(equalTo: surface.topAnchor, constant: 12),
    ])
    self.panel = panel
  }
}


/// Uses the same transparent Blender atlas as Flutter. No 3D engine needed in the panel.
private final class DashSpriteView: NSView {
  private var atlas: NSImage?
  private var clip = ""
  private var frameIndex = 0
  private var timer: Timer?
  override init(frame: NSRect) { super.init(frame: frame); setClip("idle") }
  required init?(coder: NSCoder) { super.init(coder: coder); setClip("idle") }
  convenience init() { self.init(frame: .zero) }
  func setClip(_ value: String, skin: String = "hanbok") {
    let allowed = ["idle", "listen", "speak", "wave", "celebrate", "reconnect", "sing", "megaphone"]
    let name = allowed.contains(value) ? value : "idle"
    let outfit = ["hanbok", "gat", "dancheong"].contains(skin) ? skin : "hanbok"
    let key = "\(outfit)/\(name)"
    guard key != clip else { return }
    clip = key; frameIndex = 0
    let labels = ["hanbok": "한복", "gat": "갓과 두루마기", "dancheong": "단청 무대"]
    setAccessibilityLabel("\(labels[outfit]!) 의상을 입은 2D Flutter Dash")
    if let frameworks = Bundle.main.privateFrameworksURL {
      atlas = NSImage(contentsOf: frameworks.appendingPathComponent("App.framework/Resources/flutter_assets/assets/dash/\(key).png"))
    }
    needsDisplay = true
  }
  func setAnimating(_ enabled: Bool) {
    guard enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      timer?.invalidate(); timer = nil; frameIndex = 0; needsDisplay = true; return
    }
    guard timer == nil else { return }
    let next = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.setAnimating(false); return }
      self.frameIndex = (self.frameIndex + 1) % 24; self.needsDisplay = true
    }
    timer = next; RunLoop.main.add(next, forMode: .common)
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let atlas else { return }
    let tile = atlas.size.width / 6
    let source = NSRect(x: CGFloat(frameIndex % 6) * tile, y: CGFloat(3 - frameIndex / 6) * tile, width: tile, height: tile)
    let side = min(bounds.width, bounds.height)
    let target = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    atlas.draw(in: target, from: source, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
  }
  deinit { timer?.invalidate() }
}
