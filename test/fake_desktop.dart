import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_live/src/platform/desktop_bridge.dart';

class FakeDesktop extends DesktopBridge {
  final input = StreamController<Uint8List>.broadcast();
  final played = <Uint8List>[];
  final cleared = <int>[];
  Map<String, Object>? lastState;
  String selectedUID = '';
  List<InputDevice> devices = [
    const InputDevice(
      uid: 'test-bt',
      name: 'Bluetooth microphone',
      isDefault: true,
    ),
    const InputDevice(uid: 'test-usb', name: 'USB microphone'),
  ];
  @override
  Future<List<InputDevice>> inputDevices() async => devices;
  @override
  Future<void> selectInputDevice(String uid) async {
    selectedUID = uid;
  }

  bool capturing = false;
  bool overlayShown = false;
  @override
  Stream<Uint8List> get audio => input.stream;
  @override
  void onAction(void Function(String) callback) {}
  @override
  Future<void> startCapture(String source) async {
    capturing = true;
  }

  @override
  Future<void> stopCapture() async {
    capturing = false;
  }

  @override
  Future<bool> play(Uint8List bytes, int generation) async {
    played.add(bytes);
    return true;
  }

  @override
  Future<void> clearPlayback(int generation) async {
    cleared.add(generation);
  }

  @override
  Future<void> volume(double value) async {}
  @override
  Future<void> overlay(bool visible) async {
    overlayShown = visible;
  }

  @override
  Future<void> showMain() async {}
  @override
  Future<void> hideMain() async {}
  @override
  Future<void> update(Map<String, Object> state) async {
    lastState = Map.of(state);
  }

  @override
  Future<void> openPermissionSettings(String permission) async {}
  @override
  void dispose() {
    unawaited(input.close());
  }
}
