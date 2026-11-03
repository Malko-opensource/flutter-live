import 'dart:async';

import 'dash_mascot.dart';
import 'app_theme.dart';
import 'model_settings_page.dart';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';

class FlutterLiveApp extends StatelessWidget {
  const FlutterLiveApp({super.key, required this.controller});
  final InterpreterController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Flutter Live',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        surface: const Color(0xfff8fbff),
      ),
      scaffoldBackgroundColor: const Color(0xfff4f8fd),
      fontFamily: '.AppleSystemUIFont',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink),
        bodyLarge: TextStyle(color: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce5ef)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xffdce5ef)),
        ),
      ),
    ),
    home: InterpreterScreen(controller: controller),
  );
}

class InterpreterScreen extends StatelessWidget {
  const InterpreterScreen({super.key, required this.controller});
  final InterpreterController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 20, 14),
                child: Row(
                  children: [
                    const FlutterLogo(size: 27),
                    const SizedBox(width: 12),
                    const Text(
                      'Flutter Live',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '함께 듣고, 함께 이해해요',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '설정',
                      onPressed: () => _settings(context, c),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: SegmentedButton<DisplayMode>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: DisplayMode.overlay,
                      label: Text('자막 오버레이'),
                      icon: Icon(Icons.subtitles_outlined),
                    ),
                    ButtonSegment(
                      value: DisplayMode.conversation,
                      label: Text('대화 화면'),
                      icon: Icon(Icons.people_outline_rounded),
                    ),
                  ],
                  selected: {c.mode},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? blue
                          : Colors.white,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : ink,
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 17),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  onSelectionChanged: (value) => c.setMode(value.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                child: Row(
                  children: [
                    Expanded(child: _language(c.first, c, true)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Icon(Icons.swap_horiz_rounded, color: muted),
                    ),
                    Expanded(child: _language(c.second, c, false)),
                    const SizedBox(width: 18),
                    const Icon(Icons.auto_awesome, size: 15, color: blue),
                    const SizedBox(width: 6),
                    const Text(
                      '언어 자동 감지',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: c.mode == DisplayMode.conversation
                          ? _conversation(context, c)
                          : _overlayMode(context, c),
                    ),
                  ),
                ),
              ),
              if (c.error.isNotEmpty && c.phase != SessionPhase.failed)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    c.error,
                    style: const TextStyle(
                      color: Colors.deepOrange,
                      fontSize: 12,
                    ),
                  ),
                ),
              _footer(context, c),
            ],
          ),
        ),
      );
    },
  );

  Widget _language(Language value, InterpreterController c, bool first) =>
      DropdownButtonFormField<Language>(
        key: ValueKey('${first}_${value.code}'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          isDense: true,
        ),
        items: Language.values
            .where((l) => l.code != (first ? c.second.code : c.first.code))
            .map((l) => DropdownMenuItem(value: l, child: Text(l.label)))
            .toList(),
        onChanged: c.settingsLocked
            ? null
            : (l) {
                if (l != null) {
                  c.setLanguages(first ? l : c.first, first ? c.second : l);
                }
              },
      );

  Widget _conversation(
    BuildContext context,
    InterpreterController c,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(36, 12, 36, 24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DashMascot(
          size: 210,
          clip: c.mascotClip,
          skin: c.mascotSkin,
          animate: c.active || c.phase == SessionPhase.preview,
        ),
        const SizedBox(height: 4),
        _status(c),
        const SizedBox(height: 28),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              Text(
                c.caption.translation.isEmpty
                    ? (c.phase == SessionPhase.idle
                          ? '언어가 달라도, 대화는 가깝게.'
                          : '말씀해 주세요')
                    : c.caption.translation,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: c.caption.translation.length > 90 ? 26 : 34,
                  height: 1.35,
                  letterSpacing: -.8,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                c.caption.sourceText.isEmpty
                    ? '두 언어를 선택하면 Dash가 통역을 도와드려요.'
                    : c.caption.sourceText,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, height: 1.5, color: muted),
              ),
            ],
          ),
        ),
        if (c.phase == SessionPhase.idle || c.phase == SessionPhase.failed) ...[
          const SizedBox(height: 28),
          TextButton.icon(
            onPressed: c.preview,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('디자인 미리보기'),
          ),
        ],
      ],
    ),
  );

  Widget _overlayMode(BuildContext context, InterpreterController c) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: const Text(
                '발표에 집중하세요.',
                style: TextStyle(
                  fontSize: 28,
                  letterSpacing: -.7,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            if (!c.active)
              TextButton(onPressed: c.preview, child: const Text('디자인 미리보기')),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Dash가 화면 위에서 통역을 전해드릴게요.',
          style: TextStyle(fontSize: 15, color: muted),
        ),
        const SizedBox(height: 16),
        Container(
          height: 210,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xffe6eef8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffd6e1ee)),
          ),
          child: Stack(
            children: [
              const Positioned(
                left: 30,
                top: 24,
                child: Row(
                  children: [
                    FlutterLogo(size: 28),
                    SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build beautiful apps',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('Flutter Meetup', style: TextStyle(color: muted)),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: CaptionBar(
                  translation: c.caption.translation.isEmpty
                      ? '번역 자막이 여기에 표시됩니다.'
                      : c.caption.translation,
                  original: c.caption.sourceText.isEmpty
                      ? '현재 발화만 표시해요.'
                      : c.caption.sourceText,
                  label: c.phase == SessionPhase.preview
                      ? '디자인 미리보기'
                      : c.pairLabel,
                  compact: true,
                  clip: c.mascotClip,
                  skin: c.mascotSkin,
                  animate: c.active || c.phase == SessionPhase.preview,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _status(c),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: c.presentOverlay,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('자막 띄우고 창 숨기기'),
              ),
            ),
            const SizedBox(width: 10),
            if (c.overlayVisible)
              IconButton(
                tooltip: '자막 숨기기',
                onPressed: c.hideOverlay,
                icon: const Icon(Icons.visibility_off_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '메뉴바의 파형 아이콘에서 이 창을 다시 열 수 있어요.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    ),
  );

  Widget _status(InterpreterController c) => Semantics(
    liveRegion: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.phase == SessionPhase.failed
                ? Colors.redAccent
                : c.active
                ? const Color(0xff28ba75)
                : muted,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            c.status,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: c.phase == SessionPhase.failed ? Colors.redAccent : muted,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _footer(BuildContext context, InterpreterController c) => Container(
    padding: const EdgeInsets.fromLTRB(24, 15, 24, 18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xffe2eaf4))),
    ),
    child: Row(
      children: [
        Icon(
          c.source == AudioSource.microphone
              ? Icons.mic_none_rounded
              : Icons.computer_rounded,
          size: 21,
          color: muted,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: LinearProgressIndicator(
            value: c.inputLevel,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: c.voiceEnabled ? '번역 음성 끄기' : '번역 음성 켜기',
          onPressed: () => c.setVoice(!c.voiceEnabled),
          icon: Icon(
            c.voiceEnabled
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined,
            size: 22,
          ),
        ),
        SizedBox(
          width: 90,
          child: Slider(
            value: c.volume,
            onChanged: c.voiceEnabled ? c.setVolume : null,
            semanticFormatterCallback: (v) => '${(v * 100).round()}%',
          ),
        ),
        const Spacer(),
        if (c.active ||
            c.phase == SessionPhase.paused ||
            c.phase == SessionPhase.preview)
          IconButton(
            tooltip: '통역 종료',
            onPressed: c.stop,
            icon: const Icon(Icons.stop_rounded),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () {
            if (c.active) {
              unawaited(c.pause());
            } else if (c.apiKey.trim().isEmpty) {
              _settings(context, c);
            } else {
              unawaited(c.start());
            }
          },
          icon: Icon(
            c.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 21,
          ),
          label: Text(
            c.active
                ? '일시 정지'
                : c.phase == SessionPhase.paused
                ? '통역 재개'
                : '통역 시작',
          ),
        ),
      ],
    ),
  );

  Future<void> _settings(BuildContext context, InterpreterController c) async {
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ModelSettingsPage(controller: c)),
    );
    if (applied == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('설정을 적용했어요.')));
    }
  }
}

class CaptionBar extends StatelessWidget {
  const CaptionBar({
    super.key,
    required this.translation,
    required this.original,
    required this.label,
    this.compact = false,
    this.clip = 'idle',
    this.skin = MascotSkin.hanbok,
    this.animate = false,
  });
  final String translation, original, label;
  final bool compact;
  final String clip;
  final MascotSkin skin;
  final bool animate;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 10, 16, 10),
    decoration: BoxDecoration(
      color: const Color(0xff172b44).withValues(alpha: .94),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        DashMascot(
          size: compact ? 84 : 120,
          clip: clip,
          skin: skin,
          animate: animate,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xffb3c9e5)),
              ),
              const SizedBox(height: 5),
              Text(
                translation,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 16 : 24,
                  height: 1.35,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                original,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 15,
                  color: const Color(0xffbfcbd9),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
