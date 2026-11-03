import 'package:flutter/services.dart';

class InputDevice {
  const InputDevice({
    required this.uid,
    required this.name,
    this.isDefault = false,
  });
  final String uid, name;
  final bool isDefault;
}

class DesktopBridge {
  static const channel = MethodChannel('flutter_live/desktop');
  static const audioChannel = EventChannel('flutter_live/audio');
  Stream<Uint8List> get audio =>
      audioChannel.receiveBroadcastStream().cast<Uint8List>();
  void onAction(void Function(String action) callback) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'action') callback(call.arguments as String);
    });
  }

  Future<List<InputDevice>> inputDevices() async {
    final devices =
        await channel.invokeListMethod<dynamic>('inputDevices') ?? [];
    return devices
        .map(
          (d) => InputDevice(
            uid: d['uid'] as String,
            name: d['name'] as String,
            isDefault: d['isDefault'] == true,
          ),
        )
        .toList();
  }

  Future<void> selectInputDevice(String uid) =>
      channel.invokeMethod('selectInputDevice', uid);

  Future<void> startCapture(String source) =>
      channel.invokeMethod('startCapture', source);
  Future<void> stopCapture() => channel.invokeMethod('stopCapture');
  Future<bool> play(Uint8List bytes, int generation) async =>
      await channel.invokeMethod<bool>('play', {
        'bytes': bytes,
        'generation': generation,
      }) ??
      false;
  Future<void> clearPlayback(int generation) =>
      channel.invokeMethod('clearPlayback', generation);
  Future<void> volume(double value) => channel.invokeMethod('volume', value);
  Future<void> overlay(bool visible) =>
      channel.invokeMethod('overlay', visible);
  Future<void> showMain() => channel.invokeMethod('showMain');
  Future<void> hideMain() => channel.invokeMethod('hideMain');
  Future<void> update(Map<String, Object> state) =>
      channel.invokeMethod('state', state);
  Future<void> openPermissionSettings(String permission) =>
      channel.invokeMethod('permissionSettings', permission);
  void dispose() {
    channel.setMethodCallHandler(null);
  }
}
