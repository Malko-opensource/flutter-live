import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_live/src/controller.dart';
import 'package:flutter_live/src/models.dart';
import 'package:flutter_live/src/ui/app.dart';
import 'package:flutter_live/src/ui/dash_mascot.dart';

import 'fake_desktop.dart';

void main() {
  testWidgets('two modes, same language prevention, preview and settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 780));
    final desktop = FakeDesktop();
    final c = InterpreterController(desktop: desktop);
    await tester.pumpWidget(FlutterLiveApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('대화 화면'), findsOneWidget);
    expect(find.text('자막 오버레이'), findsOneWidget);
    expect(find.text('실시간 대화'), findsNothing);
    c.setLanguages(c.first, c.first);
    expect(c.second.code, 'en');
    await tester.tap(find.text('자막 오버레이'));
    await tester.pumpAndSettle();
    expect(c.mode, DisplayMode.overlay);
    expect(c.voiceEnabled, false);
    expect(find.text('자막 띄우고 창 숨기기'), findsOneWidget);
    await tester.ensureVisible(find.text('디자인 미리보기'));
    await tester.tap(find.text('디자인 미리보기'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.phase, SessionPhase.preview);
    expect(find.text('Welcome to our Flutter meetup!'), findsOneWidget);
    await c.stop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini API 키'), findsOneWidget);
    expect(find.text('Live 모델 ID'), findsOneWidget);
    await tester.tap(find.text('오디오 · 대쉬'));
    await tester.pumpAndSettle();
    expect(find.text('오디오 입력'), findsOneWidget);
    expect(find.text('대쉬 의상'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<MascotSkin>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갓 · 두루마기').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정 적용'));
    await tester.pumpAndSettle();
    expect(c.mascotSkin, MascotSkin.gat);
    expect(
      tester.widget<DashMascot>(find.byType(DashMascot)).skin,
      MascotSkin.gat,
    );
    expect(desktop.lastState?['mascotSkin'], 'gat');
    await c.setMode(DisplayMode.conversation);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DashMascot>(find.byType(DashMascot)).skin,
      MascotSkin.gat,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.setSurfaceSize(null);
    expect(tester.takeException(), isNull);
  });
  testWidgets('minimum window and long current caption do not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(650, 650));
    final c = InterpreterController(desktop: FakeDesktop());
    c.caption.input('This is a long presentation sentence. ' * 15);
    c.caption.output('개발자 행사에서 사용하는 긴 번역문입니다. ' * 15);
    await tester.pumpWidget(FlutterLiveApp(controller: c));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.setSurfaceSize(null);
  });
}
