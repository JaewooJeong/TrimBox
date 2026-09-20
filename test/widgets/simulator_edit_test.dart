// SimulatorScreen 위젯 플로우 테스트 — 키보드 편집, 패널, 자동 배치 대안, 스텝 뷰.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/box_list_panel.dart';
import 'package:trimbox/widgets/keyboard_shortcuts_dialog.dart';

import 'sim_harness.dart';

Finder _inPanel(Finder f) =>
    find.descendant(of: find.byType(BoxListPanel), matching: f);

/// 타일 Card 색 (선택 시 0xFF333344)
Color _tileColor(WidgetTester tester, String label) {
  final card = tester.widget<Card>(find
      .ancestor(of: _inPanel(find.text(label)), matching: find.byType(Card))
      .first);
  return card.color!;
}

final _sorento = TrunkSpace.sorento();

/// 천장에는 안 닿지만 테일게이트 유리 기울기에는 걸리는 높이 (현재 0.74)
final double _tallH = _sorento.h - 0.08;

void main() {
  setUpAll(loadRealFonts);

  group('6. 키보드 편집', () {
    testWidgets('목록에서 고르고 화살표로 옮긴다 (↓ = 테일게이트 쪽 z+)', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '낮은 박스', w: 0.40, d: 0.30, h: 0.30, x: 0.40, z: 0.30),
      ]);
      expect(find.byType(SnackBar), findsNothing, reason: '조용한 복원');
      await tapTile(tester, '낮은 박스');
      expect(panelOf(tester).selectedBoxId, 'box-001');
      expect(painterOf(tester).selectedBoxId, 'box-001');

      final b = boxesOf(tester).single;
      final unit = spaceOf(tester).gridUnit;
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      expect(b.z, closeTo(0.30 + unit, 1e-6));
      await pressKey(tester, LogicalKeyboardKey.arrowUp, times: 2);
      expect(b.z, closeTo(0.30 - unit, 1e-6));
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(b.x, closeTo(0.40 + unit, 1e-6));
      await pressKey(tester, LogicalKeyboardKey.arrowLeft, times: 2);
      expect(b.x, closeTo(0.40 - unit, 1e-6));

      // 경계에서 멈춘다
      await pressKey(tester, LogicalKeyboardKey.arrowLeft, times: 45);
      expect(b.x, closeTo(0, 1e-6));
      await pressKey(tester, LogicalKeyboardKey.arrowDown, times: 60);
      expect(b.z, closeTo(spaceOf(tester).d - 0.30, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('높은 짐을 테일게이트 쪽 끝으로 밀면 빨간 상태 + 사유 다이얼로그, Ctrl+Z 로 되돌린다',
        (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '높은 박스', w: 0.40, d: 0.30, h: _tallH, x: 0.45, z: 0.35),
      ]);
      expect(statusOf(tester), StatusState.ok);
      expect(find.text('배치 문제 없음 · 테일게이트 닫힘'), findsOneWidget);

      await tapTile(tester, '높은 박스');
      final b = boxesOf(tester).single;
      final unit = spaceOf(tester).gridUnit;
      // 벽에 닿는 데 필요한 만큼만 (벽에서 더 누르면 변화 없는 undo 항목이 쌓인다)
      final steps = ((spaceOf(tester).d - 0.30 - 0.35) / unit).round();
      await pressKey(tester, LogicalKeyboardKey.arrowDown, times: steps);
      await tester.pumpAndSettle();
      expect(b.z, closeTo(spaceOf(tester).d - 0.30, 1e-6));

      expect(statusOf(tester), StatusState.problems);
      expect(_inPanel(find.textContaining('테일게이트 닫힘 불가')), findsOneWidget);
      expect(_inPanel(find.byIcon(Icons.warning_amber_rounded)), findsWidgets);
      expect(panelOf(tester).collidingBoxIds, contains('box-001'));
      expect(painterOf(tester).tailgateBlockedIds, contains('box-001'));

      // 상태 줄을 누르면 사유 전체
      await tester.tap(_inPanel(find.textContaining('테일게이트 닫힘 불가')));
      await tester.pumpAndSettle();
      expect(find.text('배치 문제 1개'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining(
                  RegExp(r'높은 박스: .*테일게이트 닫힘 불가 \(\+\d+cm 튀어나옴\)'))),
          findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('배치 문제 1개'), findsNothing);

      // Ctrl+Z 한 번 = 한 칸 (되돌리면 선택이 풀린다)
      final zEnd = b.z;
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      expect(boxesOf(tester).single.z, lessThan(zEnd));
      expect(panelOf(tester).selectedBoxId, isNull);
      // 끝까지 되돌리면 원래 자리, 초록 상태
      for (var i = 0; i < steps + 2; i++) {
        await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      }
      await tester.pumpAndSettle();
      expect(boxesOf(tester).single.z, closeTo(0.35, 1e-6));
      expect(statusOf(tester), StatusState.ok);

      // Ctrl+Y / Ctrl+Shift+Z 다시 실행
      await pressCtrl(tester, LogicalKeyboardKey.keyY);
      expect(boxesOf(tester).single.z, closeTo(0.35 + unit, 1e-6));
      await pressCtrl(tester, LogicalKeyboardKey.keyZ, shift: true);
      expect(boxesOf(tester).single.z, closeTo(0.35 + 2 * unit, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('R 회전, Delete 삭제, Backspace 삭제', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
        mkBox('box-002', '나', w: 0.30, d: 0.30, h: 0.30, x: 0.80, z: 0.20),
      ]);
      await tapTile(tester, '가');
      await pressKey(tester, LogicalKeyboardKey.keyR, character: 'r');
      final a = boxesOf(tester).firstWhere((b) => b.id == 'box-001');
      expect(a.rotY, 90);
      expect(_inPanel(find.textContaining('R:90°')), findsOneWidget);
      expect(a.effectiveW, closeTo(0.30, 1e-9));

      await pressKey(tester, LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(boxesOf(tester).map((b) => b.id), ['box-002']);
      expect(find.text('박스: 1개'), findsOneWidget);
      expect(panelOf(tester).selectedBoxId, isNull);

      // 선택이 없으면 Delete 는 아무것도 하지 않는다
      await pressKey(tester, LogicalKeyboardKey.delete);
      expect(boxesOf(tester), hasLength(1));

      await tapTile(tester, '나');
      await pressKey(tester, LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(boxesOf(tester), isEmpty);
      expect(find.text('캠핑 장비 선택하기'), findsOneWidget);

      // 삭제도 되돌릴 수 있다
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(boxesOf(tester).map((b) => b.id), ['box-002']);
      await flushAutosave(tester);
    });

    testWidgets("'0' 카메라 초기화, Q/E 회전, '?' 단축키 도움말 — 예외 없음", (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ]);
      final yaw0 = painterOf(tester).camera.yaw;
      await pressKey(tester, LogicalKeyboardKey.keyQ, character: 'q');
      expect(painterOf(tester).camera.yaw, isNot(closeTo(yaw0, 1e-9)));
      await pressKey(tester, LogicalKeyboardKey.keyE, character: 'e', times: 3);
      await pressKey(tester, LogicalKeyboardKey.digit0, character: '0');
      expect(painterOf(tester).camera.yaw, closeTo(yaw0, 1e-9));
      await pressKey(tester, LogicalKeyboardKey.numpad0, character: '0');
      expect(tester.takeException(), isNull);

      // 빈 트렁크에서도
      await tapTile(tester, '가');
      await pressKey(tester, LogicalKeyboardKey.delete);
      await pressKey(tester, LogicalKeyboardKey.digit0, character: '0');
      expect(tester.takeException(), isNull);

      await pressKey(tester, LogicalKeyboardKey.slash, character: '?');
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardShortcutsDialog), findsOneWidget);
      await flushAutosave(tester);
    });

    testWidgets('앱바 도움말 버튼이 단축키 다이얼로그를 연다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(find.byTooltip('키보드 단축키 (?)'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardShortcutsDialog), findsOneWidget);
    });

    testWidgets('키보드로 옮겨 다른 짐 위에 올리면 쌓이고, 빼면 바닥으로 내려온다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '받침', w: 0.50, d: 0.40, h: 0.30, x: 0.30, z: 0.30),
        // x 0.80~1.20: 오른쪽 휠하우스(x ≥ 1.235)에 닿지 않는 바닥 자리
        mkBox('box-002', '위', w: 0.40, d: 0.30, h: 0.20, x: 0.80, z: 0.35),
      ]);
      await tapTile(tester, '위');
      final top = boxesOf(tester).firstWhere((b) => b.id == 'box-002');
      final unit = spaceOf(tester).gridUnit;
      await pressKey(tester, LogicalKeyboardKey.arrowLeft,
          times: (0.50 / unit).round());
      await tester.pumpAndSettle();
      expect(top.x, closeTo(0.30, 1e-6));
      expect(top.y, closeTo(0.30, 1e-6), reason: '받침 위로 올라간다');
      expectSceneValid(tester);
      await pressKey(tester, LogicalKeyboardKey.arrowRight,
          times: (0.50 / unit).round());
      await tester.pumpAndSettle();
      expect(top.y, closeTo(0.0, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('화살표 키가 캔버스 포커스를 빼앗기지 않는다 (웹 외 플랫폼)', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '낮은 박스', w: 0.40, d: 0.30, h: 0.30, x: 0.40, z: 0.30),
      ]);
      await tapTile(tester, '낮은 박스');
      await focusCanvas(tester);
      await pressKey(tester, LogicalKeyboardKey.arrowUp,
          times: 3, keepCanvasFocus: false);
      expect(canvasFocusNode(tester).hasPrimaryFocus, isTrue);
      expect(boxesOf(tester).single.z,
          closeTo(0.30 - 3 * spaceOf(tester).gridUnit, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('화살표를 누르고 있으면 (키 반복) 계속 움직인다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '낮은 박스', w: 0.40, d: 0.30, h: 0.30, x: 0.40, z: 0.30),
      ]);
      await tapTile(tester, '낮은 박스');
      await focusCanvas(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(boxesOf(tester).single.z,
          closeTo(0.30 + 6 * spaceOf(tester).gridUnit, 1e-6));
      // 누르고 있던 한 번의 이동은 Ctrl+Z 한 번으로 되돌아간다
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      expect(boxesOf(tester).single.z, closeTo(0.30, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('벽에 막혀 변화가 없는 이동은 실행 취소 항목을 만들지 않는다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '낮은 박스', w: 0.40, d: 0.30, h: 0.30, x: 0.02, z: 0.30),
      ]);
      await tapTile(tester, '낮은 박스');
      await pressKey(tester, LogicalKeyboardKey.arrowLeft, times: 6);
      expect(boxesOf(tester).single.x, closeTo(0, 1e-6));
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      expect(boxesOf(tester).single.x, greaterThan(0.005),
          reason: 'Ctrl+Z 한 번이면 마지막 실제 이동이 되돌려져야 한다');
      await flushAutosave(tester);
    });

    testWidgets('이동과 무관한 키는 "손으로 편집함" 으로 치지 않는다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '첫 박스', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);
      await tapTile(tester, '첫 박스');
      await pressKey(tester, LogicalKeyboardKey.keyA, character: 'a');
      await addCustomBox(tester, label: '둘째 박스', w: 40, d: 30, h: 30);
      expect(snackTexts(tester).join(), contains('2개 배치 완료'),
          reason: '손댄 적이 없으니 추가 즉시 전체 자동 배치 + 판정 스낵바');
      await flushAutosave(tester);
    });
  });

  group('7. 패널', () {
    testWidgets('선택 강조 토글, 회전·삭제 버튼, 통계', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
        mkBox('box-002', '나', w: 0.30, d: 0.30, h: 0.30, x: 0.80, z: 0.20),
        mkBox('box-003', '다', w: 0.30, d: 0.30, h: 0.30, x: 0.20, z: 0.60),
      ]);
      expect(find.text('박스: 3개'), findsOneWidget);
      expect(_inPanel(find.textContaining(RegExp(r'^부피: \d+%$'))), findsOneWidget);
      expect(_inPanel(find.textContaining(RegExp(r'^면적: \d+%$'))), findsOneWidget);
      expect(_inPanel(find.textContaining(RegExp(r'^총 \d+L · 남은 높이: \d+cm$'))),
          findsOneWidget);
      // 캔버스 오버레이
      expect(find.text('총 짐: 3개'), findsOneWidget);
      expect(find.textContaining('남은 공간: ~'), findsOneWidget);

      const selected = Color(0xFF333344);
      expect(_tileColor(tester, '나'), isNot(selected));
      await tapTile(tester, '나');
      expect(_tileColor(tester, '나'), selected);
      expect(_tileColor(tester, '가'), isNot(selected));
      await tapTile(tester, '나');
      expect(_tileColor(tester, '나'), isNot(selected), reason: '다시 누르면 해제');
      expect(panelOf(tester).selectedBoxId, isNull);

      // 회전 버튼 (둘째 타일)
      await tester.tap(find.byTooltip('90° 회전').at(1));
      await tester.pumpAndSettle();
      expect(boxesOf(tester)[1].rotY, 90);
      expect(_inPanel(find.textContaining('R:90°')), findsOneWidget);

      // 삭제 버튼 (첫 타일)
      await tester.tap(find.byTooltip('삭제').first);
      await tester.pumpAndSettle();
      expect(boxesOf(tester).map((b) => b.label), ['나', '다']);
      expect(find.text('박스: 2개'), findsOneWidget);
      await flushAutosave(tester);
    });

    testWidgets('선택된 박스를 삭제 버튼으로 지우면 선택도 풀린다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
        mkBox('box-002', '나', w: 0.30, d: 0.30, h: 0.30, x: 0.80, z: 0.20),
      ]);
      await tapTile(tester, '가');
      await tester.tap(find.byTooltip('삭제').first);
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, isNull);
      expect(painterOf(tester).selectedBoxId, isNull);
      await flushAutosave(tester);
    });

    testWidgets('상태 줄 — 초록: 문제 없음', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ]);
      expect(statusOf(tester), StatusState.ok);
      expect(_inPanel(find.byIcon(Icons.check_circle_outline)), findsWidgets);
    });

    testWidgets('상태 줄 — 주황: 조언만 있을 때, 누르면 적재 조언 다이얼로그', (tester) async {
      await pumpAppWithScene(tester, [
        // 자주 꺼내는 쿨러가 안쪽, 바로 뒤를 다른 짐이 막음
        mkBox('box-001', '쿨러', w: 0.40, d: 0.30, h: 0.30,
            x: 0.40, z: 0.15, access: true, upright: true, weightKg: 12),
        mkBox('box-002', '막는 박스', w: 0.40, d: 0.30, h: 0.30, x: 0.40, z: 0.45),
      ]);
      expect(panelOf(tester).collidingBoxIds, isEmpty);
      expect(statusOf(tester), StatusState.advice);
      final row = _inPanel(find.textContaining('자주 꺼내는 짐인데 안쪽에 있고'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('적재 조언 1개'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.textContaining('쿨러: 자주 꺼내는 짐')),
          findsOneWidget);
      // 조언은 경고(빨간 삼각형)가 아니라 전구 아이콘
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byIcon(Icons.lightbulb_outline)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byIcon(Icons.warning_amber_rounded)),
          findsNothing);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('적재 조언 1개'), findsNothing);
    });

    testWidgets('상태 줄 — 빨강: 문제가 여러 개면 (+N), 다이얼로그에 전부', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '천장 뚫음', w: 0.30, d: 0.30, h: _sorento.h + 0.13, x: 0.50, z: 0.30),
        mkBox('box-002', '테일게이트 막음', w: 0.30, d: 0.30, h: _tallH,
            x: 0.20, z: _sorento.d - 0.30),
      ]);
      expect(statusOf(tester), StatusState.problems);
      expect(_inPanel(find.textContaining('외 1건')), findsOneWidget);
      expect(panelOf(tester).collidingBoxIds, {'box-001', 'box-002'});
      // 충돌 타일에는 경고 아이콘
      expect(find.byTooltip('충돌 감지: 다른 박스 또는 경계와 겹침'), findsNWidgets(2));

      await tester.tap(_inPanel(find.textContaining('외 1건')));
      await tester.pumpAndSettle();
      expect(find.text('배치 문제 2개'), findsOneWidget);
      final dialogTexts = [
        for (final t in tester.widgetList<Text>(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(Text))))
          t.data ?? ''
      ].join('\n');
      expect(dialogTexts, contains('천장 뚫음: '));
      expect(dialogTexts, contains('천장 초과'));
      expect(dialogTexts, contains('테일게이트 막음: '));
      expect(dialogTexts, contains('테일게이트 닫힘 불가'));
    });

    testWidgets('눌러 넣은 연질 짐이 맨 위일 때 "남은 높이" 가 음수로 나오지 않는다', (tester) async {
      final bag = mkBox('box-002', '침낭', w: 0.40, d: 0.30, h: 0.30,
          x: 0.40, y: 0.55, z: 0.40, soft: true)
        ..compressibility = 0.4
        ..squash = 0.3; // 실제 높이 0.21 → 윗면 0.76 < 천장
      await pumpAppWithScene(tester, [
        mkBox('box-001', '받침', w: 0.50, d: 0.40, h: 0.55, x: 0.35, z: 0.35),
        bag,
      ]);
      expect(statusOf(tester), StatusState.ok, reason: '배치는 유효');
      expect(_inPanel(find.textContaining('남은 높이: -')), findsNothing);
    });

    testWidgets('못 넣은 짐(트렁크 밖)은 적재율에서 빠진다: 오버레이 % = 판정 %', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '큰 박스', w: 60, d: 50, h: 40);
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '너무 큰 박스', w: 200, d: 150, h: 120);
      final snack = snackTexts(tester).join();
      expect(snack, contains('1/2개 배치'));
      final verdictPct =
          int.parse(RegExp(r'적재율 (\d+)%').firstMatch(snack)!.group(1)!);
      final overlay = allTexts(tester)
          .firstWhere((t) => RegExp(r'^\d+\.\d%$').hasMatch(t));
      expect(double.parse(overlay.replaceAll('%', '')).round(), verdictPct);
      await flushAutosave(tester);
    });
  });

  group('7b. 판정 알림', () {
    testWidgets('트렁크보다 큰 짐 하나: 0/1 판정, 사유, "적재 불가" 다이얼로그', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '냉장고', w: 200, d: 150, h: 120);
      final snack = snackTexts(tester).join('\n');
      expect(snack, contains('0/1개 배치'));
      expect(snack, contains('적재 불가: 냉장고 — 트렁크보다 큼'));
      expect(insideBoxes(tester), isEmpty, reason: '테일게이트 밖에 세워 둔다');
      expect(statusOf(tester), StatusState.problems);
      // 앱이 밖에 세워 둔 짐은 "경계 밖 충돌" 이 아니라 못 실은 짐으로 말한다
      expect(_inPanel(find.textContaining('냉장고: 안 들어감')), findsOneWidget);
      expect(find.byTooltip('트렁크에 넣을 자리가 없어 밖에 두었습니다'), findsOneWidget);
      await flushSnackBars(tester);

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.text('적재 불가'), findsOneWidget);
      expect(find.text('선택한 장비가 트렁크에 맞지 않습니다.'), findsOneWidget);
      expect(find.textContaining('2열을 당겨도 들어가지 않습니다'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    });

    testWidgets('연달아 추가하면 스낵바가 최신 판정을 보여준다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '하나', w: 40, d: 30, h: 30);
      await addCustomBox(tester, label: '둘', w: 40, d: 30, h: 30);
      expect(snackTexts(tester).join(), contains('2개 배치 완료'));
      await flushSnackBars(tester);
      await flushAutosave(tester);
    });
  });

  group('8. 자동 배치 대안 · 스텝 뷰', () {
    testWidgets('세 전략이 나오고 하나를 적용하면 판정 + 적재 순서 배지', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '2인 미니멀 캠핑');
      await flushSnackBars(tester);

      await tester.tap(_inPanel(find.text('자동 배치')));
      await tester.pumpAndSettle();
      expect(find.text('배치 전략을 선택하세요:'), findsOneWidget);
      for (final s in ['균형 배치', '최대 적재', '접근 우선']) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('추천'), findsOneWidget);
      expect(find.text('9개 모두'), findsNWidgets(3));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      // 취소는 아무것도 바꾸지 않는다
      final before = [for (final b in boxesOf(tester)) (b.x, b.y, b.z, b.rotY)];
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect([for (final b in boxesOf(tester)) (b.x, b.y, b.z, b.rotY)], before);

      await tester.tap(_inPanel(find.text('자동 배치')));
      await tester.pumpAndSettle();
      // 목록의 세 번째 전략을 고른다
      final labels = ['균형 배치', '최대 적재', '접근 우선'];
      final order = [
        for (final t in allTexts(tester))
          if (labels.contains(t)) t
      ];
      final pick = order.last;
      await tester.tap(find.text(pick));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 배치 적용'));
      await tester.pumpAndSettle();

      expect(find.text('모두 적재 가능!'), findsOneWidget);
      expect(snackTexts(tester).join(), startsWith('$pick: 9개 배치 완료'));
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      // 적재 순서 1..9 가 중복 없이
      final orders = boxesOf(tester).map((b) => b.loadOrder).toList()..sort();
      expect(orders, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expectSceneValid(tester);
      // 목록 배지에도 숫자가 보인다
      expect(_inPanel(find.text('1')), findsOneWidget);

      // 적용은 되돌릴 수 있다
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect([for (final b in boxesOf(tester)) (b.x, b.y, b.z, b.rotY)], before);
      await flushAutosave(tester);
    });

    testWidgets('액션바의 자동 배치 아이콘도 같은 다이얼로그를 연다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await tester.tap(find.byTooltip('자동 배치'));
      await tester.pumpAndSettle();
      expect(find.text('배치 전략을 선택하세요:'), findsOneWidget);
      expect(find.text('이 배치 적용'), findsOneWidget);
    });

    testWidgets('스텝 뷰: 들어가기, 앞뒤 이동, 끝에서 비활성, 닫기', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      expect(painterOf(tester).highlightLoadOrder, isNull);

      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 / 6'), findsOneWidget);
      expect(painterOf(tester).highlightLoadOrder, 1);
      String nameOfStep(int n) =>
          boxesOf(tester).firstWhere((b) => b.loadOrder == n).label;
      // 현재 스텝의 장비명이 컨트롤에 나온다 (목록에도 같은 이름이 있으므로 2개 이상)
      expect(find.text(nameOfStep(1)), findsWidgets);

      IconButton btn(IconData icon) => tester.widget<IconButton>(
          find.ancestor(of: stepButton(icon), matching: find.byType(IconButton)));
      expect(btn(Icons.chevron_left).onPressed, isNull, reason: '첫 스텝');

      for (var n = 2; n <= 6; n++) {
        await tester.tap(stepButton(Icons.chevron_right));
        await tester.pumpAndSettle();
        expect(find.text('STEP $n / 6'), findsOneWidget);
        expect(painterOf(tester).highlightLoadOrder, n);
      }
      expect(btn(Icons.chevron_right).onPressed, isNull, reason: '마지막 스텝');
      await tester.tap(stepButton(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('STEP 5 / 6'), findsOneWidget);

      await tester.tap(find.byTooltip('스텝뷰 닫기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('STEP '), findsNothing);
      expect(painterOf(tester).highlightLoadOrder, isNull);
      await flushAutosave(tester);
    });

    for (final entry in const {
      '데스크톱 1280×960': kDesktop,
      '폰 390×844': kPhone,
      '폰 가로 844×390': Size(844, 390),
    }.entries) {
      testWidgets('스텝 뷰 컨트롤은 단계가 바뀌어도 버튼이 제자리에 있다 — ${entry.key}',
          (tester) async {
        await pumpApp(tester, size: entry.value, prefs: seenPrefs());
        await addBundle(tester, '2인 미니멀 캠핑'); // 라벨 길이가 제각각
        await flushSnackBars(tester);
        if (find.text('적재 순서 가이드').evaluate().isNotEmpty) {
          await tester.ensureVisible(find.text('적재 순서 가이드'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('적재 순서 가이드'));
        } else {
          await tester.tap(find.byTooltip('적재 순서 가이드')); // 압축 패널
        }
        await tester.pumpAndSettle();

        Rect rectOf(Finder f) => tester.getRect(f);
        final close = find.byTooltip('스텝뷰 닫기');
        final prev = find.byTooltip('이전 단계');
        final next = find.byTooltip('다음 단계');
        final first = (rectOf(close), rectOf(prev), rectOf(next));
        final names = <String>{};
        for (var n = 1; n <= 9; n++) {
          expect(find.text('STEP $n / 9'), findsOneWidget);
          expect((rectOf(close), rectOf(prev), rectOf(next)), first,
              reason: 'STEP $n 에서 버튼이 움직였다');
          names.add(boxesOf(tester).firstWhere((b) => b.loadOrder == n).label);
          if (n < 9) {
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
        }
        expect(names.length, greaterThan(3), reason: '서로 다른 길이의 이름을 거쳤다');

        // ✕ 는 ‹ › 와 떨어져 있다 (구분선 포함 16px 이상)
        expect(first.$2.left - first.$1.right, greaterThanOrEqualTo(16));
        // 버튼 크기
        expect(first.$2.size, const Size(40, 40));
        expect(first.$3.size, const Size(40, 40));

        // 왼쪽 아래 캔버스 캡션·상태 표시(아래 72px)와 오른쪽 위 적재율 카드를 가리지 않는다
        final canvas = canvasRect(tester);
        final control = rectOf(find
            .ancestor(of: close, matching: find.byType(Container))
            .first);
        expect(control.bottom, lessThan(canvas.bottom - 72));
        expect(canvas.contains(control.topLeft), isTrue);
        expect(canvas.contains(control.bottomRight), isTrue);
        final card = rectOf(find
            .ancestor(of: find.text('적재율 '), matching: find.byType(Container))
            .first);
        expect(control.overlaps(card), isFalse, reason: '$control vs $card');

        if (entry.value == kDesktop) {
          // e2e 좌표 갱신용 (1280×960)
          final label = rectOf(find.text('STEP 9 / 9'));
          debugPrint('STEP-VIEW-COORDS close=${first.$1.center} '
              'prev=${first.$2.center} next=${first.$3.center} '
              'labelRegion=${Rect.fromLTRB(first.$2.right, control.top, first.$3.left, control.bottom)} '
              'stepText=$label control=$control');
        }
        await flushAutosave(tester);
      });
    }

    testWidgets('스텝 뷰는 Ctrl+Z 로도 빠져나온다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 / 6'), findsOneWidget);
      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(find.textContaining('STEP '), findsNothing);
      await flushAutosave(tester);
    });

    testWidgets('스텝 뷰 도중 짐을 모두 지우면 스텝 뷰가 닫힌다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '하나', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);
      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 / 1'), findsOneWidget);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();
      expect(boxesOf(tester), isEmpty);
      expect(find.textContaining('STEP '), findsNothing);
      await flushAutosave(tester);
    });

    testWidgets('짐을 지운 뒤 스텝 뷰에 빈 스텝이 없다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      // 적재 순서 2번 짐을 지운다
      final victim = boxesOf(tester).firstWhere((b) => b.loadOrder == 2);
      final idx = boxesOf(tester).indexOf(victim);
      await tester.tap(find.byTooltip('삭제').at(idx));
      await tester.pumpAndSettle();
      expect(boxesOf(tester), hasLength(5));

      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      final maxStep = int.parse(RegExp(r'STEP 1 / (\d+)')
          .firstMatch(allTexts(tester).firstWhere((t) => t.startsWith('STEP')))!
          .group(1)!);
      expect(maxStep, 5, reason: '남은 짐 5개 = 5 스텝');
      await flushAutosave(tester);
    });
  });
}
