import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/controller.dart';
import 'package:flutter_live/src/models.dart';
import 'package:flutter_live/src/ui/app.dart';

import 'fake_desktop.dart';

void main() {
  Future<InterpreterController> open(
    WidgetTester tester, {
    bool locked = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(650, 650));
    final c = InterpreterController(desktop: FakeDesktop())
      ..apiKey = 'existing-test-key'
      ..model = 'test-live-model';
    if (locked) c.phase = SessionPhase.paused;
    await tester.pumpWidget(FlutterLiveApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> close(WidgetTester tester, InterpreterController c) async {
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.setSurfaceSize(null);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'key is masked, draft is discarded, and apply trims configuration',
    (tester) async {
      final c = await open(tester);
      final key = find.byKey(const ValueKey('api-key-input'));
      final model = find.byKey(const ValueKey('model-id-input'));
      expect(tester.widget<TextField>(key).obscureText, isTrue);
      await tester.tap(find.byTooltip('API 키 보기'));
      await tester.pump();
      expect(tester.widget<TextField>(key).obscureText, isFalse);
      await tester.enterText(key, 'discarded-test-key');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(c.apiKey, 'existing-test-key');
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(key).obscureText, isTrue);
      await tester.enterText(key, '  new-test-key  ');
      await tester.ensureVisible(model);
      await tester.enterText(model, '  models/test-live-model-v2  ');
      expect(c.apiKey, 'existing-test-key');
      await tester.tap(find.text('설정 적용'));
      await tester.pumpAndSettle();
      expect(c.apiKey, 'new-test-key');
      expect(c.model, 'models/test-live-model-v2');
      expect(c.active, isFalse);
      await close(tester, c);
    },
  );

  testWidgets(
    'invalid configuration stays on page; empty key can clear credentials',
    (tester) async {
      final c = await open(tester);
      final key = find.byKey(const ValueKey('api-key-input'));
      final model = find.byKey(const ValueKey('model-id-input'));
      await tester.enterText(key, 'bad key');
      await tester.ensureVisible(model);
      await tester.enterText(model, '');
      await tester.tap(find.text('설정 적용'));
      await tester.pumpAndSettle();
      expect(find.text('사용할 Live 모델 ID를 입력해 주세요.'), findsOneWidget);
      expect(c.apiKey, 'existing-test-key');
      await tester.enterText(model, 'test-live-model');
      await tester.ensureVisible(key);
      await tester.enterText(key, '');
      await tester.tap(find.text('설정 적용'));
      await tester.pumpAndSettle();
      expect(c.apiKey, isEmpty);
      await close(tester, c);
    },
  );

  testWidgets('paused session keeps connection fields locked', (tester) async {
    final c = await open(tester, locked: true);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('api-key-input')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('model-id-input')))
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('설정 적용'));
    await tester.pumpAndSettle();
    expect(c.apiKey, 'existing-test-key');
    expect(c.model, 'test-live-model');
    await close(tester, c);
  });
}
