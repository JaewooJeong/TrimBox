// SimulatorScreen 폰 UX 독립 검증 — `backlog/phone-ux-w9.md` 의 2절(화면 모드)·3.3~3.8절·5절을
// 사양으로 삼아 구현을 보지 않고 쓴 테스트. 폰 세로 3크기(390×844, 360×640, 390×600),
// 폰 가로(844×390), 회귀 보호용 데스크톱(1280×960). 플랫폼은 Android 로 고정한다.
//
// 사양과 구현이 다르면 테스트를 구현에 맞추지 않는다 (2026-09-20 발견된 2건 — 타일 버튼 40px, 첫 프레임 툴팁 — 은 구현을 고쳐 해소).
// 실제 글꼴(sim_harness.loadRealFonts)이 없으면 overflow 검사만 건너뛴다 (거짓 양성 방지).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/vec3.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';
import 'package:trimbox/widgets/box_list_panel.dart';

import 'sim_harness.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);

/// 폰 세로 (사양 2절: 폭 < 600 → 아래 시트)
const _portrait = <String, Size>{
  '390×844': kPhone,
  '360×640': Size(360, 640),
  '390×600': kPhoneShort,
};

/// 폰 가로 (사양 2절: 가로 > 세로, 높이 < 500 → 옆 300px 압축 패널)
const Size _landscape = Size(844, 390);

/// 사양 3.3: 시트 최소 0.12, 최대 0.85. 짐이 들어오면 약 45 %.
const double _sheetMin = 0.12;
const double _sheetMax = 0.85;
const double _sheetLoaded = 0.45;

/// 빈 상태 시트의 목표 높이(px): 손잡이 + 안내 + CTA. 하단 인셋은 여기에 더해진다 (3.8).
const double _sheetInitialPx = 220;

/// 앱 팔레트: 주 동작 파랑, 보조 외곽선 초록
const Color _blue = Color(0xFF4DA3FF);
const Color _green = Color(0xFF00E676);

/// 선택 도구 띠의 세 툴팁 (사양 3.4)
const _toolbarTips = ['선택한 짐 회전', '선택한 짐 삭제', '선택 해제'];

/// 본문 높이 (앱바 제외)
double _bodyH(Size s) => s.height - kToolbarHeight;

// ─────────────────────────── 오류 수집기 ───────────────────────────

/// pump 중 보고된 FlutterError 를 단계 라벨과 함께 모은다 (simulator_layouts_test 와 같은 꼴).
class _Errors {
  final List<String> found = [];
  String stage = 'start';
  void Function(FlutterErrorDetails)? _original;

  void install() {
    _original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      final head = text
          .split('\n')
          .firstWhere(
            (l) =>
                l.contains('overflowed') ||
                l.contains('Exception') ||
                l.contains('Error'),
            orElse: () => details.exceptionAsString().split('\n').first,
          )
          .trim();
      final where =
          RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(text)?.group(0) ?? '';
      if (!realFontsLoaded && head.contains('overflowed')) return;
      found.add('[$stage] $head $where');
    };
  }

  void restore() => FlutterError.onError = _original;
}

/// 단계별로 오류를 모으며 [body] 를 돌리고, 끝에 한꺼번에 검사한다.
Future<void> _collecting(
    WidgetTester tester, Future<void> Function(_Errors e) body) async {
  final e = _Errors()..install();
  try {
    await body(e);
  } finally {
    e.restore();
  }
  expect(e.found, isEmpty, reason: e.found.join('\n'));
}

// ─────────────────────────── 공용 도우미 ───────────────────────────

Rect _sheetRect(WidgetTester tester) =>
    tester.getRect(find.byType(BoxListPanel));

/// 글자를 품은 버튼 (ElevatedButton·OutlinedButton·TextButton)
Finder _buttonWith(Finder text) => find
    .ancestor(of: text, matching: find.bySubtype<ButtonStyleButton>())
    .first;

Finder _textButton(String label) => _buttonWith(find.text(label));

/// "2열 +Ncm 적용" 문구
Finder _applyText() => find.textContaining(RegExp(r'^2열 \+\d+cm 적용$'));

/// 패널(폰에서는 시트 안 ListView)을 맨 위로 되돌린다.
Future<void> _panelToTop(WidgetTester tester) async {
  final c = panelOf(tester).scrollController;
  if (c != null && c.hasClients && c.offset > 0) {
    c.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

/// 시트·패널 안의 위젯을 보이게 스크롤한 뒤 누른다.
Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) await _panelToTop(tester);
  expect(f, findsWidgets);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

/// 스낵바·자동 저장 타이머를 흘려보낸다 (테스트 끝에 타이머가 남지 않게).
Future<void> _finish(WidgetTester tester) async {
  await flushSnackBars(tester);
  await flushAutosave(tester);
}

/// 온보딩 카드를 닫는다 (가장 낮은 화면에서는 카드가 스크롤되므로 위쪽 제목을 누른다).
Future<void> _dismissOnboarding(WidgetTester tester) async {
  expect(find.text('아무 곳이나 탭하여 닫기'), findsOneWidget);
  await tester.tap(find.text('박스를 추가하여\n시뮬레이션을 시작하세요'));
  await tester.pumpAndSettle();
  expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
}

/// 트렁크 상자의 8 꼭짓점
List<Vec3> _trunkCorners(TrunkSpace s) => [
      for (final x in [0.0, s.w])
        for (final y in [0.0, s.h])
          for (final z in [0.0, s.d]) Vec3(x, y, z),
    ];

/// 트렁크 8 꼭짓점이 모두 캔버스 안에 투영된다.
void _expectTrunkInsideCanvas(WidgetTester tester, {String reason = ''}) {
  final canvas = canvasRect(tester).inflate(0.5);
  for (final p in _trunkCorners(spaceOf(tester))) {
    final s = screenOf(tester, p);
    expect(canvas.contains(s), isTrue, reason: '$p → $s not in $canvas $reason');
  }
}

/// 캔버스에서 가장 위에 있는(가리는 것이 없는) 짐을 탭해 선택한다.
Future<TrimBox> _tapHighestBox(WidgetTester tester) async {
  final b = insideBoxes(tester).reduce((a, c) => a.top >= c.top ? a : c);
  await tester.tapAt(topCenterOf(tester, b) + const Offset(0, 2));
  await tester.pumpAndSettle();
  return b;
}

bool _toolbarShown() =>
    _toolbarTips.every((t) => find.byTooltip(t).evaluate().isNotEmpty);

bool _toolbarHidden() =>
    _toolbarTips.every((t) => find.byTooltip(t).evaluate().isEmpty);

/// 선택 도구 띠의 바탕 (테두리 있는 Container)
Rect _toolbarRect(WidgetTester tester) => tester.getRect(find
    .ancestor(
        of: find.byTooltip('선택한 짐 회전'),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null))
    .first);

/// 선택 도구 띠가 캔버스 안, 캡션 위(캔버스 바닥에서 56px 이상), 폭 = 캔버스 − 16 (사양 3.4)
void _expectToolbarPlacement(WidgetTester tester, {String reason = ''}) {
  final canvas = canvasRect(tester);
  final bar = _toolbarRect(tester);
  expect(bar.left, greaterThanOrEqualTo(canvas.left - 0.5), reason: '$bar in $canvas $reason');
  expect(bar.right, lessThanOrEqualTo(canvas.right + 0.5), reason: '$bar in $canvas $reason');
  expect(bar.top, greaterThanOrEqualTo(canvas.top - 0.5), reason: '$bar in $canvas $reason');
  expect(canvas.bottom - bar.bottom, greaterThanOrEqualTo(56),
      reason: '캡션 위에 뜬다: $bar in $canvas $reason');
  expect(bar.width, closeTo(canvas.width - 16, 1), reason: '$bar in $canvas $reason');
  for (final tip in _toolbarTips) {
    final r = tester.getRect(find.byTooltip(tip));
    expect(bar.inflate(0.5).contains(r.center), isTrue, reason: '$tip $r in $bar');
    expect(r.height, greaterThanOrEqualTo(44), reason: '$tip 버튼 44px');
    expect(r.width, greaterThanOrEqualTo(44), reason: '$tip 버튼 44px');
  }
}

/// 결과 시트(BottomSheet)의 글자 있는 버튼: 라벨 → (사각형, 위젯). 제목 행의 ✕ 는 글자가 없어 제외.
Map<String, (Rect, ButtonStyleButton)> _sheetButtons(WidgetTester tester) {
  final sheet = find.byType(BottomSheet);
  final out = <String, (Rect, ButtonStyleButton)>{};
  for (final e in find
      .descendant(of: sheet, matching: find.bySubtype<ButtonStyleButton>())
      .evaluate()) {
    final w = e.widget as ButtonStyleButton;
    final texts = find
        .descendant(of: find.byWidget(w), matching: find.byType(Text))
        .evaluate();
    if (texts.isEmpty) continue;
    final label = (texts.first.widget as Text).data ?? '';
    out[label] = (tester.getRect(find.byWidget(w)), w);
  }
  return out;
}

Color? _bgOf(ButtonStyleButton b) =>
    b.style?.backgroundColor?.resolve(<WidgetState>{});

Color? _sideOf(ButtonStyleButton b) =>
    b.style?.side?.resolve(<WidgetState>{})?.color;

/// 사양 3.7: 폰 결과는 아래 시트, 버튼은 전체 폭(시트 폭 − 32)·48px·세로 8px 간격,
/// 주 동작(파랑 ElevatedButton)이 맨 아래. 글자 버튼은 정확히 [labels] 만 있다.
void _expectResultSheet(WidgetTester tester, String what,
    {required List<String> labels}) {
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget, reason: '$what: 아래 시트로 열린다');
  expect(find.byType(AlertDialog), findsNothing, reason: '$what: 다이얼로그가 아니다');
  expect(find.descendant(of: sheet, matching: find.byTooltip('닫기')),
      findsOneWidget, reason: '$what: 제목 행의 ✕ 닫기');
  // 시트의 표면(Material). BottomSheet 위젯 상자는 화면 전체 폭 슬롯이고, 폰 가로처럼 넓은
  // 화면에서는 표면이 그보다 좁게(Material 기본 최대 640px) 가운데 놓인다.
  final sheetRect = tester.getRect(
      find.descendant(of: sheet, matching: find.byType(Material)).first);
  final slot = tester.getRect(sheet);
  expect(sheetRect.bottom, closeTo(slot.bottom, 0.5), reason: '$what: 표면이 바닥에 붙는다');
  expect((sheetRect.center.dx - slot.center.dx).abs(), lessThanOrEqualTo(0.5),
      reason: '$what: 표면이 가운데');
  final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  if (screenW < 600) {
    expect(sheetRect.width, screenW, reason: '$what: 폰 세로에서는 시트가 화면 전체 폭');
  }
  final buttons = _sheetButtons(tester);
  expect(buttons.keys.toSet(), labels.toSet(),
      reason: '$what: 글자 버튼 (찾은 것 ${buttons.keys.toList()})');
  final rects = [for (final l in labels) buttons[l]!.$1];
  for (final r in rects) {
    expect(r.height, closeTo(48, 0.5), reason: '$what: 버튼 높이 48 ($r)');
    expect(r.width, closeTo(sheetRect.width - 32, 1),
        reason: '$what: 전체 폭 ($r in $sheetRect)');
    expect(r.left, greaterThanOrEqualTo(sheetRect.left - 0.5), reason: '$what: $r in $sheetRect');
    expect(r.bottom, lessThanOrEqualTo(sheetRect.bottom + 0.5),
        reason: '$what: 버튼이 시트 안에 있다 ($r in $sheetRect)');
  }
  final sorted = [...rects]..sort((a, b) => a.top.compareTo(b.top));
  for (var i = 1; i < sorted.length; i++) {
    expect(sorted[i].top - sorted[i - 1].bottom, greaterThanOrEqualTo(8 - 0.01),
        reason: '$what: 세로 간격 8px 이상 (${sorted[i - 1]} / ${sorted[i]})');
  }
  final lowestTop = rects.map((r) => r.top).reduce(math.max);
  final primaries =
      buttons.entries.where((e) => e.value.$2 is ElevatedButton).toList();
  expect(primaries, hasLength(1), reason: '$what: 주 동작(ElevatedButton) 하나');
  expect(primaries.single.value.$1.top, closeTo(lowestTop, 0.5),
      reason: '$what: 주 동작 ${primaries.single.key} 이 맨 아래');
  expect(_bgOf(primaries.single.value.$2), _blue,
      reason: '$what: 주 동작은 파랑');
  for (final e in buttons.entries.where((e) => e.value.$2 is OutlinedButton)) {
    expect(_sideOf(e.value.$2), _green, reason: '$what: 보조 ${e.key} 는 초록 외곽선');
  }
}

/// 박스 자리 스냅샷 (id → x,y,z,rotY)
Map<String, (double, double, double, int)> _positions(WidgetTester tester) => {
      for (final b in boxesOf(tester)) b.id: (b.x, b.y, b.z, b.rotY),
    };

/// 판정 결과 시트를 그 시트의 ✕ 로 닫는다.
Future<void> _closeSheetByX(WidgetTester tester) async {
  final x = find.descendant(
      of: find.byType(BottomSheet), matching: find.byTooltip('닫기'));
  expect(x, findsOneWidget);
  await tester.tap(x);
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing);
}

void main() {
  setUpAll(loadRealFonts);

  // ═══════════════════ 1. 화면 모드 (사양 2절) ═══════════════════
  group('1. 화면 모드', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('폰 세로 ${entry.key}: 아래 시트, 옆 패널 없음', (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        expect(find.byType(DraggableScrollableSheet), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(BoxListPanel)),
            findsOneWidget);
        // 옆 패널이 없다: 시트와 캔버스가 화면 전체 폭
        expect(_sheetRect(tester).width, size.width);
        expect(canvasRect(tester).width, size.width);
      }, variant: _android);
    }

    testWidgets('폰 가로 844×390: 옆 300px 압축 패널, 시트 없음', (tester) async {
      await pumpApp(tester, size: _landscape, prefs: seenPrefs());
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(tester.getSize(find.byType(BoxListPanel)).width, 300);
      expect(panelOf(tester).compact, isTrue);
      expect(canvasRect(tester).width, _landscape.width - 300);
    }, variant: _android);

    testWidgets('데스크톱 1280×960 회귀: 320px 패널, 판정은 AlertDialog, 적재율 카드',
        (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ]);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(tester.getSize(find.byType(BoxListPanel)).width, 320);
      expect(panelOf(tester).compact, isFalse);
      expect(find.textContaining('총 짐:'), findsOneWidget);
      expect(find.textContaining('남은 공간:'), findsOneWidget);
      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await closeResult(tester);
      await _finish(tester);
    }, variant: _android);
  });

  // ═══════════════════ 2. 캔버스가 시트를 따라간다 (사양 3.3) ═══════════════════
  group('2. 캔버스가 시트를 따라간다', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 캔버스 바닥 = 시트 위, 올리면 줄고 카메라를 다시 맞춘다',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        final body = _bodyH(size);
        final c0 = canvasRect(tester);
        final s0 = _sheetRect(tester);
        expect(c0.bottom, closeTo(s0.top, 1), reason: '초기: $c0 / $s0');
        _expectTrunkInsideCanvas(tester, reason: '초기');
        final d0 = painterOf(tester).camera.distance;

        await expandSheet(tester);
        final c1 = canvasRect(tester);
        final s1 = _sheetRect(tester);
        expect(s1.height, closeTo(body * _sheetMax, 2), reason: '최대 85%');
        expect(c1.height, lessThan(c0.height), reason: '캔버스가 줄어든다');
        expect(c1.top, c0.top, reason: '캔버스 위는 그대로');
        expect(c1.bottom, closeTo(s1.top, 2), reason: '올린 뒤: $c1 / $s1');
        final d1 = painterOf(tester).camera.distance;
        expect((d1 - d0).abs(), greaterThan(1e-3),
            reason: '카메라 거리 다시 맞춤 ($d0 → $d1)');
        _expectTrunkInsideCanvas(tester, reason: '85%');

        // 끝까지 내리면 최소 12% — 캔버스도 따라 커진다
        final sheet = find.byType(BoxListPanel);
        for (var i = 0; i < 10; i++) {
          await tester.fling(sheet, const Offset(0, 300), 1000);
          await tester.pumpAndSettle();
        }
        final c2 = canvasRect(tester);
        final s2 = _sheetRect(tester);
        expect(s2.height, closeTo(body * _sheetMin, 2), reason: '최소 12%');
        expect(c2.bottom, closeTo(s2.top, 2), reason: '내린 뒤: $c2 / $s2');
        expect(c2.height, greaterThan(c0.height));
        _expectTrunkInsideCanvas(tester, reason: '12%');
      }, variant: _android);
    }
  });

  // ═══════════════════ 3. 첫 추가 뒤 시트가 올라간다 (사양 3.3) ═══════════════════
  group('3. 첫 추가 뒤 시트 높이', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      final exact45 = size != kPhoneShort;
      testWidgets(
          '${entry.key}: 빈 트렁크에 첫 세트 → ${exact45 ? '약 45%' : '초기값 이상'}, 둘째 세트는 내리지 않음',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        final body = _bodyH(size);
        final h0 = _sheetRect(tester).height;
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        final h1 = _sheetRect(tester).height;
        if (exact45) {
          expect(h1, closeTo(body * _sheetLoaded, 3), reason: '첫 추가 뒤 약 45% (초기 $h0)');
        } else {
          expect(h1, greaterThanOrEqualTo(h0 - 0.5), reason: '초기 $h0 → $h1');
        }
        // 캔버스는 여전히 시트 바로 위까지
        expect(canvasRect(tester).bottom, closeTo(_sheetRect(tester).top, 2));

        await addBundle(tester, '2인 미니멀 캠핑');
        await flushSnackBars(tester);
        final h2 = _sheetRect(tester).height;
        expect(h2, greaterThanOrEqualTo(h1 - 1), reason: '둘째 세트 뒤 $h1 → $h2');
        await _finish(tester);
      }, variant: _android);
    }
  });

  // ═══════════════════ 4. 적재율 칩 (사양 3.3) ═══════════════════
  group('4. 적재율 칩', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 한 줄 칩 "적재율 N% · N개 · 남은 NL", 캔버스 200px 미만이면 숨김',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);

        final head = find.byWidgetPredicate((w) => w is Text && w.data == '적재율 ');
        expect(head, findsOneWidget);
        final row = find.ancestor(of: head, matching: find.byType(Row)).first;
        final parts = [
          for (final e in find.descendant(of: row, matching: find.byType(Text)).evaluate())
            (e.widget as Text).data ?? '',
        ];
        expect(parts.join(), matches(RegExp(r'^적재율 \d+% · \d+개 · 남은 \d+L$')),
            reason: '$parts');
        expect(parts[1], matches(RegExp(r'^\d+%$')));
        expect(parts.last, matches(RegExp(r' · \d+개 · 남은 \d+L$')));
        // 한 줄: 모든 조각의 세로 중심이 같다
        final centers = [
          for (final e in find.descendant(of: row, matching: find.byType(Text)).evaluate())
            tester.getRect(find.byElementPredicate((x) => x == e)).center.dy,
        ];
        for (final c in centers) {
          expect(c, closeTo(centers.first, 1), reason: '한 줄 $centers');
        }
        // 캔버스 안에 있다
        final canvas = canvasRect(tester);
        final chip = tester.getRect(row);
        expect(canvas.inflate(0.5).contains(chip.topLeft), isTrue, reason: '$chip in $canvas');
        expect(canvas.inflate(0.5).contains(chip.bottomRight), isTrue, reason: '$chip in $canvas');
        // 데스크톱 카드 문구는 없다
        expect(find.textContaining('총 짐:'), findsNothing);
        expect(find.textContaining('남은 공간:'), findsNothing);

        // 시트를 85% 까지 올리면 캔버스가 200px 미만 → 칩을 숨긴다
        await expandSheet(tester);
        expect(canvasRect(tester).height, lessThan(200), reason: '전제: 캔버스가 낮다');
        expect(head, findsNothing, reason: '낮은 캔버스에서는 칩 없음');
        await _finish(tester);
      }, variant: _android);
    }
  });

  // ═══════════════════ 5. 선택 도구 띠 (사양 3.4) ═══════════════════
  group('5. 선택 도구 띠', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 짐 탭 → 띠(회전·삭제·해제)가 캔버스 아래 캡션 위에; 회전 90°, 해제, 삭제',
          (tester) async {
        await pumpAppWithScene(
            tester,
            [
              mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
              mkBox('box-002', '나', w: 0.40, d: 0.40, h: 0.30, x: 0.80, z: 0.30),
            ],
            size: size);
        expect(_toolbarHidden(), isTrue, reason: '선택 없음 → 띠 없음');
        expect(canvasRect(tester).height, greaterThanOrEqualTo(200), reason: '전제');

        final target = boxesOf(tester).firstWhere((b) => b.id == 'box-002');
        await tester.tapAt(topCenterOf(tester, target) + const Offset(0, 2));
        await tester.pumpAndSettle();
        expect(panelOf(tester).selectedBoxId, 'box-002');
        expect(_toolbarShown(), isTrue, reason: '선택 → 띠');
        _expectToolbarPlacement(tester, reason: entry.key);

        // 회전: rotY 가 90 바뀐다
        final r0 = target.rotY;
        await tester.tap(find.byTooltip('선택한 짐 회전'));
        await tester.pumpAndSettle();
        final rotated = boxesOf(tester).firstWhere((b) => b.id == 'box-002');
        expect((rotated.rotY - r0 + 360) % 360, 90);
        expect(_toolbarShown(), isTrue, reason: '회전 뒤에도 선택 유지');

        // ✕ 선택 해제
        await tester.tap(find.byTooltip('선택 해제'));
        await tester.pumpAndSettle();
        expect(panelOf(tester).selectedBoxId, isNull);
        expect(_toolbarHidden(), isTrue, reason: '해제 → 띠 없음');
        expect(boxesOf(tester), hasLength(2), reason: '해제는 지우지 않는다');

        // 다시 선택 → 삭제
        final again = boxesOf(tester).firstWhere((b) => b.id == 'box-002');
        await tester.tapAt(topCenterOf(tester, again) + const Offset(0, 2));
        await tester.pumpAndSettle();
        expect(panelOf(tester).selectedBoxId, 'box-002');
        await tester.tap(find.byTooltip('선택한 짐 삭제'));
        await tester.pumpAndSettle();
        expect(boxesOf(tester).map((b) => b.id), ['box-001']);
        expect(_toolbarHidden(), isTrue, reason: '삭제 → 띠 없음');
        await _finish(tester);
      }, variant: _android);
    }

    testWidgets('390×844: 스텝 뷰 중에는 띠를 숨긴다', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await _tapHighestBox(tester);
      expect(panelOf(tester).selectedBoxId, isNotNull);
      expect(_toolbarShown(), isTrue);
      await _tapVisible(tester, find.byTooltip('적재 순서 가이드'));
      expect(find.textContaining('STEP 1 / '), findsOneWidget);
      expect(_toolbarHidden(), isTrue, reason: '스텝 뷰 → 띠 없음');
      await tester.tap(find.byTooltip('스텝뷰 닫기'));
      await tester.pumpAndSettle();
      await _finish(tester);
    }, variant: _android);

    testWidgets('데스크톱 1280×960: 짐을 선택해도 띠가 없다', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.40, d: 0.40, h: 0.30, x: 0.20, z: 0.30),
      ]);
      final b = boxesOf(tester).single;
      await tester.tapAt(topCenterOf(tester, b) + const Offset(0, 2));
      await tester.pumpAndSettle();
      expect(panelOf(tester).selectedBoxId, 'box-001');
      expect(_toolbarHidden(), isTrue);
    }, variant: _android);
  });

  // ═══════════════════ 6. 폰 시트 구성 (사양 3.5) ═══════════════════
  group('6. 폰 시트 구성', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 도구 한 줄(박스 추가·순서 가이드·실행 취소·다시 실행·⋯) 44px, ⋯ 메뉴, 상태 두 줄',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        await _panelToTop(tester);
        final panel = find.byType(BoxListPanel);

        final add = tester.getRect(_buttonWith(
            find.descendant(of: panel, matching: find.text('박스 추가'))));
        final tips = ['실행 취소', '다시 실행', '더 보기', '적재 순서 가이드'];
        final rects = <String, Rect>{'박스 추가': add};
        for (final t in tips) {
          final f = find.descendant(of: panel, matching: find.byTooltip(t));
          expect(f, findsOneWidget, reason: t);
          rects[t] = tester.getRect(f);
        }
        for (final e in rects.entries) {
          expect(e.value.height, greaterThanOrEqualTo(44), reason: '${e.key} ${e.value}');
          expect((e.value.center.dy - add.center.dy).abs(), lessThanOrEqualTo(1),
              reason: '${e.key} 는 박스 추가와 같은 줄 (${e.value} / $add)');
          expect(e.value.right, lessThanOrEqualTo(size.width), reason: '${e.key} 화면 안');
        }
        // 도구 줄은 시트 안에 있다
        final sheet = _sheetRect(tester);
        expect(add.top, greaterThanOrEqualTo(sheet.top));

        // 저장·불러오기는 직접 버튼이 아니라 ⋯ 메뉴 안에
        expect(find.descendant(of: panel, matching: find.byTooltip('배치 저장')), findsNothing);
        expect(find.descendant(of: panel, matching: find.byTooltip('불러오기')), findsNothing);
        expect(find.descendant(of: panel, matching: find.byTooltip('스크린샷')), findsNothing);
        expect(find.descendant(of: panel, matching: find.byTooltip('공유 카드')), findsNothing);
        await tester.tap(find.byTooltip('더 보기'));
        await tester.pumpAndSettle();
        expect(find.text('배치 저장'), findsOneWidget);
        expect(find.text('불러오기'), findsOneWidget);
        // 파일 I/O 가 없는 플랫폼(테스트 VM)에서는 이미지 항목이 없다
        expect(find.text('스크린샷'), findsNothing);
        expect(find.text('공유 카드'), findsNothing);
        await tester.tapAt(const Offset(10, 100));
        await tester.pumpAndSettle();
        expect(find.text('배치 저장'), findsNothing, reason: '메뉴가 닫혔다');

        // 상태 두 줄: 통계 한 줄 + 상태 행
        expect(
            find.descendant(
                of: panel,
                matching: find.textContaining(
                    RegExp(r'^박스 \d+개 · 부피 \d+% · 남은 높이 -?\d+cm$'))),
            findsOneWidget);
        final statusIcons = find.descendant(
            of: panel,
            matching: find.byWidgetPredicate((w) =>
                w is Icon &&
                w.size == 14 &&
                (w.icon == Icons.check_circle_outline ||
                    w.icon == Icons.lightbulb_outline ||
                    w.icon == Icons.warning_amber_rounded)));
        expect(statusIcons, findsOneWidget, reason: '상태 행 하나');
        await _finish(tester);
      }, variant: _android);

      testWidgets('${entry.key}: 히어로 줄 "들어갈까?" | "자동 배치" 48px 한 줄, 시트 맨 위',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        await _panelToTop(tester);
        final quick = tester.getRect(_textButton('들어갈까?'));
        final auto = tester.getRect(_textButton('자동 배치'));
        expect(quick.height, closeTo(48, 1), reason: '$quick');
        expect(auto.height, closeTo(48, 1), reason: '$auto');
        expect((quick.center.dy - auto.center.dy).abs(), lessThanOrEqualTo(1));
        final add = tester.getRect(_buttonWith(find.descendant(
            of: find.byType(BoxListPanel), matching: find.text('박스 추가'))));
        expect(quick.bottom, lessThanOrEqualTo(add.top), reason: '히어로 줄이 도구 줄 위');
        expect(quick.top, greaterThanOrEqualTo(_sheetRect(tester).top));
        await _finish(tester);
      }, variant: _android);

      testWidgets('${entry.key}: 목록 타일의 회전·삭제 탭 영역 48px', (tester) async {
        await pumpAppWithScene(
            tester,
            [mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20)],
            size: size);
        for (final tip in ['90° 회전', '삭제']) {
          final f = find.descendant(
              of: find.byType(BoxListPanel), matching: find.byTooltip(tip));
          await tester.ensureVisible(f.first);
          await tester.pumpAndSettle();
          final s = tester.getSize(f.first);
          expect(s.height, greaterThanOrEqualTo(48), reason: '$tip $s');
          expect(s.width, greaterThanOrEqualTo(48), reason: '$tip $s');
        }
      }, variant: _android);
    }
  });

  // ═══════════════════ 7. 빈 시트 (사양 3.5) ═══════════════════
  group('7. 빈 시트', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: CTA 와 "저장된 배치 불러오기" 가 초기 높이 안에, 도구 줄 없음, 불러오기 다이얼로그',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        final cta = tester.getRect(_textButton('캠핑 장비 선택하기'));
        final load = tester.getRect(_textButton('저장된 배치 불러오기'));
        for (final r in [cta, load]) {
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$r');
          expect(r.top, greaterThanOrEqualTo(_sheetRect(tester).top), reason: '$r');
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(size.width));
        }
        expect(load.top, greaterThanOrEqualTo(cta.bottom - 0.5), reason: 'CTA 아래');
        expect(find.text('박스 추가'), findsNothing);
        for (final t in ['실행 취소', '다시 실행', '더 보기']) {
          expect(find.byTooltip(t), findsNothing, reason: t);
        }
        expect(find.text('들어갈까?'), findsNothing);

        await tester.tap(_textButton('저장된 배치 불러오기'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('저장된 배치 불러오기'), findsNWidgets(2), reason: '버튼 + 제목');
        expect(find.text('저장된 배치가 없습니다'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }, variant: _android);
    }
  });

  // ═══════════════════ 8. 장비 선택 전체 화면 페이지 (사양 3.6) ═══════════════════
  group('8. 장비 선택 페이지', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 시뮬레이터에서 열면 Scaffold 페이지 "장비 선택", ✕ 닫기, 세트 → 추가 (16개), 행 48px',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await openAddDialog(tester);
        final picker = find.byType(AddBoxDialog);
        expect(find.descendant(of: picker, matching: find.byType(Scaffold)), findsOneWidget);
        expect(find.descendant(of: picker, matching: find.byType(Dialog)), findsNothing);
        expect(find.text('장비 선택'), findsOneWidget);
        expect(tester.getRect(picker).width, size.width, reason: '전체 폭');

        // 보이는 행 5개의 탭 영역 ≥ 48px
        final checkboxes = find.descendant(of: picker, matching: find.byType(Checkbox));
        expect(checkboxes.evaluate().length, greaterThanOrEqualTo(5));
        for (var i = 0; i < 5; i++) {
          final box = checkboxes.at(i);
          await tester.ensureVisible(box);
          await tester.pumpAndSettle();
          final row = find.ancestor(of: box, matching: find.byType(InkWell)).first;
          expect(tester.getRect(row).height, greaterThanOrEqualTo(48), reason: '행 $i');
          expect(tester.getRect(row).width, greaterThanOrEqualTo(size.width - 40), reason: '행 $i');
        }

        // ✕ 로 닫으면 시뮬레이터로 돌아오고 아무것도 추가되지 않는다
        await tester.tap(find.byTooltip('닫기'));
        await tester.pumpAndSettle();
        expect(find.byType(AddBoxDialog), findsNothing);
        expect(boxesOf(tester), isEmpty);

        await openAddDialog(tester);
        await tester.ensureVisible(find.text('4인 가족 캠핑'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('4인 가족 캠핑'));
        await tester.pumpAndSettle();
        expect(find.text('추가 (16개)'), findsOneWidget);
        final addBtn = tester.getRect(_textButton('추가 (16개)'));
        expect(addBtn.height, greaterThanOrEqualTo(48));
        expect(addBtn.bottom, lessThanOrEqualTo(size.height));
        await tester.tap(find.byTooltip('닫기'));
        await tester.pumpAndSettle();
        expect(find.byType(AddBoxDialog), findsNothing);
      }, variant: _android);
    }

    testWidgets('데스크톱 1280×960 회귀: 여전히 Dialog, "장비 선택" 제목 없음', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await openAddDialog(tester);
      final picker = find.byType(AddBoxDialog);
      expect(find.descendant(of: picker, matching: find.byType(Dialog)), findsOneWidget);
      expect(find.descendant(of: picker, matching: find.byType(Scaffold)), findsNothing);
      expect(find.text('장비 선택'), findsNothing);
      // 다이얼로그 표면은 화면보다 좁다 (Dialog 위젯 자체의 상자는 화면 전체이므로 Material 을 잰다)
      final surface = tester.getRect(find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first);
      expect(surface.width, lessThan(kDesktop.width));
      expect(surface.left, greaterThan(0));
    }, variant: _android);
  });

  // ═══════════════════ 9. 판정 결과 시트 (사양 3.7) ═══════════════════
  group('9. 판정 결과 시트', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;

      testWidgets('${entry.key}: 모두 적재 → 시트, 보조 "순서 가이드" 위 / 주 "배치 저장" 아래, ✕ 닫기',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        await _tapVisible(tester, find.text('들어갈까?'));
        expect(find.text('모두 적재 가능!'), findsOneWidget);
        _expectResultSheet(tester, '모두 적재', labels: ['순서 가이드', '배치 저장']);
        final buttons = _sheetButtons(tester);
        expect(buttons['순서 가이드']!.$2, isA<OutlinedButton>());
        expect(buttons['배치 저장']!.$2, isA<ElevatedButton>());
        expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('확인')),
            findsNothing);
        await _closeSheetByX(tester);
        await _finish(tester);
      }, variant: _android);

      testWidgets('${entry.key}: 일부 적재 → 보조 "2열 +Ncm 적용"(초록 외곽선) 위, 주 "다시 배치"(파랑) 아래, 스크림 탭으로 닫힘',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        final depth = (TrunkSpace.sorento().d * 100).round() + 10;
        await addCustomBox(tester, label: '긴 짐', w: 100, d: depth, h: 25);
        await flushSnackBars(tester);
        await addCustomBox(tester, label: '작은 박스', w: 30, d: 30, h: 20);
        await flushSnackBars(tester);
        await _tapVisible(tester, find.text('들어갈까?'));
        expect(find.text('1/2개 적재 가능'), findsOneWidget);
        expect(_applyText(), findsOneWidget, reason: '2열 제안이 있다');
        final applyLabel = (_applyText().evaluate().single.widget as Text).data!;
        _expectResultSheet(tester, '일부 적재', labels: [applyLabel, '다시 배치']);
        final buttons = _sheetButtons(tester);
        expect(buttons[applyLabel]!.$2, isA<OutlinedButton>());
        expect(_sideOf(buttons[applyLabel]!.$2), _green);
        expect(buttons['다시 배치']!.$2, isA<ElevatedButton>());
        expect(_bgOf(buttons['다시 배치']!.$2), _blue);
        expect(buttons[applyLabel]!.$1.bottom, lessThanOrEqualTo(buttons['다시 배치']!.$1.top),
            reason: '보조가 주 위에');

        // 스크림(시트 밖) 탭으로 닫힌다
        final sheetTop = tester.getRect(find.byType(BottomSheet)).top;
        await tester.tapAt(Offset(20, math.min(100, sheetTop - 10)));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(boxesOf(tester), hasLength(2), reason: '닫기만 했다');
        await _finish(tester);
      }, variant: _android);

      testWidgets('${entry.key}: 적재 불가(2열 제안 없음) → 주 "확인"(파랑) 하나뿐, ✕ 도 있다',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        // 2열을 27cm 당겨도 안 들어가는 길이 (200cm)
        await addCustomBox(tester, label: '아주 긴 짐', w: 100, d: 200, h: 25);
        await flushSnackBars(tester);
        await _tapVisible(tester, find.text('들어갈까?'));
        expect(find.text('적재 불가'), findsOneWidget);
        expect(_applyText(), findsNothing, reason: '+27cm 로도 안 들어간다');
        _expectResultSheet(tester, '적재 불가', labels: ['확인']);
        final ok = _sheetButtons(tester)['확인']!;
        expect(ok.$2, isA<ElevatedButton>());
        expect(_bgOf(ok.$2), _blue);
        await _closeSheetByX(tester);
        await _finish(tester);
      }, variant: _android);
    }
  });

  // ═══════════════════ 10. 자동 배치 대안 시트 (사양 3.7) ═══════════════════
  group('10. 자동 배치 대안 시트', () {
    for (final entry in _portrait.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 전략 3종 카드 + 전체 폭 "이 배치 적용", 취소 없음, ✕ 는 자리를 바꾸지 않음',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        final before = _positions(tester);
        await _tapVisible(tester, find.text('자동 배치'));
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        for (final s in ['균형 배치', '최대 적재', '접근 우선']) {
          expect(find.descendant(of: sheet, matching: find.text(s)), findsWidgets, reason: s);
        }
        _expectResultSheet(tester, '자동 배치 대안', labels: ['이 배치 적용']);
        expect(find.text('취소'), findsNothing);
        await _closeSheetByX(tester);
        expect(_positions(tester), equals(before), reason: '✕ 는 배치를 바꾸지 않는다');
        await _finish(tester);
      }, variant: _android);
    }
  });

  // ═══════════════════ 11. SafeArea (사양 3.8) ═══════════════════
  group('11. SafeArea', () {
    testWidgets('390×844 + 하단 인셋 34: 초기 시트 ≈ 220+34, 결과 시트 버튼·목록 끝이 인셋 위에',
        (tester) async {
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      const inset = 34.0;

      final s0 = _sheetRect(tester);
      expect(s0.height, closeTo(_sheetInitialPx + inset, 1.5), reason: '초기 시트 $s0');
      expect(s0.bottom, kPhone.height, reason: '시트는 화면 바닥까지');
      // 빈 상태 버튼들이 인셋 위에 있다
      expect(tester.getRect(_textButton('저장된 배치 불러오기')).bottom,
          lessThanOrEqualTo(kPhone.height - inset));

      await addBundle(tester, '4인 가족 캠핑');
      await flushSnackBars(tester);

      // 결과 시트: 주 버튼 바닥 ≤ 화면 − 인셋 − 8
      await _tapVisible(tester, find.text('들어갈까?'));
      final buttons = _sheetButtons(tester);
      final primary = buttons.entries.where((e) => e.value.$2 is ElevatedButton).toList();
      expect(primary, hasLength(1));
      expect(primary.single.value.$1.bottom, lessThanOrEqualTo(kPhone.height - inset - 8),
          reason: '${primary.single.key} ${primary.single.value.$1}');
      await closeResult(tester);
      await flushSnackBars(tester);

      // 시트 목록 끝: 마지막 타일 아래 여백 ≥ 인셋
      await expandSheet(tester);
      final sheet = find.byType(BoxListPanel);
      for (var i = 0; i < 6; i++) {
        await tester.fling(sheet, const Offset(0, -400), 1500);
        await tester.pumpAndSettle();
      }
      final c = panelOf(tester).scrollController!;
      expect(c.position.maxScrollExtent, greaterThan(0), reason: '목록이 스크롤될 만큼 길다');
      expect(c.offset, closeTo(c.position.maxScrollExtent, 1), reason: '끝까지 스크롤');
      final lastLabel = boxesOf(tester).last.label;
      final lastCard = tester.getRect(
          find.ancestor(of: find.text(lastLabel).last, matching: find.byType(Card)).first);
      final sheetRect = _sheetRect(tester);
      expect(sheetRect.bottom - lastCard.bottom, greaterThanOrEqualTo(inset),
          reason: '마지막 타일 $lastCard / 시트 $sheetRect');
      await _finish(tester);
    }, variant: _android);

    testWidgets('390×844 + 하단 인셋 34: 자동 배치 대안 시트의 버튼도 인셋 위에', (tester) async {
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await _tapVisible(tester, find.text('자동 배치'));
      final apply = tester.getRect(_textButton('이 배치 적용'));
      expect(apply.bottom, lessThanOrEqualTo(kPhone.height - 34 - 8), reason: '$apply');
      await _closeSheetByX(tester);
      await _finish(tester);
    }, variant: _android);
  });

  // ═══════════════════ 12. 도움말 (사양 3.8) ═══════════════════
  group('12. 도움말 버튼', () {
    for (final entry in {..._portrait, '가로 844×390': _landscape}.entries) {
      final size = entry.value;
      testWidgets('${entry.key}: 첫 실행 직후 앱바 ? 를 누르면 제스처 다이얼로그(한 손가락 드래그)',
          (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        final help = find.widgetWithIcon(IconButton, Icons.help_outline);
        expect(help, findsOneWidget);
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('한 손가락 드래그'), findsOneWidget);
        expect(find.text('두 손가락'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }, variant: _android);

      testWidgets('${entry.key}: 첫 프레임부터 툴팁이 "조작법" 이다', (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        expect(find.byTooltip('키보드 단축키 (?)'), findsNothing);
        expect(find.byTooltip('조작법'), findsOneWidget);
      }, variant: _android);

      testWidgets('${entry.key}: 다시 빌드된 뒤에는 툴팁 "조작법" → 제스처 다이얼로그', (tester) async {
        await pumpApp(tester, size: size, prefs: seenPrefs());
        // 캔버스 탭(선택 갱신)으로 화면을 한 번 다시 빌드한다
        await tester.tapAt(canvasRect(tester).center);
        await tester.pumpAndSettle();
        expect(find.byTooltip('키보드 단축키 (?)'), findsNothing);
        await tester.tap(find.byTooltip('조작법'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('한 손가락 드래그'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }, variant: _android);
    }

    testWidgets('데스크톱 1280×960: "키보드 단축키 (?)" 그대로', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      expect(find.byTooltip('키보드 단축키 (?)'), findsOneWidget);
      expect(find.byTooltip('조작법'), findsNothing);
    }, variant: _android);
  });

  // ═══════════════════ 13. 폰 가로 844×390 ═══════════════════
  group('13. 폰 가로 844×390', () {
    testWidgets('판정은 시트, 선택 도구 띠 동작, 장비 선택은 전체 화면 페이지, overflow 0', (tester) async {
      await _collecting(tester, (e) async {
        e.stage = '빈 상태';
        await pumpApp(tester, size: _landscape, prefs: seenPrefs());
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(panelOf(tester).compact, isTrue);

        e.stage = '장비 선택 페이지';
        await openAddDialog(tester);
        final picker = find.byType(AddBoxDialog);
        expect(find.descendant(of: picker, matching: find.byType(Scaffold)), findsOneWidget);
        expect(find.text('장비 선택'), findsOneWidget);
        expect(tester.getRect(picker).size, _landscape);
        await tester.ensureVisible(find.text('솔로 백패킹'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('솔로 백패킹'));
        await tester.pumpAndSettle();
        expect(find.text('추가 (6개)'), findsOneWidget);
        await tester.tap(addConfirmButton());
        await tester.pumpAndSettle();
        expect(boxesOf(tester), hasLength(6));
        await flushSnackBars(tester);

        e.stage = '판정 시트';
        await tester.tap(find.text('들어갈까?'));
        await tester.pumpAndSettle();
        expect(find.text('모두 적재 가능!'), findsOneWidget);
        _expectResultSheet(tester, '가로 판정', labels: ['순서 가이드', '배치 저장']);
        await _closeSheetByX(tester);

        e.stage = '선택 도구 띠';
        final b = await _tapHighestBox(tester);
        expect(panelOf(tester).selectedBoxId, isNotNull);
        expect(_toolbarShown(), isTrue);
        _expectToolbarPlacement(tester, reason: '가로');
        final sel = boxesOf(tester).firstWhere((x) => x.id == panelOf(tester).selectedBoxId);
        final r0 = sel.rotY;
        await tester.tap(find.byTooltip('선택한 짐 회전'));
        await tester.pumpAndSettle();
        expect((sel.rotY - r0 + 360) % 360, 90, reason: b.label);
        await tester.tap(find.byTooltip('선택 해제'));
        await tester.pumpAndSettle();
        expect(_toolbarHidden(), isTrue);

        e.stage = '자동 배치 대안 시트';
        await tester.tap(find.text('자동 배치'));
        await tester.pumpAndSettle();
        _expectResultSheet(tester, '가로 자동 배치', labels: ['이 배치 적용']);
        await _closeSheetByX(tester);
        await _finish(tester);
      });
    }, variant: _android);
  });

  // ═══════════════════ 14. 전 플로우 overflow 0 (사양 5절) ═══════════════════
  group('14. 전 플로우 overflow 0', () {
    for (final entry in {..._portrait, '가로 844×390': _landscape}.entries) {
      final size = entry.value;
      final portrait = size.width < 600;
      testWidgets('${entry.key}: 온보딩 → 장비 페이지 → 세트 → 판정 → 자동 배치 → 스텝 뷰 → 시트 올리고 내리기',
          (tester) async {
        await _collecting(tester, (e) async {
          e.stage = '온보딩';
          await pumpApp(tester, size: size);
          await _dismissOnboarding(tester);

          e.stage = '장비 페이지';
          await openAddDialog(tester);
          expect(
              find.descendant(of: find.byType(AddBoxDialog), matching: find.byType(Scaffold)),
              findsOneWidget);
          e.stage = '세트 추가';
          await tester.ensureVisible(find.text('4인 가족 캠핑'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('4인 가족 캠핑'));
          await tester.pumpAndSettle();
          await tester.tap(addConfirmButton());
          await tester.pumpAndSettle();
          expect(boxesOf(tester), hasLength(16));
          await flushSnackBars(tester);

          e.stage = '판정 시트';
          await _tapVisible(tester, find.text('들어갈까?'));
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.textContaining('적재 가능'), findsWidgets);
          await closeResult(tester);

          e.stage = '자동 배치 대안 → 적용';
          await _tapVisible(tester, find.text('자동 배치'));
          expect(find.byType(BottomSheet), findsOneWidget);
          await tester.tap(find.text('이 배치 적용'));
          await tester.pumpAndSettle();
          e.stage = '적용 뒤 판정 시트';
          expect(find.byType(BottomSheet), findsOneWidget);
          await closeResult(tester);
          await flushSnackBars(tester);

          e.stage = '스텝 뷰';
          await _tapVisible(tester, find.byTooltip('적재 순서 가이드'));
          expect(find.textContaining('STEP 1 / '), findsOneWidget);
          await tester.tap(stepButton(Icons.chevron_right));
          await tester.pumpAndSettle();
          expect(find.textContaining('STEP 2 / '), findsOneWidget);
          await tester.tap(find.byTooltip('스텝뷰 닫기'));
          await tester.pumpAndSettle();

          e.stage = '짐 선택 + 도구 띠';
          await _tapHighestBox(tester);
          expect(_toolbarShown(), isTrue);
          await tester.tap(find.byTooltip('선택 해제'));
          await tester.pumpAndSettle();

          if (portrait) {
            e.stage = '시트 올리기';
            await expandSheet(tester);
            expect(_sheetRect(tester).height, closeTo(_bodyH(size) * _sheetMax, 2));
            e.stage = '목록 끝까지';
            final sheet = find.byType(BoxListPanel);
            for (var i = 0; i < 4; i++) {
              await tester.fling(sheet, const Offset(0, -300), 1000);
              await tester.pumpAndSettle();
            }
            e.stage = '시트 내리기';
            for (var i = 0; i < 10; i++) {
              await tester.fling(sheet, const Offset(0, 300), 1000);
              await tester.pumpAndSettle();
            }
            expect(_sheetRect(tester).height, closeTo(_bodyH(size) * _sheetMin, 2));
            expect(canvasRect(tester).bottom, closeTo(_sheetRect(tester).top, 2));
          }
          await _finish(tester);
        });
      }, variant: _android);
    }
  });
  _reviewFixTests();
}

// ═══════════════════ 15. UX 리뷰(2026-09-20)로 고친 것 ═══════════════════
// 실제 빌드 리뷰가 찾은 문제의 회귀 가드. 사양: backlog/phone-ux-w9.md 6절.
void _reviewFixTests() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  group('15. 리뷰 수정 회귀', () {
    testWidgets('들어갈까? 는 지금 배치를 판정한다: 손으로 테일게이트를 막으면 "지금 배치: 문제" + 이 배치 적용',
        (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addCustomBox(tester, label: '작은 박스', w: 30, d: 30, h: 20);
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '세운 짐', w: 40, d: 40, h: 70);
      await flushSnackBars(tester);
      // 높은 짐을 손으로 테일게이트 끝까지 끌어 닫힘을 막는다 (화면 아래 = z+)
      final space = spaceOf(tester);
      final tall = boxesOf(tester).firstWhere((b) => b.label == '세운 짐');
      await slowDrag(tester, topCenterOf(tester, tall), const Offset(0, 260),
          kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      final blocked = painterOf(tester).tailgateBlockedIds.isNotEmpty ||
          painterOf(tester).collidingBoxIds.isNotEmpty;
      expect(blocked, isTrue, reason: '짐이 테일게이트에 걸리거나 충돌해야 한다 (z=${tall.z}, d=${space.d})');
      await flushSnackBars(tester);
      // 알약도 초록이 아니다
      final (pill, kind) = TrunkPainter3D.captionStatus(space, boxesOf(tester),
          painterOf(tester).tailgateBlockedIds,
          collidingIds: painterOf(tester).collidingBoxIds);
      expect(kind, isNot(CaptionStatusKind.ok), reason: pill);

      await tester.tap(find.text('들어갈까?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('지금 배치: 문제'), findsOneWidget);
      expect(find.text('모두 적재 가능!'), findsNothing);
      expect(find.text('이 배치 적용'), findsOneWidget);
      await tester.tap(find.text('이 배치 적용'));
      await tester.pumpAndSettle();
      // 적용 뒤에는 유효한 배치 + 판정
      expect(painterOf(tester).tailgateBlockedIds, isEmpty);
      expectSceneValid(tester);
      await closeResult(tester);
      await flushSnackBars(tester);
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('일부만 들어갈 때 스낵바는 최대 두 항목 + "외 N개", 자세히 버튼이 판정 시트를 연다',
        (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addBundle(tester, '4인 가족 캠핑');
      await flushSnackBars(tester);
      await addBundle(tester, '4인 가족 캠핑'); // 32개: 다 안 들어간다
      final snack = snackTexts(tester).firstWhere((t) => t.contains('적재 불가: '));
      expect('\n'.allMatches(snack).length, lessThanOrEqualTo(1), reason: '두 줄 이하: $snack');
      expect(snack.length, lessThan(160), reason: '글 벽이 아니다: $snack');
      expect(find.text('자세히'), findsOneWidget);
      await tester.tap(find.text('자세히'));
      await tester.pumpAndSettle();
      expect(find.textContaining('개 적재 가능'), findsOneWidget);
      // 같은 이름·같은 사유는 "×N" 으로 묶인다
      expect(find.textContaining('×'), findsWidgets);
      await closeResult(tester);
      await flushSnackBars(tester);
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('짐이 못 실릴 때 칩·상태 줄은 "실은/전체" 로 세고, 타일은 "안 들어감" 태그', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addCustomBox(tester, label: '작은 박스', w: 30, d: 30, h: 20);
      await flushSnackBars(tester);
      await addCustomBox(tester, label: '냉장고', w: 200, d: 150, h: 120);
      await flushSnackBars(tester);
      expect(find.textContaining('1/2개'), findsWidgets);
      expect(find.text('안 들어감'), findsOneWidget);
      expect(find.byTooltip('충돌 감지: 다른 박스 또는 경계와 겹침'), findsNothing);
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('장비 페이지에서 카테고리를 바꿔도 선택이 남는다 (세트 + 캐리어)', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await openAddDialog(tester);
      await tester.tap(find.text('4인 가족 캠핑'));
      await tester.pumpAndSettle();
      expect(find.text('16개 선택'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '캐리어'));
      await tester.pumpAndSettle();
      expect(find.text('16개 선택'), findsOneWidget, reason: '카테고리 전환이 선택을 지우지 않는다');
      final first = presetRowLabels(tester).first;
      await tester.tap(dialogLabel(first));
      await tester.pumpAndSettle();
      expect(find.text('17개 선택'), findsOneWidget);
      expect(find.text('추가 (17개)'), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('검색은 서브카테고리·동의어도 맞춘다: "쿨러" 에 아이스박스가 나온다', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await openAddDialog(tester);
      final search = find.descendant(
          of: find.byType(AddBoxDialog), matching: find.byType(TextField));
      await tester.enterText(search, '쿨러');
      await tester.pumpAndSettle();
      final labels = presetRowLabels(tester);
      expect(labels.any((l) => l.contains('아이스박스')), isTrue, reason: '$labels');
      await tester.enterText(search, 'helinox');
      await tester.pumpAndSettle();
      expect(presetRowLabels(tester).any((l) => l.contains('헬리녹스')), isTrue);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('삭제로 받침이 사라져도 짐이 휠하우스 속으로 떨어지지 않는다', (tester) async {
      final space = TrunkSpace.sorento();
      final wh = space.leftWheelhouse;
      // 휠하우스 옆 바닥의 받침 상자 + 그 위에 휠하우스 쪽으로 걸친 상자
      await pumpAppWithScene(tester, [
        mkBox('box-001', '받침', w: 0.40, d: 0.40, h: 0.30, x: wh.w, z: wh.zStart + 0.25),
        mkBox('box-002', '걸침', w: 0.40, d: 0.40, h: 0.20,
            x: wh.w - 0.10, y: 0.30, z: wh.zStart + 0.25),
      ], size: kPhone);
      expectSceneValid(tester);
      await tapTile(tester, '받침');
      await tester.tap(find.byTooltip('선택한 짐 삭제'));
      await tester.pumpAndSettle();
      final left = boxesOf(tester).single;
      expect(left.y, greaterThanOrEqualTo(wh.h - 1e-6),
          reason: '휠하우스 위(${wh.h}) 에 얹히거나 그대로: y=${left.y}');
      expect(painterOf(tester).collidingBoxIds, isEmpty);
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('자동 배치 대안: 하나도 못 넣는 배치는 "이 배치 적용" 이 비활성', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addCustomBox(tester, label: '냉장고', w: 200, d: 150, h: 120);
      await flushSnackBars(tester);
      await tester.tap(find.text('자동 배치'));
      await tester.pumpAndSettle();
      final apply = tester.widget<ElevatedButton>(find.ancestor(
          of: find.text('이 배치 적용'), matching: find.byType(ElevatedButton)));
      expect(apply.enabled, isFalse);
      await closeResult(tester);
      await flushAutosave(tester);
    }, variant: android);

    testWidgets('가로→세로 복귀: 짐이 있으면 시트가 45% 로 다시 열린다', (tester) async {
      await pumpApp(tester, size: kPhone, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      tester.view.physicalSize = kPhone;
      await tester.pumpAndSettle();
      final body = kPhone.height - kToolbarHeight;
      expect(tester.getRect(find.byType(BoxListPanel)).height, closeTo(body * 0.45, 2));
      await flushAutosave(tester);
    }, variant: android);
  });
}
