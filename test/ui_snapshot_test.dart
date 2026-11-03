import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/controller.dart';
import 'package:flutter_live/src/models.dart';
import 'package:flutter_live/src/ui/app.dart';

import 'fake_desktop.dart';

void main() {
  testWidgets('capture actual Flutter screens for visual inspection', (
    tester,
  ) async {
    final loader = FontLoader('.AppleSystemUIFont');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('/System/Library/Fonts/AppleSDGothicNeo.ttc').readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future.value(
        ByteData.sublistView(
          File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
              .readAsBytesSync(),
        ),
      ),
    );
    await icons.load();
    await tester.binding.setSurfaceSize(const Size(760, 780));
    final c = InterpreterController(desktop: FakeDesktop());
    c.caption.input('Flutter 밋업에 오신 것을 환영합니다!');
    c.caption.output('Welcome to our Flutter meetup!');
    c.phase = SessionPhase.preview;
    const boundary = ValueKey('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: FlutterLiveApp(controller: c),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('../docs/verification/conversation.png'),
    );
    await c.setMode(DisplayMode.overlay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('../docs/verification/overlay-controls.png'),
    );
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('../docs/verification/model-settings.png'),
    );
    await tester.binding.setSurfaceSize(const Size(650, 650));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('../docs/verification/model-settings-small.png'),
    );
    await tester.tap(find.text('오디오 · 대쉬'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('../docs/verification/audio-settings-small.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.setSurfaceSize(null);
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));
}
