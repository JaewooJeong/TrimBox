// SimulatorScreen 위젯 플로우 테스트 — 이름 저장/불러오기, 자동 저장 복원, 구버전·손상 데이터.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/file_io.dart' as file_io;

import 'sim_harness.dart';

typedef _Pose = (String, double, double, double, int);

List<_Pose> _poses(WidgetTester tester) =>
    [for (final b in boxesOf(tester)) (b.id, b.x, b.y, b.z, b.rotY)];

void _expectSamePoses(List<_Pose> actual, List<_Pose> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].$1, expected[i].$1);
    expect(actual[i].$2, closeTo(expected[i].$2, 1e-6), reason: '${expected[i].$1}.x');
    expect(actual[i].$3, closeTo(expected[i].$3, 1e-6), reason: '${expected[i].$1}.y');
    expect(actual[i].$4, closeTo(expected[i].$4, 1e-6), reason: '${expected[i].$1}.z');
    expect(actual[i].$5, expected[i].$5);
  }
}

/// 2026-09-16 이전 버전이 저장하던 형식: 옛 쏘렌토(1.08×1.10×0.78), 개구부·단면·2열
/// 슬라이드 없음, 박스에 무게·연질 필드 없음.
String _legacyAutosave() {
  Map<String, dynamic> box(String id, String label, double w, double d, double h,
          double x, double y, double z,
          {bool upright = false}) =>
      {
        'id': id,
        'label': label,
        'size': {'w': w, 'd': d, 'h': h},
        'pos': {'x': x, 'y': y, 'z': z},
        'rotY': 0,
        'color': 0xFFBAE1FF,
        'category': 2,
        if (upright) 'upright': true,
      };
  return json.encode({
    'version': '1.0.0',
    'space': {
      'w': 1.08,
      'd': 1.10,
      'h': 0.78,
      'wheelhouse': {
        'left': {'w': 0.08, 'd': 0.48, 'h': 0.30},
        'right': {'w': 0.08, 'd': 0.48, 'h': 0.30},
      },
      'seatSplitRatio': [0.6, 0.4],
      'taperRatio': 0.07,
      'ceilingDrop': 0.12,
      'rearTopNarrow': 0.05,
      'vehicleName': 'SORENTO 5인승',
      'bodyWidth': 1.44,
      'trunkLipHeight': 0.58,
      'roofExtension': 0.12,
      'bumperDepth': 0.07,
      'bodyDepth': 0.60,
      'bodyColor': 0xFF1C2526,
    },
    'grid': 0.01,
    'boxes': [
      // 옛 트렁크(휠하우스 폭 8cm)에서는 유효했던 자리 — 새 휠하우스(14.5cm)와 겹친다
      box('box-001', '대형 아이스박스 (50L)', 0.60, 0.40, 0.42, 0.08, 0, 0.0,
          upright: true),
      box('box-002', '일반 침낭 (3계절)', 0.26, 0.40, 0.26, 0.70, 0, 0.0),
      box('box-003', '코베아 슬림트윈 투버너', 0.55, 0.35, 0.12, 0.08, 0, 0.50),
      box('box-007', '롤테이블 (4인/120cm)', 0.90, 0.17, 0.16, 0.08, 0, 0.90),
    ],
  });
}

void main() {
  setUpAll(loadRealFonts);

  group('9a. 이름으로 저장 / 불러오기', () {
    testWidgets('저장 → 짐 삭제 → 불러오기로 그대로 복원', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      final saved = _poses(tester);

      await tester.tap(find.byTooltip('배치 저장'));
      await tester.pumpAndSettle();
      expect(find.text('배치 저장'), findsOneWidget); // 다이얼로그 제목
      final nameField = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(tester.widget<TextField>(nameField).controller!.text,
          '쏘렌토 5인승 - 6개 적재');
      await tester.enterText(nameField, '주말 캠핑');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(snackTexts(tester).join(), contains('"주말 캠핑" 저장 완료'));
      await flushSnackBars(tester);

      // 두 개 지운다
      await tester.tap(find.byTooltip('삭제').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('삭제').first);
      await tester.pumpAndSettle();
      expect(boxesOf(tester), hasLength(4));

      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('저장된 배치 불러오기'), findsOneWidget);
      expect(find.text('주말 캠핑'), findsOneWidget);
      expect(find.textContaining('쏘렌토 5인승 | 6개 | '), findsOneWidget);
      await tester.tap(find.text('주말 캠핑'));
      await tester.pumpAndSettle();

      expect(snackTexts(tester).join(), contains('6개 박스를 불러왔습니다'));
      _expectSamePoses(_poses(tester), saved);
      expectSceneValid(tester);
      await flushAutosave(tester);
    });

    testWidgets('같은 이름으로 다시 저장하면 덮어쓰기 확인', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '박스', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);

      Future<void> save() async {
        await tester.tap(find.byTooltip('배치 저장'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.byType(TextField)),
            '같은 이름');
        await tester.tap(find.text('저장'));
        await tester.pumpAndSettle();
      }

      await save();
      await flushSnackBars(tester);
      await save();
      expect(find.text('배치 덮어쓰기'), findsOneWidget);
      expect(find.textContaining("'같은 이름' 배치가 이미 존재합니다"), findsOneWidget);
      // 취소하면 저장하지 않는다
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      await save();
      await tester.tap(find.text('덮어쓰기'));
      await tester.pumpAndSettle();
      expect(snackTexts(tester).join(), contains('"같은 이름" 저장 완료'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('trimbox_scene_')),
          hasLength(1));
      await flushAutosave(tester);
    });

    testWidgets('짐이 없으면 저장 다이얼로그 대신 안내 스낵바 ("0개 적재" 를 저장하지 않는다)',
        (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(find.byTooltip('배치 저장'));
      await tester.pumpAndSettle();
      expect(find.text('배치 이름'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(snackTexts(tester).join(), contains('저장할 짐이 없습니다'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('trimbox_scene_')), isEmpty);
    });

    testWidgets('빈 이름·취소는 저장하지 않는다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '박스', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);
      await tester.tap(find.byTooltip('배치 저장'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '   ');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('trimbox_scene_')), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await flushAutosave(tester);
    });

    testWidgets('저장 목록: 비어 있음 안내, 삭제 확인', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('저장된 배치가 없습니다'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      await addCustomBox(tester, label: '박스', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);
      await tester.tap(find.byTooltip('배치 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장')); // 기본 이름
      await tester.pumpAndSettle();
      await flushSnackBars(tester);

      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('쏘렌토 5인승 - 1개 적재'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.byTooltip('삭제')));
      await tester.pumpAndSettle();
      expect(find.text('배치 삭제'), findsOneWidget);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('저장된 배치가 없습니다'), findsOneWidget);
      await flushAutosave(tester);
    });

    testWidgets('7인승 + 2열 +13cm 로 저장한 배치를 새 세션에서 불러오면 차종·슬라이드도 복원',
        (tester) async {
      final boxes = [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ];
      final sceneStr =
          sceneJson(boxes, space: TrunkSpace.sorento7(seatSlide: 0.13));
      await pumpApp(tester,
          prefs: seenPrefs({
            'trimbox_scene_trip': sceneStr,
            'trimbox_meta_trip': json.encode({
              'name': 'trip',
              'date': '2026-09-17T10:00:00.000',
              'vehicle': '쏘렌토 7인승·3열 접음',
              'boxCount': 1,
            }),
          }));
      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-09-17 10:00'), findsOneWidget);
      await tester.tap(find.text('trip'));
      await tester.pumpAndSettle();

      // 차종 버튼: 7인승 + 2열을 당긴 만큼 늘어난 바닥 깊이
      final depthCm =
          (TrunkSpace.sorento7(seatSlide: 0.13).d * 100).round();
      expect(
          find.descendant(
              of: presetButton(),
              matching: find.textContaining('쏘렌토 7인승·3열 접음')),
          findsOneWidget);
      expect(
          find.descendant(
              of: presetButton(), matching: find.textContaining('×${depthCm}cm)')),
          findsOneWidget);
      expect(
          find.descendant(
              of: seatSlideControl(), matching: find.text('2열 중간 (+13cm)')),
          findsOneWidget);
      expect(spaceOf(tester).d,
          closeTo(TrunkSpace.sorento7(seatSlide: 0.13).d, 1e-9));
      expect(boxesOf(tester).single.label, '가');
      await flushAutosave(tester);
    });
  });

  group('9a-2. 파일·이미지 동작 (웹 외 플랫폼 = Android 와 같은 스텁)', () {
    testWidgets('지원하지 않는 플랫폼에서는 항상 실패하던 버튼을 숨기고, 이름 저장/불러오기는 그대로',
        (tester) async {
      expect(file_io.fileActionsSupported, isFalse,
          reason: '테스트 VM 은 file_io_stub 을 쓴다 (웹만 true)');
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '박스', w: 40, d: 30, h: 30);
      await flushSnackBars(tester);

      expect(find.byTooltip('스크린샷'), findsNothing);
      expect(find.byTooltip('공유 카드'), findsNothing);

      await tester.tap(find.byTooltip('배치 저장'));
      await tester.pumpAndSettle();
      expect(find.text('파일로 내보내기'), findsNothing);
      expect(find.text('저장'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('파일에서 불러오기'), findsNothing);
      expect(find.text('저장된 배치가 없습니다'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    });
  });

  group('9b. 자동 저장 → 재시작 복원', () {
    testWidgets('추가 후 자동 저장되고, 앱을 다시 띄우면 조용히 복원된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await flushAutosave(tester);
      final saved = _poses(tester);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kAutosaveKey);
      expect(raw, isNotNull);
      expect((json.decode(raw!) as Map)['boxes'], hasLength(6));

      await restartApp(tester);
      expect(find.byType(SnackBar), findsNothing, reason: '조용한 복원');
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
      expect(find.text('박스: 6개'), findsOneWidget);
      _expectSamePoses(_poses(tester), saved);
      // 물리 속성도 유지
      expect(boxesOf(tester).every((b) => b.weightKg > 0), isTrue);
      expectSceneValid(tester);
      await flushAutosave(tester);
    });

    testWidgets('손으로 옮긴 자리·회전·2열 슬라이드도 복원된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '박스', w: 50, d: 30, h: 30);
      await flushSnackBars(tester);
      await tester.tap(find.byTooltip('90° 회전'));
      await tester.pumpAndSettle();
      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2열 최전방 (+27cm)'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
      final saved = _poses(tester);

      await restartApp(tester);
      _expectSamePoses(_poses(tester), saved);
      expect(boxesOf(tester).single.rotY, 90);
      expect(spaceOf(tester).seatSlide, closeTo(0.27, 1e-9));
      expect(
          find.descendant(
              of: seatSlideControl(),
              matching: find.text('2열 최전방 (+27cm)')),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await flushAutosave(tester);
    });

    testWidgets('커스텀 트렁크도 복원된다 (2열 컨트롤 없음)', (tester) async {
      await pumpAppWithScene(
          tester,
          [mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20)],
          space: TrunkSpace.custom(w: 1.2, d: 0.9, h: 0.7));
      expect(find.text('커스텀 (120×90cm)'), findsOneWidget);
      expect(seatSlideControl(), findsNothing);
      expect(boxesOf(tester), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('메뉴에 없는 차종(투싼) 자동 저장도 예외 없이 복원된다', (tester) async {
      await pumpAppWithScene(
          tester,
          [mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20)],
          space: TrunkSpace.tucson());
      expect(tester.takeException(), isNull);
      expect(find.text(TrunkPreset.tucson.label), findsOneWidget);
      expect(seatSlideControl(), findsNothing);
      // 메뉴를 열어도 예외 없음, 여전히 3개만
      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      expect(presetMenuItem(TrunkPreset.sorento), findsOneWidget);
      expect(presetMenuItem(TrunkPreset.sorento7), findsOneWidget);
      expect(presetMenuItem(TrunkPreset.custom), findsOneWidget);
      expect(presetMenuItem(TrunkPreset.tucson), findsNothing);
    });

    testWidgets('변경 직후(자동 저장 대기 800ms 안)에 앱이 내려가도 마지막 변경이 저장된다',
        (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '박스', w: 50, d: 30, h: 30);
      await flushSnackBars(tester);
      await flushAutosave(tester);
      await tester.tap(find.byTooltip('90° 회전'));
      await tester.pump(const Duration(milliseconds: 100)); // 타이머가 아직 안 돌았다
      await restartApp(tester);
      expect(boxesOf(tester).single.rotY, 90);
    });

    testWidgets('빈 트렁크 자동 저장은 빈 상태로 (온보딩은 본 적 있으면 없음)', (tester) async {
      await pumpAppWithScene(tester, []);
      expect(boxesOf(tester), isEmpty);
      expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
    });

    testWidgets('자동 복원 뒤에도 적재 순서 가이드를 쓸 수 있다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await flushAutosave(tester);
      expect(find.text('적재 순서 가이드'), findsOneWidget);
      final orders = [for (final b in boxesOf(tester)) b.loadOrder];
      final raw = (await SharedPreferences.getInstance()).getString(kAutosaveKey)!;
      expect(
          [for (final b in (json.decode(raw) as Map)['boxes'] as List) b['order']],
          orders);
      await restartApp(tester);
      expect(find.text('적재 순서 가이드'), findsOneWidget);
      expect([for (final b in boxesOf(tester)) b.loadOrder], orders);
    });
  });

  group('9c. 구버전 자동 저장', () {
    testWidgets('옛 쏘렌토 치수 → 현재 프리셋으로 바꾸고 다시 배치한다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs({kAutosaveKey: _legacyAutosave()}));
      expect(tester.takeException(), isNull);

      final s = spaceOf(tester);
      // 현재 쏘렌토 프리셋 (2026-09-17 기준 1.38 × 1.07 × 0.82)
      final ref = TrunkSpace.sorento();
      expect((s.w, s.d, s.h), (ref.w, ref.d, ref.h));
      expect(s.w, isNot(1.08), reason: '옛 치수가 남으면 안 된다');
      expect(s.hasTailgateModel, isTrue, reason: '개구부·테일게이트 모델이 붙는다');
      expect(s.seatSlide, 0);
      expect(find.text(TrunkPreset.sorento.label), findsOneWidget);
      expect(find.text('2열 최후방'), findsOneWidget);

      expect(boxesOf(tester).map((b) => b.id),
          ['box-001', 'box-002', 'box-003', 'box-007']);
      // 다시 배치했고 전부 들어간다
      expect(snackTexts(tester).join(), contains('4개 배치 완료'));
      expect(insideBoxes(tester), hasLength(4));
      expectSceneValid(tester);
      expect(boxesOf(tester).every((b) => b.loadOrder != null), isTrue);
      expect(statusOf(tester), isNot(StatusState.problems));
      // 세움 속성은 구버전에도 있었다
      expect(boxesOf(tester).first.keepUpright, isTrue);

      // 새 박스 id 는 기존 최대 번호 다음
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '새 박스', w: 30, d: 30, h: 30);
      expect(boxesOf(tester).last.id, 'box-008');
      await flushAutosave(tester);

      // 새 형식으로 자동 저장된다
      final prefs = await SharedPreferences.getInstance();
      final space = (json.decode(prefs.getString(kAutosaveKey)!) as Map)['space'] as Map;
      expect(space['w'], TrunkSpace.sorento().w);
      expect(space.containsKey('aperture'), isTrue);
    });

    testWidgets('구버전 짐에도 장비 DB 의 무게·연질 속성이 채워진다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs({kAutosaveKey: _legacyAutosave()}));
      final cooler =
          boxesOf(tester).firstWhere((b) => b.label == '대형 아이스박스 (50L)');
      final bag = boxesOf(tester).firstWhere((b) => b.label == '일반 침낭 (3계절)');
      expect(cooler.weightKg, greaterThan(0));
      expect(cooler.accessPriority, isTrue);
      expect(bag.soft, isTrue);
    });
  });

  group('9d. 손상된 저장 데이터', () {
    const corrupt = <String, String>{
      '깨진 JSON': '{"version": "1.0.0", "space": {',
      '빈 문자열': '',
      '배열': '[]',
      '문자열 JSON': '"hello"',
      'space 없음': '{"boxes": []}',
      'space 가 빈 맵': '{"space": {}, "boxes": []}',
      '박스에 size 없음':
          '{"space": {"w":1,"d":1,"h":1,"wheelhouse":{"left":{"w":0,"d":0,"h":0},"right":{"w":0,"d":0,"h":0}}}, "boxes": [{"id":"x"}]}',
      'null': 'null',
    };

    for (final e in corrupt.entries) {
      testWidgets('${e.key} → 시작 시 예외 없이 빈 상태, 이후 정상 사용', (tester) async {
        await pumpApp(tester, prefs: seenPrefs({kAutosaveKey: e.value}));
        expect(tester.takeException(), isNull);
        expect(boxesOf(tester), isEmpty);
        expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
        expect(spaceOf(tester).w, closeTo(TrunkSpace.sorento().w, 1e-9));
        expect(find.byType(SnackBar), findsNothing, reason: '조용한 복원');
        // 읽을 수 없는 자동 저장은 버린다 (다음 실행에서 또 걸리지 않게)
        expect((await SharedPreferences.getInstance()).getString(kAutosaveKey),
            isNull);

        await addCustomBox(tester, label: '박스', w: 40, d: 30, h: 30);
        expect(boxesOf(tester), hasLength(1));
        await flushAutosave(tester);
        // 손상본은 정상 자동 저장으로 덮인다 (그 전에 이미 지워져 있다)
        final prefs = await SharedPreferences.getInstance();
        expect(
            (json.decode(prefs.getString(kAutosaveKey)!) as Map)['boxes'],
            hasLength(1));
      });
    }

    testWidgets('자동 저장 키의 타입이 다르면(문자열 아님) 조용히 무시', (tester) async {
      await pumpApp(tester, prefs: {kOnboardedKey: true, kAutosaveKey: 12345});
      expect(tester.takeException(), isNull);
      expect(boxesOf(tester), isEmpty);
      expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
    });

    testWidgets('이상한 박스(크기 0, 트렁크보다 큼, 음수 좌표)도 그리기·판정에서 예외 없음',
        (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '크기 0', w: 0, d: 0, h: 0),
        mkBox('box-002', '거대', w: 3, d: 3, h: 3),
        mkBox('box-003', '음수', w: 0.3, d: 0.3, h: 0.3, x: -5, z: -5),
      ]);
      expect(tester.takeException(), isNull);
      expect(boxesOf(tester), hasLength(3));
      expect(statusOf(tester), StatusState.problems);
      // 판정도 예외 없이
      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('적재 가능'), findsWidgets);
      await flushAutosave(tester);
    });

    testWidgets('손상된 자동 저장은 시작할 때 오류 스낵바를 띄우지 않는다', (tester) async {
      await pumpApp(tester,
          prefs: seenPrefs({kAutosaveKey: '{"version": "1.0.0", "space": {'}));
      expect(snackTexts(tester), isEmpty);
    });

    testWidgets('손상된 이름 저장본은 목록에서 빠지거나, 눌러도 앱이 죽지 않는다', (tester) async {
      await pumpApp(tester,
          prefs: seenPrefs({
            'trimbox_meta_bad': '{not json',
            'trimbox_scene_bad': '{}',
            'trimbox_meta_bad2': json.encode({'name': '깨진 배치', 'boxCount': 3}),
            'trimbox_scene_bad2': '{"space": 1}',
          }));
      await tester.tap(find.byTooltip('불러오기'));
      await tester.pumpAndSettle();
      expect(find.text('깨진 배치'), findsOneWidget);
      await tester.tap(find.text('깨진 배치'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(snackTexts(tester).join(), contains('잘못된 파일 형식'));
      expect(boxesOf(tester), isEmpty);
    });
  });
}
