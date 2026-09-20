// SimulatorScreen 캔버스 조작 테스트 — 탭 선택, 박스 드래그, 적층, 카메라 회전·줌·패닝.
//
// 화면 좌표는 현재 카메라로 월드 좌표를 투영해 구한다 (고정 픽셀 좌표 없음).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/render3d/vec3.dart';

import 'sim_harness.dart';

void main() {
  setUpAll(loadRealFonts);

  group('캔버스 — 선택', () {
    testWidgets('박스를 탭하면 선택, 빈 바닥을 탭하면 해제', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
        mkBox('box-002', '나', w: 0.40, d: 0.40, h: 0.30, x: 0.80, z: 0.30),
      ]);
      final boxes = boxesOf(tester);
      await tester.tapAt(topCenterOf(tester, boxes[1]));
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, 'box-002');
      await tester.tapAt(topCenterOf(tester, boxes[0]));
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, 'box-001');
      // 두 박스 사이 빈 바닥 (테일게이트 쪽)
      await tester.tapAt(screenOf(tester, const Vec3(0.69, 0, 0.95)));
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, isNull);
    });

    testWidgets('스텝 뷰에서 아직 안 실은(숨은) 짐은 탭으로 잡히지 않는다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      final last = boxesOf(tester).firstWhere((b) => b.loadOrder == 6);
      await tester.tapAt(topCenterOf(tester, last));
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, isNot(last.id));
      await flushAutosave(tester);
    });
  });

  group('캔버스 — 박스 드래그', () {
    testWidgets('마우스로 끌면 바닥을 따라 움직이고, 놓으면 격자에 맞고, Ctrl+Z 로 되돌린다',
        (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
      ]);
      final b = boxesOf(tester).single;
      final from = topCenterOf(tester, b);
      // 같은 높이의 수평면에서 +0.40m 오른쪽 지점
      final to = screenOf(tester, Vec3(b.x + 0.20 + 0.40, b.top, b.z + 0.20));
      await slowDrag(tester, from, to - from);
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, 'box-001');
      // 드래그는 박스 바닥 높이 평면에 투영한다 → 윗면을 잡으면 시차만큼 덜/더 간다. 방향과 대략의 크기만 본다.
      expect(b.x, greaterThan(0.40));
      expect(b.x, lessThan(0.90));
      expect(b.y, 0);
      final unit = spaceOf(tester).gridUnit;
      expect((b.x / unit - (b.x / unit).round()).abs(), lessThan(1e-6), reason: '격자 스냅');
      expectSceneValid(tester);

      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await tester.pumpAndSettle();
      expect(boxesOf(tester).single.x, closeTo(0.20, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('경계 밖으로 끌어도 트렁크 안에 머문다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.50, z: 0.30),
      ]);
      final b = boxesOf(tester).single;
      final from = topCenterOf(tester, b);
      await slowDrag(tester, from, const Offset(900, 0));
      await tester.pumpAndSettle();
      expect(b.x, closeTo(spaceOf(tester).w - 0.40, 1e-6));
      await flushAutosave(tester);
    });

    testWidgets('다른 박스 위로 끌면 쌓인다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '받침', w: 0.50, d: 0.50, h: 0.25, x: 0.70, z: 0.30),
        mkBox('box-002', '위', w: 0.30, d: 0.30, h: 0.20, x: 0.15, z: 0.40),
      ]);
      final base = boxesOf(tester)[0];
      final top = boxesOf(tester)[1];
      final from = topCenterOf(tester, top);
      // 바닥 평면 기준으로 받침 한가운데
      final to = screenOf(tester,
          Vec3(base.x + 0.25, top.top, base.z + 0.25));
      await slowDrag(tester, from, to - from);
      await tester.pumpAndSettle();
      expect(top.y, closeTo(0.25, 1e-6), reason: 'x=${top.x} z=${top.z}');
      expectSceneValid(tester);
      await flushAutosave(tester);
    });

    testWidgets('손으로 끈 뒤에는 적재 순서가 지워지고, 추가해도 기존 자리를 건드리지 않는다',
        (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '첫 박스', w: 40, d: 40, h: 30);
      await flushSnackBars(tester);
      expect(find.text('적재 순서 가이드'), findsOneWidget);
      final b = boxesOf(tester).single;
      final from = topCenterOf(tester, b);
      final to = screenOf(tester, Vec3(b.x + 0.20 + 0.30, b.top, b.z + 0.20 + 0.30));
      await slowDrag(tester, from, to - from);
      await tester.pumpAndSettle();
      expect(b.loadOrder, isNull);
      expect(find.text('적재 순서 가이드'), findsNothing);
      // 처음 손으로 옮기면 "순서를 지웠어요" 안내가 한 번 뜬다
      expect(snackTexts(tester).join(), contains('적재 순서를 지웠어요'));
      await flushSnackBars(tester);
      final pos = (b.x, b.z);

      await addCustomBox(tester, label: '둘째 박스', w: 30, d: 30, h: 30);
      expect(find.byType(SnackBar), findsNothing, reason: '자동 재배치 없음');
      expect((boxesOf(tester).first.x, boxesOf(tester).first.z), pos);
      expect(boxesOf(tester), hasLength(2));
      expectSceneValid(tester);
      await flushAutosave(tester);
    });

    testWidgets('터치로 좁은 짐(폭 15cm)도 짧은 축 방향으로 끌 수 있다 (슬롭 뒤 위치가 박스 밖이어도)',
        (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '의자', w: 0.15, d: 0.85, h: 0.20, x: 0.60, z: 0.10),
      ], size: kTablet);
      final b = boxesOf(tester).single;
      final yaw0 = painterOf(tester).camera.yaw;
      final from = topCenterOf(tester, b);
      await slowDrag(tester, from, const Offset(120, 0),
          kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(painterOf(tester).camera.yaw, closeTo(yaw0, 1e-9),
          reason: '카메라가 돌면 안 된다');
      expect(b.x, greaterThan(0.65), reason: '박스가 따라와야 한다');
      await flushAutosave(tester);
    });
  });

  group('캔버스 — 카메라', () {
    testWidgets('빈 곳을 끌면 회전(제한 있음), 휠은 줌(제한 있음), 0 으로 초기화', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
      ]);
      final r = canvasRect(tester);
      final cam0 = painterOf(tester).camera;
      // 캔버스 왼쪽 위 구석(트렁크 밖 배경)에서 시작
      final start = r.topLeft + const Offset(30, 60);
      await slowDrag(tester, start, const Offset(200, 40));
      await tester.pumpAndSettle();
      final cam1 = painterOf(tester).camera;
      expect(cam1.yaw, isNot(closeTo(cam0.yaw, 1e-6)));
      expect(cam1.pitch, greaterThan(cam0.pitch));
      // 박스는 그대로
      expect(boxesOf(tester).single.x, closeTo(0.20, 1e-9));

      // 아주 멀리 끌어도 각도 제한 안
      await slowDrag(tester, start, const Offset(1200, 800));
      await tester.pumpAndSettle();
      final cam2 = painterOf(tester).camera;
      expect(cam2.yaw.abs(), lessThanOrEqualTo(85 * 3.1415927 / 180 + 1e-6));
      expect(cam2.pitch, lessThanOrEqualTo(75 * 3.1415927 / 180 + 1e-6));

      // 휠 줌
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(r.center));
      final d0 = painterOf(tester).camera.distance;
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();
      expect(painterOf(tester).camera.distance, lessThan(d0));
      for (var i = 0; i < 60; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      }
      await tester.pump();
      final far = painterOf(tester).camera.distance;
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(painterOf(tester).camera.distance, closeTo(far, 1e-9), reason: '최대 줌아웃 제한');

      await pressKey(tester, LogicalKeyboardKey.digit0, character: '0');
      final cam3 = painterOf(tester).camera;
      expect(cam3.yaw, closeTo(cam0.yaw, 1e-9));
      expect(cam3.pitch, closeTo(cam0.pitch, 1e-9));
      expect(cam3.distance, closeTo(cam0.distance, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('우클릭 드래그는 패닝', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
      ]);
      final r = canvasRect(tester);
      final g = await tester.startGesture(r.center,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await g.moveBy(const Offset(60, -30));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(painterOf(tester).camera.pan, const Offset(60, -30));
      expect(boxesOf(tester).single.x, closeTo(0.20, 1e-9));
    });

    testWidgets('창 크기가 바뀌어도 (데스크톱 → 폰 → 데스크톱) 예외 없이 다시 맞춘다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
      ]);
      final d0 = painterOf(tester).camera.distance;
      tester.view.physicalSize = kTablet;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = kDesktop;
      await tester.pumpAndSettle();
      expect(painterOf(tester).camera.distance, closeTo(d0, 1e-6));
      expect(boxesOf(tester), hasLength(1));
    });
  });
}
