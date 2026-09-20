// SimulatorScreen 위젯 플로우 테스트 — 첫 실행, 장비 추가, 빠른 판정, 2열 슬라이드, 차종 메뉴.
//
// 웹 E2E(캔버스·좌표 클릭)와 달리 실제 위젯을 찾아 누르고 문구·상태를 검증한다.
// 픽셀 좌표에 의존하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimbox/main.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';
import 'package:trimbox/widgets/box_list_panel.dart';
import 'package:trimbox/widgets/trunk_size_dialog.dart';

import 'sim_harness.dart';

const _family = '4인 가족 캠핑';
const _duo = '2인 미니멀 캠핑';
const _solo = '솔로 백패킹';

/// 2열 최후방에서는 안 들어가지만 2열을 당기면 (작은 박스 하나와 함께) 들어가는 긴 짐을
/// 엔진으로 찾는다. 프리셋 치수가 바뀌어도 테스트가 따라가도록 고정값을 쓰지 않는다.
/// 앱의 _suggestSeatSlide 와 같은 순서(+13 → +27)로 첫 성공 단계를 고른다.
({int wCm, int dCm, int hCm, double slide})? _findSlideOnlyLoad() {
  final base = TrunkSpace.sorento();
  List<TrimBox> boxes(int w, int d, int h) => [
        mkBox('box-001', '작은 박스', w: 0.30, d: 0.30, h: 0.20),
        mkBox('box-002', '긴 짐', w: w / 100, d: d / 100, h: h / 100),
      ];
  final baseCm = (base.d * 100).round();
  for (final extra in [5, 8, 10, 15, 20]) {
    for (final w in [100, 90, 80]) {
      const h = 25;
      final d = baseCm + extra;
      final r0 = AutoLayoutEngine.computeLayout(base, boxes(w, d, h),
          restarts: 24, budget: const Duration(milliseconds: 2500));
      if (r0.allBoxesFit || r0.placements.length != 1) continue;
      for (final slide in [0.13, sorentoSeatSlideMax]) {
        final r = AutoLayoutEngine.computeLayout(
            TrunkSpace.sorento(seatSlide: slide), boxes(w, d, h),
            restarts: 12, budget: const Duration(milliseconds: 1500));
        if (r.allBoxesFit) return (wCm: w, dCm: d, hCm: h, slide: slide);
      }
    }
  }
  return null;
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(AddBoxDialog), matching: f);

void main() {
  setUpAll(loadRealFonts);

  group('1. 첫 실행', () {
    testWidgets('온보딩이 보이고 탭하면 닫히며 본 적 있음으로 저장된다', (tester) async {
      await pumpApp(tester);
      expect(find.text('박스를 추가하여\n시뮬레이션을 시작하세요'), findsOneWidget);
      expect(find.text('아무 곳이나 탭하여 닫기'), findsOneWidget);

      await tester.tap(find.text('아무 곳이나 탭하여 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kOnboardedKey), isTrue);

      // 다시 띄우면 온보딩이 없다
      await restartApp(tester);
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
      expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
    });

    const mouseOnly = ['마우스 휠', '우클릭 드래그', 'R', '?'];
    const touchOnly = ['한 손가락 드래그', '두 손가락', '짐을 탭', '시트 도구 줄'];

    testWidgets('데스크톱(마우스·키보드)에서는 마우스·단축키 조작법을 보여준다', (tester) async {
      await pumpApp(tester, size: kDesktop);
      for (final t in mouseOnly) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      for (final t in touchOnly) {
        expect(find.text(t), findsNothing, reason: t);
      }
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('터치 기기(Android·iOS)에서는 터치 제스처를 보여준다 — 마우스·키 안내 없음',
        (tester) async {
      await pumpApp(tester, size: kPhone);
      for (final t in touchOnly) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('도구 띠로 회전·삭제'), findsOneWidget);
      expect(find.text('확대·이동'), findsOneWidget);
      for (final t in mouseOnly) {
        expect(find.text(t), findsNothing, reason: t);
      }
    }, variant: TargetPlatformVariant.mobile());

    testWidgets('데스크톱 OS 라도 폰 크기 화면(모바일 웹 에뮬레이션 등)이면 터치 안내', (tester) async {
      await pumpApp(tester, size: kPhone);
      expect(find.text('한 손가락 드래그'), findsOneWidget);
      expect(find.text('마우스 휠'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('빈 상태 CTA 가 장비 선택 다이얼로그를 연다', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('아무 곳이나 탭하여 닫기'));
      await tester.pumpAndSettle();
      expect(find.text('캠핑 장비를 선택하고\n트렁크에 들어가는지 확인하세요'),
          findsOneWidget);
      await tester.tap(find.text('캠핑 장비 선택하기'));
      await tester.pumpAndSettle();
      expect(find.byType(AddBoxDialog), findsOneWidget);
      // 취소하면 아무것도 추가되지 않는다
      await tester.tap(_inDialog(find.text('취소')));
      await tester.pumpAndSettle();
      expect(find.byType(AddBoxDialog), findsNothing);
      expect(boxesOf(tester), isEmpty);
    });

    testWidgets('온보딩을 닫지 않고 바로 장비를 추가해도 온보딩이 사라지고 저장된다',
        (tester) async {
      await pumpApp(tester);
      await addBundle(tester, _solo);
      expect(boxesOf(tester), hasLength(6));
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kOnboardedKey), isTrue);
      await flushAutosave(tester);
    });

    testWidgets('온보딩을 이미 본 사용자에게는 첫 프레임에도 온보딩이 비치지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues(seenPrefs());
      tester.view.physicalSize = kDesktop;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(TrimBoxApp(key: UniqueKey()));
      expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('빈 상태에서는 판정·자동배치 버튼이 없고 앱바에 차종/2열 컨트롤이 있다',
        (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      expect(find.text('들어갈까?'), findsNothing);
      expect(find.text('자동 배치'), findsNothing);
      expect(find.text('적재 순서 가이드'), findsNothing);
      expect(find.text('TrimBox'), findsOneWidget);
      expect(find.text(TrunkPreset.sorento.label), findsOneWidget);
      expect(seatSlideControl(), findsOneWidget);
      expect(find.text('2열 최후방'), findsOneWidget);
      // 현재 쏘렌토 프리셋 치수
      final s = spaceOf(tester);
      final ref = TrunkSpace.sorento();
      expect((s.w, s.d, s.h), (ref.w, ref.d, ref.h));
      expect(s.vehicleName, ref.vehicleName);
      expect(s.hasTailgateModel, isTrue);
    });
  });

  group('2. 장비 추가 다이얼로그', () {
    testWidgets('추천 세트 카드 3종이 있다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      expect(_inDialog(find.text('추천 세트')), findsOneWidget);
      expect(_inDialog(find.text(_duo)), findsOneWidget);
      expect(_inDialog(find.text(_family)), findsOneWidget);
      expect(_inDialog(find.text(_solo)), findsOneWidget);
      expect(_inDialog(find.text('9개 장비')), findsOneWidget);
      expect(_inDialog(find.text('16개 장비')), findsOneWidget);
      expect(_inDialog(find.text('6개 장비')), findsOneWidget);
      // 아무것도 고르지 않으면 추가 버튼은 비활성
      final btn = tester.widget<ButtonStyleButton>(find.ancestor(
          of: addConfirmButton(),
          matching: find.bySubtype<ButtonStyleButton>()));
      expect(btn.onPressed, isNull);
    });

    testWidgets('4인 가족 캠핑 → 16개 추가, 배지와 판정 스낵바', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.text(_family));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('16개 선택')), findsOneWidget);
      expect(_inDialog(find.text('추가 (16개)')), findsOneWidget);
      // 수량 표시: 의자 4, 침낭 4 (목록은 보이는 행만 만든다 → 내려가며 찾는다)
      final presetList = _inDialog(find.byType(ListView));
      var foundQty = false;
      for (var i = 0; i < 40 && !foundQty; i++) {
        foundQty = _inDialog(find.text('4')).evaluate().isNotEmpty;
        if (!foundQty) {
          await tester.drag(presetList, const Offset(0, -250));
          await tester.pumpAndSettle();
        }
      }
      expect(foundQty, isTrue, reason: '수량 4 표시');

      await tester.tap(addConfirmButton());
      await tester.pumpAndSettle();

      final boxes = boxesOf(tester);
      expect(boxes, hasLength(16));
      expect(find.text('박스: 16개'), findsOneWidget);
      expect(find.text('총 짐: 16개'), findsOneWidget);

      // 판정 스낵바
      final snack = snackTexts(tester).join('\n');
      expect(snack, matches(RegExp(r'(\d+/16개 배치|16개 배치 완료)')));
      expect(snack, contains('적재율'));
      final m = RegExp(r'(\d+)/16개 배치').firstMatch(snack);
      if (m != null) {
        // 못 넣은 짐은 사유와 함께 나온다
        expect(snack, contains('적재 불가: '));
        expect(snack, contains(' — '));
        final placed = int.parse(m.group(1)!);
        expect(insideBoxes(tester), hasLength(placed));
      } else {
        expect(insideBoxes(tester), hasLength(16));
      }

      // 물리 속성이 장비 DB 에서 채워졌다
      expect(boxes.every((b) => b.weightKg > 0), isTrue);
      expect(boxes.where((b) => b.soft), isNotEmpty);
      expect(boxes.where((b) => b.keepUpright), isNotEmpty);
      expect(boxes.where((b) => b.accessPriority), isNotEmpty);

      // 목록 배지 (ListView 는 보이는 타일만 만든다 → 끝까지 스크롤하며 모은다)
      final seen = <String>{};
      final list = find.descendant(
          of: find.byType(BoxListPanel), matching: find.byType(Scrollable));
      for (var i = 0; i < 12; i++) {
        seen.addAll(allTexts(tester).where((t) => t.contains(' × ')));
        await tester.drag(list.first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final badges = seen.join('\n');
      expect(badges, contains('kg'));
      expect(badges, anyOf(contains('연질'), contains('눌림')));
      expect(badges, contains('세움'));
      expect(badges, contains('자주 꺼냄'));

      // 트렁크 안에 들어간 짐은 전부 유효 (충돌 0)
      final det = CollisionDetector(spaceOf(tester));
      for (final b in insideBoxes(tester)) {
        expect(det.describe(b, boxes), isEmpty, reason: b.label);
        expect(b.loadOrder, isNotNull, reason: '${b.label} 적재 순서');
      }
      await flushAutosave(tester);
    });

    testWidgets('검색이 프리셋을 걸러낸다 (카테고리 무시)', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      final search = _inDialog(find.byType(TextField));
      expect(search, findsOneWidget);
      await tester.enterText(search, '헬리녹스');
      await tester.pumpAndSettle();
      var rows = presetRowLabels(tester);
      expect(rows, isNotEmpty);
      expect(rows.every((l) => l.contains('헬리녹스') || l.toLowerCase().contains('helinox')),
          isTrue, reason: '$rows');

      // 캐리어 카테고리 항목도 캠핑 탭에서 검색된다
      await tester.enterText(search, '캐리어');
      await tester.pumpAndSettle();
      rows = presetRowLabels(tester);
      expect(rows, isNotEmpty);
      // "캐리어" 는 카테고리 이름이기도 해서 캐리어 분류 전체(더플백·배낭 포함)가 나온다
      expect(rows.any((l) => l.contains('캐리어')), isTrue, reason: '$rows');
      expect(rows.any((l) => l.contains('더플백') || l.contains('배낭')), isTrue,
          reason: '분류 이름 검색: $rows');

      // 검색 결과 하나를 골라 추가
      await tester.enterText(search, '헬리녹스 체어원');
      await tester.pumpAndSettle();
      await tester.tap(dialogLabel('헬리녹스 체어원'));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('1개 선택')), findsOneWidget);
      await tester.tap(addConfirmButton());
      await tester.pumpAndSettle();
      expect(boxesOf(tester).single.label, '헬리녹스 체어원');
      expect(snackTexts(tester).join(), contains('1개 배치 완료'));
      await flushAutosave(tester);
    });

    testWidgets('결과 없는 검색어는 "항목이 없습니다" 를 보여준다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.enterText(_inDialog(find.byType(TextField)), 'zzzz없는장비');
      await tester.pumpAndSettle();
      expect(_inDialog(find.byType(Checkbox)), findsNothing);
      expect(_inDialog(find.text('항목이 없습니다')), findsOneWidget);
    });

    testWidgets('검색 지우기 버튼이 목록을 되돌린다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.enterText(_inDialog(find.byType(TextField)), '헬리녹스');
      await tester.pumpAndSettle();
      expect(_inDialog(find.text(_family)), findsNothing,
          reason: '검색 중에는 결과가 바로 보이게 추천 세트를 접는다');
      await tester.tap(_inDialog(find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(_inDialog(find.byType(TextField)));
      expect(field.controller!.text, isEmpty);
      expect(presetRowLabels(tester).any((l) => !l.contains('헬리녹스') && !l.toLowerCase().contains('helinox')), isTrue,
          reason: '필터가 풀려 다른 장비가 다시 보인다');
      expect(_inDialog(find.text(_family)), findsOneWidget, reason: '세트도 다시 보인다');
    });

    testWidgets('세트가 수량을 채운다: 같은 장비 여러 개가 각각 박스가 된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _duo);
      final boxes = boxesOf(tester);
      expect(boxes, hasLength(9));
      expect(boxes.where((b) => b.label == '헬리녹스 체어원'), hasLength(2));
      expect(boxes.where((b) => b.label == '다운침낭 (경량)'), hasLength(2));
      expect(boxes.map((b) => b.id).toSet(), hasLength(9), reason: 'id 중복 없음');
      await flushAutosave(tester);
    });

    testWidgets('개별 장비의 수량을 늘릴 수 있다 (수량 스테퍼)', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.enterText(
          _inDialog(find.byType(TextField)), '헬리녹스 체어원');
      await tester.pumpAndSettle();
      await tester.tap(dialogLabel('헬리녹스 체어원'));
      await tester.pumpAndSettle();
      // 수량 +1
      await tester.tap(_inDialog(find.byTooltip('수량 늘리기')));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('2개 선택')), findsOneWidget);
      await tester.tap(_inDialog(find.byTooltip('수량 늘리기')));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('추가 (3개)')), findsOneWidget);
      await tester.tap(_inDialog(find.byTooltip('수량 줄이기')));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('2개 선택')), findsOneWidget);

      await tester.tap(addConfirmButton());
      await tester.pumpAndSettle();
      expect(boxesOf(tester).map((b) => b.label),
          ['헬리녹스 체어원', '헬리녹스 체어원']);
      expect(boxesOf(tester).map((b) => b.id).toSet(), hasLength(2));
      expect(snackTexts(tester).join(), contains('2개 배치 완료'));
      await flushAutosave(tester);
    });

    testWidgets('수량 1 에서 − 를 누르면 선택이 풀리고, 9개에서 + 는 멈춘다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.enterText(
          _inDialog(find.byType(TextField)), '헬리녹스 체어원');
      await tester.pumpAndSettle();
      await tester.tap(dialogLabel('헬리녹스 체어원'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        final plus = tester.widget<IconButton>(find.ancestor(
            of: _inDialog(find.byIcon(Icons.add)),
            matching: find.byType(IconButton)));
        if (plus.onPressed == null) break;
        await tester.tap(_inDialog(find.byTooltip('수량 늘리기')));
        await tester.pumpAndSettle();
      }
      expect(_inDialog(find.text('9개 선택')), findsOneWidget);
      for (var i = 0; i < 9; i++) {
        await tester.tap(_inDialog(find.byTooltip('수량 줄이기')));
        await tester.pumpAndSettle();
      }
      expect(_inDialog(find.textContaining('개 선택')), findsNothing);
      expect(_inDialog(find.byTooltip('수량 줄이기')), findsNothing);
    });

    testWidgets('세트 두 개를 고른 뒤 하나를 해제해도 다른 세트는 온전하다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.text(_duo));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('9개 선택')), findsOneWidget);
      await tester.tap(find.text(_solo));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_solo)); // 해제
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('9개 선택')), findsOneWidget);
    });

    testWidgets('세트를 다시 누르면 선택이 해제되고, 선택 해제 버튼도 동작한다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.text(_solo));
      await tester.pumpAndSettle();
      expect(_inDialog(find.text('6개 선택')), findsOneWidget);
      await tester.tap(find.text(_solo));
      await tester.pumpAndSettle();
      expect(_inDialog(find.textContaining('개 선택')), findsNothing);

      await tester.tap(find.text(_solo));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog(find.text('선택 해제')));
      await tester.pumpAndSettle();
      expect(_inDialog(find.textContaining('개 선택')), findsNothing);
      expect(_inDialog(find.text('추가')), findsOneWidget);
    });

    testWidgets('직접 입력: 라벨과 cm 치수로 박스 하나 추가', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '내 박스', w: 50, d: 40, h: 30);
      final b = boxesOf(tester).single;
      expect(b.label, '내 박스');
      expect(b.w, closeTo(0.50, 1e-9));
      expect(b.d, closeTo(0.40, 1e-9));
      expect(b.h, closeTo(0.30, 1e-9));
      expect(find.text('내 박스'), findsOneWidget);
      expect(find.textContaining('50 × 40 × 30cm'), findsOneWidget);
      expect(snackTexts(tester).join(), contains('1개 배치 완료'));
      expect(statusOf(tester), StatusState.ok);
      await flushAutosave(tester);
    });

    testWidgets('직접 입력: 라벨을 비우면 "Box N", 잘못된 치수는 거부', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '직접 입력'));
      await tester.pumpAndSettle();
      // 직접 입력 모드에는 검색창이 없다
      expect(_inDialog(find.byIcon(Icons.search)), findsNothing);
      await tester.enterText(
          _inDialog(find.widgetWithText(TextField, '가로(cm)')), '0');
      await tester.tap(addConfirmButton());
      await tester.pumpAndSettle();
      expect(find.byType(AddBoxDialog), findsOneWidget, reason: '닫히지 않는다');
      expect(find.text('유효한 크기를 입력하세요'), findsOneWidget);
      expect(boxesOf(tester), isEmpty);

      await tester.enterText(
          _inDialog(find.widgetWithText(TextField, '가로(cm)')), '45');
      await tester.tap(addConfirmButton());
      await tester.pumpAndSettle();
      expect(boxesOf(tester).single.label, 'Box 1');
      await flushAutosave(tester);
    });

    testWidgets('직접 입력: 라벨 입력란은 문자 키보드를 쓴다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '직접 입력'));
      await tester.pumpAndSettle();
      final label = tester
          .widget<TextField>(_inDialog(find.widgetWithText(TextField, '라벨')));
      expect(label.keyboardType, isNot(const TextInputType.numberWithOptions(decimal: true)));
    });

    testWidgets('두 번째 추가도 전체를 다시 자동 배치한다 (손댄 적 없을 때)', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      await addPresetBySearch(tester, '소형 아이스박스 (25L)');
      expect(boxesOf(tester), hasLength(7));
      expect(snackTexts(tester).join(), contains('7개 배치 완료'));
      expectSceneValid(tester);
      await flushAutosave(tester);
    });
  });

  group('3. 빠른 판정 "들어갈까?"', () {
    testWidgets('다 들어가면 "모두 적재 가능!" + 테일게이트 닫힘 + 순서 가이드', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      final before = [for (final b in boxesOf(tester)) (b.x, b.y, b.z, b.rotY)];

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.text('모두 적재 가능!'), findsOneWidget);
      expect(find.text('6개 모두 트렁크에 들어갑니다'), findsOneWidget);
      expect(find.text('닫힙니다 (닫힘 한계·개구부 반영)'), findsOneWidget);
      expect(find.text('적재 순서 (안쪽부터)'), findsOneWidget);
      expect(find.textContaining('만에 계산 완료'), findsOneWidget);
      expect(find.text('순서 가이드'), findsOneWidget);
      expect(find.text('배치 저장'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('모두 적재 가능!'), findsNothing);
      // 판정만 하고 배치는 건드리지 않는다
      final after = [for (final b in boxesOf(tester)) (b.x, b.y, b.z, b.rotY)];
      expect(after, before);
      await flushAutosave(tester);
    });

    testWidgets('판정 다이얼로그의 "순서 가이드" 가 스텝 뷰로 들어간다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('순서 가이드'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 / 6'), findsOneWidget);
      await flushAutosave(tester);
    });

    testWidgets('쏘렌토에 4인 세트: "모두 적재 가능!" 또는 "N/16개 적재 가능" + 못 넣은 목록·사유',
        (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _family);
      await flushSnackBars(tester);

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();

      final title = allTexts(tester).firstWhere(
          (t) => t == '모두 적재 가능!' || RegExp(r'^\d+/16개 적재 가능$').hasMatch(t),
          orElse: () => '');
      expect(title, isNotEmpty, reason: '판정 제목');
      expect(find.text('적재율'), findsOneWidget);
      expect(find.textContaining('만에 계산 완료'), findsOneWidget);

      if (title == '모두 적재 가능!') {
        expect(find.text('16개 모두 트렁크에 들어갑니다'), findsOneWidget);
        expect(find.textContaining('2열 시트를'), findsNothing);
        expect(find.text('적재 불가 장비:'), findsNothing);
      } else {
        expect(find.text('적재 불가 장비:'), findsOneWidget);
        // 사유가 붙은 항목이 최소 하나 ("라벨 — 사유")
        expect(
            allTexts(tester)
                .where((t) => t.contains(' — ') && !t.contains('개 — ')),
            isNotEmpty);
        expect(find.text('다시 배치'), findsOneWidget);
        // 제안이 있으면 문구와 버튼이 짝을 이룬다
        final hint = allTexts(tester)
            .where((t) => t.startsWith('2열 시트를 ') && t.contains('앞으로 당기면'));
        if (hint.isNotEmpty) {
          final cm = RegExp(r'2열 시트를 (\d+)cm').firstMatch(hint.first)!.group(1);
          expect(hint.first, contains('16개 모두 들어갑니다'));
          expect(find.text('2열 +${cm}cm 적용'), findsOneWidget);
        } else {
          expect(find.textContaining('2열을 당겨도 다 들어가지 않습니다'), findsOneWidget);
        }
      }
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    });
  });

  group('3a. 2열 슬라이드 제안', () {
    testWidgets('최후방에서는 안 들어가고 당기면 들어가는 긴 짐: 제안 문구 → 적용 → 전부 적재',
        (tester) async {
      final load = _findSlideOnlyLoad();
      if (load == null) {
        markTestSkipped('slide 0 에서만 안 들어가는 짐을 찾지 못했다 (프리셋 치수 변경?)');
        return;
      }
      final cm = (load.slide * 100).round();
      final optionLabel = (load.slide - 0.13).abs() < 1e-6
          ? '2열 중간 (+13cm)'
          : '2열 최전방 (+27cm)';

      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '작은 박스', w: 30, d: 30, h: 20);
      await flushSnackBars(tester);
      await addCustomBox(tester,
          label: '긴 짐', w: load.wCm, d: load.dCm, h: load.hCm);
      final snack = snackTexts(tester).join('\n');
      expect(snack, contains('1/2개 배치'));
      expect(snack, contains('적재 불가: 긴 짐 — '));
      await flushSnackBars(tester);

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.text('1/2개 적재 가능'), findsOneWidget);
      expect(find.text('적재 불가 장비:'), findsOneWidget);
      expect(find.textContaining('긴 짐 — '), findsOneWidget);
      expect(find.textContaining('2열 시트를 ${cm}cm 앞으로 당기면'), findsOneWidget);
      expect(find.textContaining('2개 모두 들어갑니다'), findsOneWidget);
      expect(find.text('2열 +${cm}cm 적용'), findsOneWidget);
      expect(find.text('다시 배치'), findsOneWidget);

      await tester.tap(find.text('2열 +${cm}cm 적용'));
      await tester.pumpAndSettle();

      // 앱바 2열 컨트롤이 바뀐다
      expect(
          find.descendant(of: seatSlideControl(), matching: find.text(optionLabel)),
          findsOneWidget);
      final s = spaceOf(tester);
      expect(s.seatSlide, closeTo(load.slide, 1e-9));
      expect(s.d, closeTo(TrunkSpace.sorento(seatSlide: load.slide).d, 1e-9));

      // 적용 결과 판정
      expect(find.text('모두 적재 가능!'), findsOneWidget);
      final after = snackTexts(tester).join('\n');
      expect(after, contains('2개 배치 완료'));
      expect(after, isNot(contains('적재 불가')));
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(insideBoxes(tester), hasLength(2));
      expectSceneValid(tester);
      expect(statusOf(tester), isNot(StatusState.problems));
      expect(panelOf(tester).collidingBoxIds, isEmpty);
      expect(painterOf(tester).tailgateBlockedIds, isEmpty);
      await flushAutosave(tester);
    });

    testWidgets('짐이 하나도 안 들어갈 때도 2열 제안을 보여준다', (tester) async {
      final load = _findSlideOnlyLoad();
      if (load == null) {
        markTestSkipped('slide 0 에서만 안 들어가는 짐을 찾지 못했다');
        return;
      }
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester,
          label: '긴 짐', w: load.wCm, d: load.dCm, h: load.hCm);
      await flushSnackBars(tester);
      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('앞으로 당기면'), findsOneWidget);
      await flushAutosave(tester);
    });
  });

  group('3b. 판정 다이얼로그의 다음 행동', () {
    testWidgets('"배치 저장" 은 저장 다이얼로그로 이어진다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('배치 저장'));
      await tester.pumpAndSettle();
      expect(find.text('모두 적재 가능!'), findsNothing);
      expect(find.text('배치 이름'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    });

    testWidgets('일부만 들어갈 때 "다시 배치" 는 전략 선택 다이얼로그로 이어진다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      // 큰 짐 둘 + 트렁크보다 큰 짐 하나 → 항상 2/3
      await addCustomBox(tester, label: '큰 박스', w: 60, d: 50, h: 40);
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '큰 박스 2', w: 60, d: 50, h: 40);
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '너무 큰 박스', w: 200, d: 150, h: 120);
      await flushSnackBars(tester);

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.text('2/3개 적재 가능'), findsOneWidget);
      expect(find.text('적재 불가 장비:'), findsOneWidget);
      expect(find.textContaining('너무 큰 박스 — 트렁크보다 큼'), findsOneWidget);
      // 2열을 당겨도 안 들어가므로 제안 버튼은 없다
      expect(find.textContaining('적용'), findsNothing);
      expect(find.textContaining('2열을 당겨도 다 들어가지 않습니다'), findsOneWidget);

      await tester.tap(find.text('다시 배치'));
      await tester.pumpAndSettle();
      expect(find.text('배치 전략을 선택하세요:'), findsOneWidget);
      expect(find.text('2/3개'), findsNWidgets(3));
      expect(find.textContaining('배치 불가: 너무 큰 박스'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    });
  });

  group('4. 앱바 2열 슬라이드 메뉴', () {
    testWidgets('세 단계가 있고 고르면 캡션·트렁크 깊이가 바뀐다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      expect(find.text('2열 최후방'), findsNWidgets(2)); // 버튼 + 메뉴 항목
      expect(find.text('2열 중간 (+13cm)'), findsOneWidget);
      expect(find.text('2열 최전방 (+27cm)'), findsOneWidget);

      await tester.tap(find.text('2열 최전방 (+27cm)'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: seatSlideControl(), matching: find.text('2열 최전방 (+27cm)')),
          findsOneWidget);
      expect(spaceOf(tester).d,
          closeTo(TrunkSpace.sorento().d + sorentoSeatSlideMax, 1e-9));
      expect(spaceOf(tester).leftWheelhouse.zStart, closeTo(0.27, 1e-9));
      // 차종 버튼의 바닥 깊이 숫자도 따라 바뀐다 (메뉴 항목은 프리셋 라벨 그대로)
      final depthCm = (spaceOf(tester).d * 100).round();
      expect(
          find.descendant(
              of: presetButton(), matching: find.textContaining('×${depthCm}cm)')),
          findsOneWidget);
      // 빈 트렁크에서는 스낵바가 없다
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2열 최후방').last);
      await tester.pumpAndSettle();
      expect(spaceOf(tester).d, closeTo(TrunkSpace.sorento().d, 1e-9));
      await flushAutosave(tester);
    });

    testWidgets('손대지 않은 배치는 슬라이드를 바꾸면 다시 배치된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _family);
      await flushSnackBars(tester);

      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2열 최전방 (+27cm)'));
      await tester.pumpAndSettle();

      // 다시 배치했다는 판정 스낵바 (최전방이면 보통 16개 전부)
      final snack = snackTexts(tester).join();
      expect(snack, matches(RegExp(r'(\d+/16개 배치|16개 배치 완료)')));
      final det = CollisionDetector(spaceOf(tester));
      for (final b in insideBoxes(tester)) {
        expect(det.describe(b, boxesOf(tester)), isEmpty, reason: b.label);
      }
      if (snack.contains('16개 배치 완료')) {
        expect(insideBoxes(tester), hasLength(16));
        expectSceneValid(tester);
      }
      await flushAutosave(tester);
    });

    testWidgets('손으로 돌린 뒤에는 슬라이드를 바꿔도 다시 배치하지 않는다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addCustomBox(tester, label: '손댄 박스', w: 50, d: 30, h: 30);
      await flushSnackBars(tester);
      await tester.tap(find.byTooltip('90° 회전'));
      await tester.pumpAndSettle();
      final b = boxesOf(tester).single;
      expect(b.rotY, 90);
      final pos = (b.x, b.z);

      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2열 중간 (+13cm)'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing, reason: '재배치 판정 스낵바 없음');
      expect((boxesOf(tester).single.x, boxesOf(tester).single.z), pos);
      expect(boxesOf(tester).single.rotY, 90);
      await flushAutosave(tester);
    });

    testWidgets('7인승에도 있고 커스텀에서는 숨는다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(presetMenuItem(TrunkPreset.sorento7));
      await tester.pumpAndSettle();
      expect(seatSlideControl(), findsOneWidget);

      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('커스텀'));
      await tester.pumpAndSettle();
      expect(find.byType(TrunkSizeDialog), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(seatSlideControl(), findsNothing);
      expect(find.text('커스텀 (100×100cm)'), findsOneWidget);
      await flushAutosave(tester);
    });
  });

  group('5. 차종 메뉴', () {
    testWidgets('쏘렌토 두 구성과 커스텀만 나온다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(presetButton());
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<PopupMenuItem<TrunkPreset>>(
              find.byType(PopupMenuItem<TrunkPreset>))
          .where((i) => i.value != null)
          .map((i) => i.value)
          .toList();
      expect(items,
          [TrunkPreset.sorento, TrunkPreset.sorento7, TrunkPreset.custom]);
      expect(find.text('SUV'), findsOneWidget);
      // 행은 두 줄: 차종명 + 설명. 5인승·7인승은 치수·부피가 같아서 차이를 글로 적는다
      Finder inItem(TrunkPreset p, Finder f) =>
          find.descendant(of: presetMenuItem(p), matching: f);
      expect(inItem(TrunkPreset.sorento, find.text('쏘렌토 5인승')), findsOneWidget);
      expect(inItem(TrunkPreset.sorento, find.textContaining('바닥 ')), findsOneWidget);
      expect(inItem(TrunkPreset.sorento7, find.text('쏘렌토 7인승·3열 접음')),
          findsOneWidget);
      expect(
          inItem(TrunkPreset.sorento7,
              find.text('5인승과 같은 공간 · 바닥 아래 수납함만 다름')),
          findsOneWidget);
      // 차종명·설명이 부피 숫자와 붙지 않는다 (간격 12px 이상), 설명은 잘리지 않는다
      for (final p in [TrunkPreset.sorento, TrunkPreset.sorento7]) {
        final vol = tester.getRect(inItem(p, find.textContaining(RegExp(r'^\d+L$'))));
        for (final e in inItem(p, find.byType(Text)).evaluate()) {
          final t = e.widget as Text;
          if (RegExp(r'^\d+L$').hasMatch(t.data ?? '')) continue;
          final para = e.renderObject as RenderParagraph;
          expect(tester.getRect(find.byWidget(t)).right, lessThanOrEqualTo(vol.left - 12),
              reason: t.data);
          expect(para.didExceedMaxLines, isFalse, reason: '${t.data} 가 잘렸다');
        }
        // 항목 높이는 그대로 48 — 메뉴 항목 위치가 바뀌지 않는다
        expect(tester.getSize(presetMenuItem(p)).height, 48);
      }
      for (final hidden in ['투싼', '싼타페', '카니발', '아이오닉5', '아반떼']) {
        expect(find.textContaining(hidden), findsNothing);
      }
      // 용량 표기 (L)
      expect(find.textContaining(RegExp(r'^\d+L$')), findsNWidgets(2));
    });

    testWidgets('7인승으로 바꿔도 짐은 그대로', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      final before = [for (final b in boxesOf(tester)) (b.id, b.x, b.y, b.z)];

      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(presetMenuItem(TrunkPreset.sorento7));
      await tester.pumpAndSettle();

      expect(find.text(TrunkPreset.sorento7.label), findsOneWidget);
      expect(spaceOf(tester).vehicleName, 'SORENTO 7인승 (3열 접음)');
      final after = [for (final b in boxesOf(tester)) (b.id, b.x, b.y, b.z)];
      for (var i = 0; i < before.length; i++) {
        expect(after[i].$1, before[i].$1);
        expect(after[i].$2, closeTo(before[i].$2, 1e-6));
        expect(after[i].$3, closeTo(before[i].$3, 1e-6));
        expect(after[i].$4, closeTo(before[i].$4, 1e-6));
      }
      expectSceneValid(tester);
      await flushAutosave(tester);
    });

    testWidgets('차종을 바꿔도 2열 슬라이드 설정이 유지된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(seatSlideControl());
      await tester.pumpAndSettle();
      await tester.tap(find.text('2열 중간 (+13cm)'));
      await tester.pumpAndSettle();
      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(presetMenuItem(TrunkPreset.sorento7));
      await tester.pumpAndSettle();
      expect(spaceOf(tester).seatSlide, closeTo(0.13, 1e-9));
      expect(spaceOf(tester).d,
          closeTo(TrunkSpace.sorento7(seatSlide: 0.13).d, 1e-9));
      expect(
          find.descendant(
              of: seatSlideControl(), matching: find.text('2열 중간 (+13cm)')),
          findsOneWidget);
      await flushAutosave(tester);
    });

    testWidgets('커스텀: 치수 검증, 취소, 적용', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);

      Future<void> openCustom() async {
        await tester.tap(presetButton());
        await tester.pumpAndSettle();
        await tester.tap(find.text('커스텀').last);
        await tester.pumpAndSettle();
        expect(find.byType(TrunkSizeDialog), findsOneWidget);
        expect(find.text('커스텀 트렁크'), findsOneWidget);
      }

      // 취소 → 그대로
      await openCustom();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text(TrunkPreset.sorento.label), findsOneWidget);

      // 잘못된 값 → 오류 문구
      await openCustom();
      await tester.enterText(find.widgetWithText(TextField, '가로(cm)'), '0');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('트렁크 가로/세로/높이는 양수를 입력하세요'), findsOneWidget);
      expect(find.byType(TrunkSizeDialog), findsOneWidget);

      // 적용
      await tester.enterText(find.widgetWithText(TextField, '가로(cm)'), '150');
      await tester.enterText(find.widgetWithText(TextField, '세로(cm)'), '120');
      await tester.enterText(find.widgetWithText(TextField, '높이(cm)'), '90');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('커스텀 (150×120cm)'), findsOneWidget);
      final s = spaceOf(tester);
      expect((s.w, s.d, s.h), (1.5, 1.2, 0.9));
      expect(s.hasTailgateModel, isFalse);
      expect(boxesOf(tester), hasLength(6), reason: '짐 유지');
      expect(seatSlideControl(), findsNothing);
      await flushAutosave(tester);
    });

    testWidgets('커스텀: 휠하우스 입력이 반영된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('커스텀'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('휠하우스 (선택)'));
      await tester.pumpAndSettle();
      final wFields = find.widgetWithText(TextField, 'W(cm)');
      final dFields = find.widgetWithText(TextField, 'D(cm)');
      final hFields = find.widgetWithText(TextField, 'H(cm)');
      expect(wFields, findsNWidgets(2));
      await tester.enterText(wFields.first, '10');
      await tester.enterText(dFields.first, '40');
      await tester.enterText(hFields.first, '25');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      final lw = spaceOf(tester).leftWheelhouse;
      expect((lw.w, lw.d, lw.h), (0.10, 0.40, 0.25));
      expect(spaceOf(tester).rightWheelhouse.w, 0);
      await flushAutosave(tester);
    });

    testWidgets('작은 커스텀 트렁크로 바꾸면 손대지 않은 배치는 다시 배치된다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, _solo);
      await flushSnackBars(tester);
      await tester.tap(presetButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('커스텀'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '가로(cm)'), '90');
      await tester.enterText(find.widgetWithText(TextField, '세로(cm)'), '80');
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      // 솔로 세트(≈100L)는 90×80×80 에 충분히 들어간다
      expectSceneValid(tester, reason: '커스텀 90×80×80 으로 전환 후');
      await flushAutosave(tester);
    });
  });
}
