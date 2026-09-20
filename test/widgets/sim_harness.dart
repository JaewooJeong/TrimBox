// SimulatorScreen 위젯 플로우 테스트 공용 도구 (테스트 파일 아님).
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimbox/main.dart';
import 'package:trimbox/models/scene.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';
import 'package:trimbox/render3d/vec3.dart';
import 'package:trimbox/screens/simulator_screen.dart';
import 'package:trimbox/utils/collision.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';
import 'package:trimbox/widgets/box_list_panel.dart';

/// 알려진 결함을 재현하는 테스트를 켠다:
///   flutter test --dart-define=RUN_KNOWN_BUGS=true test/widgets
/// 기본은 건너뛴다 (스위트를 초록으로 유지). 결함을 고치면 knownBug → testWidgets 로 바꾼다.
const bool runKnownBugs = bool.fromEnvironment('RUN_KNOWN_BUGS');

/// 실제 결함을 드러내는 테스트. [bug] 는 한 줄 설명 (건너뛴 사유로 이름에 남는다).
void knownBug(String description, String bug, WidgetTesterCallback body) {
  testWidgets('$description  [skip: BUG: $bug]', body, skip: !runKnownBugs);
}

const Size kDesktop = Size(1280, 960);
const Size kTablet = Size(820, 1180);
const Size kPhone = Size(390, 844);
const Size kPhoneShort = Size(390, 600);

/// 실제 글꼴을 로드했는가. flutter_test 기본 글꼴은 모든 글자가 1em 정사각형이라
/// 라틴 문자·숫자가 실제의 약 2배 폭으로 재어져 RenderFlex overflow 가 거짓 양성으로 난다.
bool realFontsLoaded = false;

/// 한글 글리프까지 실제 폭으로 재는가 (false 면 한글이 좁은 .notdef 로 재어져
/// overflow 검사가 느슨해진다 — 거짓 실패는 없다).
bool koreanFontLoaded = false;

/// 앱 기본 패밀리('Roboto')에 실제 글꼴을 등록한다.
/// 1순위: 한글+라틴이 다 있는 시스템 글꼴 (Windows 맑은 고딕 — 한글 1em, 라틴 ≈ Roboto 폭).
/// 2순위: Flutter SDK 캐시의 Roboto (한글은 .notdef).
/// 둘 다 없으면 테스트 기본 글꼴 그대로 (overflow 검사는 [realFontsLoaded] 로 건너뛴다).
Future<void> loadRealFonts() async {
  if (realFontsLoaded) return;
  Future<bool> loadFamily(List<String> paths) async {
    final files = paths.map(File.new).where((f) => f.existsSync()).toList();
    if (files.isEmpty) return false;
    // 'Roboto' = Android·웹 기본, 'Segoe UI' = Windows 플랫폼 타이포그래피의 패밀리
    // (TargetPlatformVariant 로 데스크톱을 흉내 낼 때도 같은 글꼴로 재도록)
    for (final family in ['Roboto', 'Segoe UI']) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = f.readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }
    return true;
  }

  final winFonts = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
  if (await loadFamily(['$winFonts/malgun.ttf', '$winFonts/malgunbd.ttf'])) {
    realFontsLoaded = true;
    koreanFontLoaded = true;
    return;
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final dirs = <String>[
    if (root != null) '$root/bin/cache/artifacts/material_fonts',
    // flutter_tester: <root>/bin/cache/artifacts/engine/<platform>/flutter_tester
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  for (final dir in dirs) {
    if (await loadFamily([
      '$dir/roboto-regular.ttf',
      '$dir/roboto-medium.ttf',
      '$dir/roboto-bold.ttf',
    ])) {
      realFontsLoaded = true;
      return;
    }
  }
}

/// 기본 테스트 글꼴(라틴 2배 폭)밖에 없을 때는 overflow 오류만 걸러낸다.
/// 실제 글꼴이 있으면 아무것도 하지 않는다 — overflow 는 그대로 테스트 실패.
void tolerateOverflowIfNoRealFonts() {
  if (realFontsLoaded) return;
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// scene_storage.dart 의 키 (비공개 상수라 여기 복제)
const String kAutosaveKey = 'trimbox_autosave';
const String kOnboardedKey = 'trimbox_onboarded';

/// 앱을 띄운다. [prefs] 가 null 이면 저장소를 건드리지 않는다 (재시작 시나리오).
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = kDesktop,
  Map<String, Object>? prefs = const {},
}) async {
  tolerateOverflowIfNoRealFonts();
  if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TrimBoxApp(key: UniqueKey()));
  // _restoreSession 의 비동기 저장소 읽기 + (있다면) 복원 뒤 재배치
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

/// 앱을 내렸다가 같은 저장소로 다시 띄운다 (새 State).
Future<void> restartApp(WidgetTester tester, {Size size = kDesktop}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await pumpApp(tester, size: size, prefs: null);
}

/// 자동 저장 타이머(800ms)와 저장 Future 를 흘려보낸다.
Future<void> flushAutosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 50));
}

/// 떠 있는 스낵바를 끝까지 흘려보낸다.
Future<void> flushSnackBars(WidgetTester tester) async {
  for (var i = 0; i < 6 && find.byType(SnackBar).evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }
}

BoxListPanel panelOf(WidgetTester tester) =>
    tester.widget<BoxListPanel>(find.byType(BoxListPanel));

/// 화면 State 의 실제 박스 리스트 (패널에 같은 참조가 전달된다)
List<TrimBox> boxesOf(WidgetTester tester) => panelOf(tester).boxes;

TrunkSpace spaceOf(WidgetTester tester) => panelOf(tester).space;

TrunkPainter3D painterOf(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  return paints.map((p) => p.painter).whereType<TrunkPainter3D>().single;
}

/// 화면에 떠 있는 모든 Text 문자열
List<String> allTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];

/// 스낵바 본문들
List<String> snackTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.descendant(
          of: find.byType(SnackBar), matching: find.byType(Text))))
        t.data ?? '',
    ];

/// 트렁크 안에 있는 (주차되지 않은) 박스
List<TrimBox> insideBoxes(WidgetTester tester) {
  final s = spaceOf(tester);
  return boxesOf(tester).where((b) => b.z < s.d - 0.005).toList();
}

/// 현재 화면 상태가 물리적으로 유효한가: 충돌 0, 부양 0
void expectSceneValid(WidgetTester tester, {String reason = ''}) {
  final s = spaceOf(tester);
  final boxes = boxesOf(tester);
  final det = CollisionDetector(s);
  final problems = <String>[];
  for (final b in boxes) {
    final why = det.describe(b, boxes);
    if (why.isNotEmpty) problems.add('${b.label}: ${why.join(', ')}');
  }
  expect(problems, isEmpty, reason: 'collision problems $reason');
  expect(det.findAllCollisions(boxes), isEmpty, reason: reason);
  for (final b in boxes) {
    expect(SupportRule.isSupported(b, boxes, s), isTrue,
        reason: '${b.label} floats at y=${b.y} $reason');
  }
}

/// 첫 실행 온보딩을 본 상태의 저장소
Map<String, Object> seenPrefs([Map<String, Object> extra = const {}]) =>
    {kOnboardedKey: true, ...extra};

/// 추가 다이얼로그를 연다 (빈 상태 CTA 또는 액션바 버튼)
Future<void> openAddDialog(WidgetTester tester) async {
  final cta = find.text('캠핑 장비 선택하기');
  if (cta.evaluate().isNotEmpty) {
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
  } else {
    final add = find.descendant(
        of: find.byType(BoxListPanel), matching: find.text('박스 추가'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
  }
  await tester.pumpAndSettle();
  expect(find.byType(AddBoxDialog), findsOneWidget);
}

/// 다이얼로그의 확인 버튼 ('추가' 또는 '추가 (N개)')
Finder addConfirmButton() => find.descendant(
    of: find.byType(AddBoxDialog),
    matching: find.textContaining(RegExp(r'^추가( \(\d+개\))?$')));

/// 번들을 골라 추가한다. 자동 배치가 동기 실행되므로 실제 시간이 걸린다.
Future<void> addBundle(WidgetTester tester, String bundleName) async {
  await openAddDialog(tester);
  // 좁은 다이얼로그에서는 세트 카드 줄이 가로 스크롤이다
  await tester.ensureVisible(find.text(bundleName));
  await tester.pumpAndSettle();
  await tester.tap(find.text(bundleName));
  await tester.pumpAndSettle();
  await tester.tap(addConfirmButton());
  await tester.pumpAndSettle();
}

/// 다이얼로그 안의 Text 위젯만 (검색창의 EditableText·힌트 제외) 정확히 일치
Finder dialogLabel(String label) => find.descendant(
    of: find.byType(AddBoxDialog),
    matching: find.byWidgetPredicate(
        (w) => w is Text && w.data == label && w.maxLines != 1));

/// 현재 보이는 프리셋 행의 라벨들 (체크박스가 있는 행)
List<String> presetRowLabels(WidgetTester tester) {
  final out = <String>[];
  final boxes = find.descendant(
      of: find.byType(AddBoxDialog), matching: find.byType(Checkbox));
  for (final e in boxes.evaluate()) {
    final row = find
        .ancestor(of: find.byElementPredicate((x) => x == e), matching: find.byType(Row))
        .first;
    final text = tester.widget<Text>(
        find.descendant(of: row, matching: find.byType(Text)).first);
    out.add(text.data ?? '');
  }
  return out;
}

/// 검색으로 프리셋 하나를 골라 추가한다.
Future<void> addPresetBySearch(WidgetTester tester, String label) async {
  await openAddDialog(tester);
  await tester.enterText(
      find.descendant(
          of: find.byType(AddBoxDialog), matching: find.byType(TextField)),
      label);
  await tester.pumpAndSettle();
  await tester.tap(dialogLabel(label));
  await tester.pumpAndSettle();
  await tester.tap(addConfirmButton());
  await tester.pumpAndSettle();
}

/// 직접 입력으로 박스 하나 추가 (cm)
Future<void> addCustomBox(WidgetTester tester,
    {required String label,
    required int w,
    required int d,
    required int h}) async {
  await openAddDialog(tester);
  await tester.tap(find.widgetWithText(ChoiceChip, '직접 입력'));
  await tester.pumpAndSettle();
  Finder field(String l) => find.descendant(
      of: find.byType(AddBoxDialog),
      matching: find.widgetWithText(TextField, l));
  await tester.enterText(field('라벨'), label);
  await tester.enterText(field('가로(cm)'), '$w');
  await tester.enterText(field('세로(cm)'), '$d');
  await tester.enterText(field('높이(cm)'), '$h');
  await tester.tap(addConfirmButton());
  await tester.pumpAndSettle();
}

/// 패널 목록에서 라벨로 박스 타일을 탭 (선택 토글)
Future<void> tapTile(WidgetTester tester, String label) async {
  final f = find.descendant(
      of: find.byType(BoxListPanel), matching: find.text(label));
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

/// 캔버스의 키 입력 포커스 노드 (SimulatorScreen 이 debugLabel 'trunk-canvas' 로 만든다)
FocusNode canvasFocusNode(WidgetTester tester) => tester
    .widget<Focus>(find.descendant(
        of: find.byType(SimulatorScreen),
        matching: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'trunk-canvas')))
    .focusNode!;

/// 캔버스에 포커스를 돌려놓는다 (다이얼로그·메뉴를 닫은 직후 등).
///
/// 캔버스는 처리한 키를 소비하므로 화살표를 눌러도 포커스가 앱바·패널 버튼으로 새지
/// 않는다 ("화살표 키가 캔버스 포커스를 빼앗기지 않는다" 테스트가 [keepCanvasFocus]
/// 없이 확인한다).
Future<void> focusCanvas(WidgetTester tester) async {
  final node = canvasFocusNode(tester);
  if (!node.hasPrimaryFocus) {
    node.requestFocus();
    await tester.pump();
  }
}

Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key,
    {String? character, int times = 1, bool keepCanvasFocus = true}) async {
  for (var i = 0; i < times; i++) {
    if (keepCanvasFocus) await focusCanvas(tester);
    await tester.sendKeyDownEvent(key, character: character);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
  }
}

Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false}) async {
  await focusCanvas(tester);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// 앱바의 2열 슬라이드 컨트롤
Finder seatSlideControl() => find.byTooltip('2열 시트 슬라이드');

/// 앱바의 차종 버튼. 라벨은 화면 폭(폰은 차종명만)과 2열 슬라이드(바닥 깊이)에 따라
/// 달라지므로 글자가 아니라 툴팁으로 찾는다.
Finder presetButton() => find.byTooltip('차종 선택');

/// 열린 차종 메뉴의 항목 (행은 "차종명 / 설명" 두 줄이라 글자가 아니라 값으로 찾는다)
Finder presetMenuItem(TrunkPreset preset) => find.byWidgetPredicate(
    (w) => w is PopupMenuItem<TrunkPreset> && w.value == preset);

/// 차종 메뉴를 열고 항목을 고른다
Future<void> choosePreset(WidgetTester tester, TrunkPreset preset) async {
  await tester.tap(presetButton());
  await tester.pumpAndSettle();
  await tester.tap(presetMenuItem(preset));
  await tester.pumpAndSettle();
}

/// 패널 상태 줄의 세 상태
enum StatusState { ok, advice, problems }

StatusState statusOf(WidgetTester tester) {
  final p = find.byType(BoxListPanel);
  bool has(IconData i) =>
      find.descendant(of: p, matching: find.byIcon(i)).evaluate().isNotEmpty;
  if (find
      .descendant(of: p, matching: find.text('배치 문제 없음 · 테일게이트 닫힘'))
      .evaluate()
      .isNotEmpty) {
    return StatusState.ok;
  }
  if (has(Icons.lightbulb_outline)) return StatusState.advice;
  return StatusState.problems;
}

/// 테스트용 박스
TrimBox mkBox(
  String id,
  String label, {
  required double w,
  required double d,
  required double h,
  double x = 0,
  double y = 0,
  double z = 0,
  int rotY = 0,
  double weightKg = 0,
  bool soft = false,
  bool upright = false,
  bool access = false,
}) =>
    TrimBox(
      id: id,
      label: label,
      w: w,
      d: d,
      h: h,
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      color: const Color(0xFFBAE1FF),
      weightKg: weightKg,
      soft: soft,
      keepUpright: upright,
      accessPriority: access,
    );

/// 자동 저장 형식의 씬 JSON (현재 프리셋 정의 그대로면 복원 때 재배치되지 않는다)
String sceneJson(List<TrimBox> boxes, {TrunkSpace? space}) =>
    Scene(space: space ?? TrunkSpace.sorento(), boxes: boxes).toJsonString();

/// 만든 씬을 자동 저장으로 심어 앱을 띄운다 (자리 그대로 복원).
Future<void> pumpAppWithScene(WidgetTester tester, List<TrimBox> boxes,
    {TrunkSpace? space, Size size = kDesktop}) async {
  await pumpApp(tester,
      size: size,
      prefs: seenPrefs({kAutosaveKey: sceneJson(boxes, space: space)}));
}

/// 스텝 뷰의 이전/다음 버튼 (상태 줄의 작은 chevron 과 구분: size 28)
Finder stepButton(IconData icon) => find.byWidgetPredicate(
    (w) => w is Icon && w.icon == icon && w.size == 28);

/// 판정·자동배치 결과를 닫는다. 데스크톱은 다이얼로그의 '확인'(또는 '취소'), 폰은 아래
/// 시트의 ✕('닫기') — 폰 시트에는 확인 버튼이 없다 (`backlog/phone-ux-w9.md` 3.7).
Future<void> closeResult(WidgetTester tester) async {
  final ok = find.text('확인');
  final cancel = find.text('취소');
  final close = find.byTooltip('닫기');
  if (ok.evaluate().isNotEmpty) {
    await tester.tap(ok.last);
  } else if (cancel.evaluate().isNotEmpty) {
    await tester.tap(cancel.last);
  } else {
    expect(close, findsWidgets, reason: '결과 다이얼로그/시트가 열려 있어야 한다');
    await tester.tap(close.last);
  }
  await tester.pumpAndSettle();
}

/// 결과가 아래 시트로 열려 있는가 (폰)
bool resultIsSheet(WidgetTester tester) =>
    find.byType(BottomSheet).evaluate().isNotEmpty;

/// 패널의 도구 동작을 누른다. 데스크톱·폰 가로는 툴팁 버튼, 폰 세로 시트는 '더 보기'(⋯)
/// 메뉴 안의 항목(배치 저장·불러오기·스크린샷·공유 카드).
Future<void> tapPanelAction(WidgetTester tester, String label) async {
  final direct = find.byTooltip(label);
  if (direct.evaluate().isNotEmpty) {
    await tester.ensureVisible(direct.first);
    await tester.pumpAndSettle();
    await tester.tap(direct.first);
    await tester.pumpAndSettle();
    return;
  }
  final more = find.byTooltip('더 보기');
  expect(more, findsOneWidget, reason: '$label 버튼도 ⋯ 메뉴도 없다');
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  await tester.tap(more);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 앱바 도움말 버튼의 툴팁 (폰은 조작법, 그 외는 키보드 단축키)
String helpTooltip(Size size) {
  final phoneLandscape = size.width > size.height && size.height < 500;
  return (size.width < 600 || phoneLandscape) ? '조작법' : '키보드 단축키 (?)';
}

/// 폰 레이아웃의 시트를 끝까지 올린다. (tester.drag 의 한 번에 점프하는 이동은
/// DraggableScrollableSheet 를 움직이지 못한다 → fling 을 쓴다.)
Future<void> expandSheet(WidgetTester tester) async {
  final sheet = find.byType(BoxListPanel);
  // 안쪽 목록이 스크롤돼 있으면(예: ensureVisible 뒤) 위로 끌어도 시트 대신 목록이 움직인다
  final c = panelOf(tester).scrollController;
  if (c != null && c.hasClients && c.offset > 0) {
    c.jumpTo(0);
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 8; i++) {
    final before = tester.getRect(sheet).top;
    await tester.flingFrom(tester.getRect(sheet).topCenter + const Offset(0, 8),
        const Offset(0, -300), 1000);
    await tester.pumpAndSettle();
    if ((tester.getRect(sheet).top - before).abs() < 1) break;
  }
}

/// 3D 캔버스(CustomPaint)의 화면 영역
Rect canvasRect(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is TrunkPainter3D));

/// 월드 좌표 → 화면(글로벌) 좌표. 현재 카메라로 투영하므로 고정 픽셀에 의존하지 않는다.
Offset screenOf(WidgetTester tester, Vec3 world) {
  final r = canvasRect(tester);
  final p = painterOf(tester).camera.project(world, r.size);
  if (p == null) throw StateError('카메라 뒤: $world');
  return r.topLeft + p.screen;
}

/// 박스 윗면 중심의 화면 좌표
Offset topCenterOf(WidgetTester tester, TrimBox b) => screenOf(
    tester, Vec3(b.x + b.effectiveW / 2, b.top, b.z + b.effectiveD / 2));

/// 여러 번의 작은 이동으로 끄는 드래그 (마우스/터치 선택 가능).
/// tester.timedDragFrom 은 항상 터치다.
Future<void> slowDrag(
  WidgetTester tester,
  Offset from,
  Offset delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
  int steps = 24,
}) async {
  final g = await tester.startGesture(from, kind: kind);
  for (var i = 0; i < steps; i++) {
    await g.moveBy(delta / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}
