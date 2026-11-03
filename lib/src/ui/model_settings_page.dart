import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../models.dart';
import 'app_theme.dart' show ink;
import 'dash_mascot.dart';

// Settings actions and small copy need AA contrast on the light app surfaces.
const _accent = Color(0xff0065d6);
const _secondary = Color(0xff5b6d82);

/// Draft fields stay local until Apply; secrets never enter preferences or logs.
class ModelSettingsPage extends StatefulWidget {
  const ModelSettingsPage({super.key, required this.controller});
  final InterpreterController controller;

  @override
  State<ModelSettingsPage> createState() => _ModelSettingsPageState();
}

class _ModelSettingsPageState extends State<ModelSettingsPage> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late AudioSource _source;
  late String _inputUID;
  late MascotSkin _skin;
  late double _threshold;
  bool _showKey = false;
  int _tab = 0;
  String? _keyError, _modelError;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _key = TextEditingController(text: c.apiKey);
    _model = TextEditingController(text: c.model);
    _source = c.source;
    _inputUID = c.inputDeviceUID;
    unawaited(c.refreshInputDevices());
    _skin = c.mascotSkin;
    _threshold = c.megaphoneThresholdDbfs;
  }

  @override
  void dispose() {
    unawaited(widget.controller.stopMicrophoneTest());
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final c = widget.controller;
    await c.stopMicrophoneTest();
    if (!mounted) return;
    if (!c.settingsLocked) {
      final key = _key.text.trim(), model = _model.text.trim();
      setState(() {
        _keyError = RegExp(r'\s').hasMatch(key)
            ? 'API 키 안의 공백이나 줄바꿈을 지워 주세요.'
            : null;
        _modelError = model.isEmpty
            ? '사용할 Live 모델 ID를 입력해 주세요.'
            : !RegExp(r'^(models/)?[a-zA-Z0-9._-]+$').hasMatch(model)
            ? '모델 ID만 입력해 주세요. URL이나 공백은 사용할 수 없어요.'
            : null;
        if (_keyError != null || _modelError != null) _tab = 0;
      });
      if (_keyError != null || _modelError != null) return;
      c.apiKey = key;
      c.model = model;
      c.source = _source;
      c.inputDeviceUID = _inputUID;
      c.error = '';
    }
    c.setMascotSkin(_skin);
    c.setMegaphoneThreshold(_threshold);
    c.refresh();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    },
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final locked = widget.controller.settingsLocked;
        return Scaffold(
          backgroundColor: const Color(0xfff4f8fd),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 28, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '설정 닫기',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '설정',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const Spacer(),
                      const FlutterLogo(size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Flutter Live',
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      _tabButton(0, '모델 연결', Icons.key_rounded),
                      const SizedBox(width: 8),
                      _tabButton(1, '오디오 · 대쉬', Icons.tune_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(_tab),
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: _tab == 0
                            ? _connection(locked)
                            : _appearance(locked),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xffdce5ef))),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '변경한 내용은 적용 후 사용됩니다.',
                          style: TextStyle(color: _secondary, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: _accent),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _apply,
                        child: const Text('설정 적용'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _tabButton(int value, String title, IconData icon) => TextButton.icon(
    onPressed: () => setState(() => _tab = value),
    icon: Icon(icon, size: 18),
    label: Text(title),
    style: TextButton.styleFrom(
      foregroundColor: _tab == value ? _accent : _secondary,
      backgroundColor: _tab == value
          ? const Color(0xffe2efff)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  Widget _connection(bool locked) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '통역을 시작할 준비',
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Gemini API 키와 사용할 Live 모델을 설정해 주세요.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: _secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DashMascot(size: 106, skin: _skin, clip: 'wave'),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffdce5ef)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 28, color: _accent),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Google Gemini Live',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '실시간 음성 통역',
                    style: TextStyle(color: _secondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              _key.text.trim().isEmpty ? '키 입력 전' : '키 입력됨',
              style: const TextStyle(color: _secondary, fontSize: 12),
            ),
          ],
        ),
      ),
      if (locked) ...[
        const SizedBox(height: 16),
        const Text(
          '통역을 종료하면 API 키와 모델을 변경할 수 있어요.',
          style: TextStyle(color: ink, height: 1.5),
        ),
      ],
      const SizedBox(height: 26),
      TextField(
        key: const ValueKey('api-key-input'),
        controller: _key,
        enabled: !locked,
        obscureText: !_showKey,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() => _keyError = null),
        decoration: InputDecoration(
          labelText: 'Gemini API 키',
          hintText: 'Google AI Studio에서 발급한 키를 붙여넣으세요',
          errorText: _keyError,
          suffixIcon: IconButton(
            tooltip: _showKey ? 'API 키 숨기기' : 'API 키 보기',
            onPressed: locked
                ? null
                : () => setState(() => _showKey = !_showKey),
            icon: Icon(
              _showKey
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '키는 이번 실행에서만 사용하며 앱을 종료하면 지워집니다.',
        style: TextStyle(color: _secondary, height: 1.5, fontSize: 12),
      ),
      const SizedBox(height: 26),
      TextField(
        key: const ValueKey('model-id-input'),
        controller: _model,
        enabled: !locked,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _apply(),
        onChanged: (_) => setState(() => _modelError = null),
        decoration: InputDecoration(
          labelText: 'Live 모델 ID',
          hintText: '사용 가능한 Live 모델 ID',
          errorText: _modelError,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '계정에서 사용할 수 있는 Live API 모델 ID를 입력하세요.\n모델 접근 권한과 API 키는 통역 시작 시 확인됩니다.',
        style: TextStyle(color: _secondary, height: 1.6, fontSize: 12),
      ),
    ],
  );

  Widget _microphoneControls(bool locked) {
    final c = widget.controller;
    final devices = c.inputDevices;
    final defaults = devices.where((d) => d.isDefault);
    final defaultName = defaults.isEmpty ? '연결된 마이크 없음' : defaults.first.name;
    final missing =
        _inputUID.isNotEmpty && !devices.any((d) => d.uid == _inputUID);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'microphone-$_inputUID-${devices.map((d) => d.uid).join()}',
                ),
                initialValue: _inputUID,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '사용할 마이크'),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      '자동 · $defaultName',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final d in devices)
                    DropdownMenuItem(
                      value: d.uid,
                      child: Text(d.name, overflow: TextOverflow.ellipsis),
                    ),
                  if (missing)
                    DropdownMenuItem(
                      value: _inputUID,
                      child: const Text('선택한 마이크 · 연결 끊김'),
                    ),
                ],
                onChanged: locked || c.testingMicrophone
                    ? null
                    : (v) => setState(() => _inputUID = v!),
              ),
            ),
            IconButton(
              tooltip: '마이크 목록 새로고침',
              onPressed: c.refreshInputDevices,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '블루투스·USB·유선 등 macOS가 인식하는 모든 입력 장치를 사용할 수 있어요.',
          style: TextStyle(color: _secondary, fontSize: 12, height: 1.5),
        ),
        if (c.inputDevicesError.isNotEmpty)
          Text(c.inputDevicesError, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: locked || missing || devices.isEmpty
                  ? null
                  : () => c.testingMicrophone
                        ? c.stopMicrophoneTest()
                        : c.testMicrophone(_inputUID),
              icon: Icon(
                c.testingMicrophone
                    ? Icons.stop_rounded
                    : Icons.mic_none_rounded,
              ),
              label: Text(c.testingMicrophone ? '테스트 중지' : '마이크 테스트'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: LinearProgressIndicator(
                value: c.testingMicrophone ? c.inputLevel : 0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              c.testingMicrophone ? '${c.inputDbfs.round()} dBFS' : '입력 대기',
              style: const TextStyle(color: _secondary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          c.testingMicrophone
              ? c.microphoneTestChunks == 0
                    ? '마이크 연결 중…'
                    : '입력 수신 중 · 말씀해 보세요. 저장하거나 서버로 보내지 않습니다.'
              : 'API 키 없이 마이크 입력을 확인할 수 있어요.',
          style: const TextStyle(color: _secondary, fontSize: 12, height: 1.5),
        ),
        if (c.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              c.error,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _appearance(bool locked) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      const Text(
        '내게 맞는 통역 환경',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink),
      ),
      const SizedBox(height: 26),
      DropdownButtonFormField<AudioSource>(
        initialValue: _source,
        decoration: const InputDecoration(labelText: '오디오 입력'),
        items: const [
          DropdownMenuItem(
            value: AudioSource.microphone,
            child: Text('마이크 · 연결된 입력 장치'),
          ),
          DropdownMenuItem(
            value: AudioSource.system,
            child: Text('시스템 오디오 · 발표 / 동영상'),
          ),
        ],
        onChanged: locked
            ? null
            : (v) {
                unawaited(widget.controller.stopMicrophoneTest());
                setState(() => _source = v!);
              },
      ),
      const SizedBox(height: 10),
      if (_source == AudioSource.microphone) _microphoneControls(locked),
      const Text(
        '출력은 macOS 기본 장치를 사용합니다. 시스템 오디오는 화면 및 시스템 오디오 접근 승인이 필요해요.',
        style: TextStyle(color: _secondary, fontSize: 12, height: 1.5),
      ),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: _accent),
        onPressed: () =>
            widget.controller.desktop.openPermissionSettings(_source.name),
        child: const Text('macOS 권한 설정 열기'),
      ),
      const Divider(height: 32),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<MascotSkin>(
              initialValue: _skin,
              decoration: const InputDecoration(labelText: '대쉬 의상'),
              items: MascotSkin.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (v) => setState(() => _skin = v!),
            ),
          ),
          const SizedBox(width: 20),
          DashMascot(size: 100, skin: _skin, clip: 'wave'),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        '확성기 전환 · ${_threshold.round()} dBFS',
        style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
      ),
      Slider(
        activeColor: _accent,
        value: _threshold,
        min: -36,
        max: -6,
        divisions: 30,
        label: '${_threshold.round()} dBFS',
        semanticFormatterCallback: (v) => '${v.round()} dBFS',
        onChanged: (v) => setState(() => _threshold = v),
      ),
      const Text(
        '왼쪽으로 옮기면 더 작은 목소리에도 반응해요. 녹음 입력 크기 기준이며 실제 공간의 소음 데시벨은 아닙니다.',
        style: TextStyle(color: _secondary, height: 1.5, fontSize: 12),
      ),
      if (locked)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            '통역을 종료하면 오디오 입력을 변경할 수 있어요.',
            style: TextStyle(color: ink),
          ),
        ),
    ],
  );
}
