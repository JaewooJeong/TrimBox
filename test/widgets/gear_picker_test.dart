// 장비 선택 전체 화면 페이지(폰) — showGearPicker(fullScreen: true) → AddBoxDialog(fullScreen: true).
// 폰 두 크기(390×844, 360×640)에서 열기·세트·검색·직접 입력·닫기·키보드 인셋·탭 영역을 확인하고,
// 매 테스트에서 RenderFlex overflow 등 FlutterError 가 하나도 없는지 모은다.
// 실제 글꼴(sim_harness.loadRealFonts)이 없으면 overflow 검사만 건너뛴다 (거짓 양성 방지).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'sim_harness.dart';

const _sizes = <String, Size>{
  '폰 390×844': Size(390, 844),
  '작은 폰 360×640': Size(360, 640),
};

/// 키보드 높이 (논리 px, dpr 1)
const double _keyboard = 300;

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
  WidgetTester tester,
  Future<void> Function(_Errors e) body,
) async {
  final e = _Errors()..install();
  try {
    await body(e);
  } finally {
    e.restore();
  }
  expect(e.found, isEmpty, reason: e.found.join('\n'));
}

/// showGearPicker 의 결과. [_returned] 가 false 면 아직 열려 있다.
List<Map<String, dynamic>>? _result;
bool _returned = false;

/// 호스트 화면: '열기' 를 누르면 [fullScreen] 모드로 장비 선택을 연다.
Widget _host({required bool fullScreen}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await showGearPicker(ctx, fullScreen: fullScreen);
              _result = r;
              _returned = true;
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
}

/// 호스트를 띄우고 장비 선택을 연다.
Future<void> _open(
  WidgetTester tester,
  Size size, {
  bool fullScreen = true,
}) async {
  _result = null;
  _returned = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(fullScreen: fullScreen));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  expect(find.byType(AddBoxDialog), findsOneWidget);
}

/// 이미 띄운 호스트에서 다시 연다 (닫힌 뒤).
Future<void> _reopen(WidgetTester tester) async {
  _result = null;
  _returned = false;
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  expect(find.byType(AddBoxDialog), findsOneWidget);
}

Finder _inPicker(Finder f) =>
    find.descendant(of: find.byType(AddBoxDialog), matching: f);

Finder _searchField() => _inPicker(find.byType(TextField));

Finder _listView() => _inPicker(find.byType(ListView));

/// 세트 카드를 눌러 선택한다 (좁은 화면에서는 가로 스크롤 줄).
Future<void> _tapBundle(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// 직접 입력 탭으로 가서 값을 채운다.
Future<void> _fillCustom(
  WidgetTester tester, {
  String label = '내 박스',
  String w = '50',
  String d = '40',
  String h = '30',
}) async {
  await tester.tap(find.widgetWithText(ChoiceChip, '직접 입력'));
  await tester.pumpAndSettle();
  Finder field(String l) => _inPicker(find.widgetWithText(TextField, l));
  await tester.enterText(field('라벨'), label);
  await tester.enterText(field('가로(cm)'), w);
  await tester.enterText(field('세로(cm)'), d);
  await tester.enterText(field('높이(cm)'), h);
  await tester.pumpAndSettle();
}

/// 세트를 골라 추가했을 때의 결과 (호스트를 새로 띄운다).
Future<List<Map<String, dynamic>>> _bundleResult(
  WidgetTester tester,
  Size size, {
  required bool fullScreen,
  required String bundle,
}) async {
  await _open(tester, size, fullScreen: fullScreen);
  await _tapBundle(tester, bundle);
  await tester.tap(addConfirmButton());
  await tester.pumpAndSettle();
  expect(_returned, isTrue);
  expect(_result, isNotNull);
  return _result!;
}

/// 키보드가 올라온 것으로 친다.
void _showKeyboard(WidgetTester tester) {
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  addTearDown(tester.view.resetViewInsets);
}

/// 앱바 칩 "N개 선택" 의 N (없으면 0)
int _selectedCount(WidgetTester tester) {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final m = RegExp(r'^(\d+)개 선택$').firstMatch(w.data ?? '');
    if (m != null) return int.parse(m.group(1)!);
  }
  return 0;
}

void main() {
  setUpAll(loadRealFonts);

  for (final entry in _sizes.entries) {
    final name = entry.key;
    final size = entry.value;

    group('장비 선택 페이지 — $name', () {
      testWidgets('1. 라우트 페이지로 열린다: Scaffold·제목 "장비 선택"·취소 없음', (tester) async {
        await _collecting(tester, (e) async {
          await _open(tester, size);
          expect(_inPicker(find.byType(Scaffold)), findsOneWidget);
          expect(_inPicker(find.byType(Dialog)), findsNothing);
          expect(_inPicker(find.byType(AppBar)), findsOneWidget);
          expect(find.text('장비 선택'), findsOneWidget);
          expect(find.text('박스 추가'), findsNothing);
          expect(find.text('취소'), findsNothing);
          expect(find.byTooltip('닫기'), findsOneWidget);
          // 아직 아무것도 안 골랐다: 알약 없음, 추가 비활성
          expect(find.textContaining('개 선택'), findsNothing);
          final add = tester.widget<ElevatedButton>(
            _inPicker(find.widgetWithText(ElevatedButton, '추가')),
          );
          expect(add.onPressed, isNull);
          expect(find.text('선택 해제'), findsNothing);
          // 페이지 전체 폭을 쓴다 (다이얼로그의 좌우 16px 여백이 없다)
          final page = tester.getRect(_inPicker(find.byType(Scaffold)));
          expect(page.width, size.width);
          expect(page.height, size.height);
          // 하단 바의 추가 버튼은 전체 폭·48px
          final addRect = tester.getRect(
            _inPicker(find.byType(ElevatedButton)),
          );
          expect(addRect.height, greaterThanOrEqualTo(48));
          expect(addRect.width, greaterThanOrEqualTo(size.width - 40));
          expect(addRect.bottom, lessThanOrEqualTo(size.height));
          // 세트는 목록 맨 위에 있다
          expect(find.text('추천 세트'), findsOneWidget);
          expect(find.text('4인 가족 캠핑'), findsOneWidget);
        });
      });

      testWidgets('2. 세트 "4인 가족 캠핑" → 16개 선택·추가 (16개) → 다이얼로그와 같은 결과', (
        tester,
      ) async {
        await _collecting(tester, (e) async {
          e.stage = '페이지';
          await _open(tester, size);
          await _tapBundle(tester, '4인 가족 캠핑');
          expect(find.text('16개 선택'), findsOneWidget);
          expect(find.text('추가 (16개)'), findsOneWidget);
          expect(find.text('선택 해제'), findsOneWidget);
          // 알약은 앱바 안에 있다
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text('16개 선택'),
            ),
            findsOneWidget,
          );
          await tester.tap(addConfirmButton());
          await tester.pumpAndSettle();
          expect(find.byType(AddBoxDialog), findsNothing);
          expect(_returned, isTrue);
          final page = _result!;
          expect(page, hasLength(16));
          for (final m in page) {
            expect(m.keys, containsAll(['w', 'd', 'h', 'label', 'category']));
            // 이름 있는 장비는 물리 속성도 같이 온다
            expect(
              m.keys,
              containsAll(['weight', 'soft', 'compress', 'upright', 'access']),
            );
            expect(m['w'], isA<double>());
            expect(m['category'], BoxCategory.camping.index);
          }
          expect(page.first['label'], '코베아 네스트W (4인 거실형)');

          e.stage = '다이얼로그';
          final dialog = await _bundleResult(
            tester,
            size,
            fullScreen: false,
            bundle: '4인 가족 캠핑',
          );
          expect(page, equals(dialog));
        });
      });

      testWidgets('3. 검색 "헬리녹스" 가 행을 걸러내고 세트를 숨긴다; 지우면 복원', (tester) async {
        await _collecting(tester, (e) async {
          await _open(tester, size);
          final before = presetRowLabels(tester);
          expect(before, isNotEmpty);
          expect(before.first, '네이처하이크 클라우드업2 (2인)');

          e.stage = '검색';
          await tester.enterText(_searchField(), '헬리녹스');
          await tester.pumpAndSettle();
          final hits = presetRowLabels(tester);
          expect(hits.length, greaterThanOrEqualTo(3));
          for (final l in hits) {
            expect(l.contains('헬리녹스') || l.toLowerCase().contains('helinox'), isTrue, reason: l);
          }
          expect(find.text('추천 세트'), findsNothing);
          expect(find.text('4인 가족 캠핑'), findsNothing);
          // 검색 필드는 여전히 고정 머리말에 있다
          expect(_searchField(), findsOneWidget);

          e.stage = '지우기';
          await tester.tap(find.byTooltip('검색어 지우기'));
          await tester.pumpAndSettle();
          expect(find.text('추천 세트'), findsOneWidget);
          expect(presetRowLabels(tester).first, before.first);
          expect(find.byTooltip('검색어 지우기'), findsNothing);
        });
      });

      testWidgets('4. 직접 입력: 추가하면 1개, 빈 치수는 다이얼로그처럼 스낵바로 막는다', (tester) async {
        await _collecting(tester, (e) async {
          e.stage = '직접 입력 추가';
          await _open(tester, size);
          await _fillCustom(tester);
          // 검색 필드는 없고 추가는 항상 활성
          expect(
            _inPicker(find.widgetWithText(TextField, '라벨')),
            findsOneWidget,
          );
          expect(find.text('선택 해제'), findsNothing);
          final add = tester.widget<ElevatedButton>(
            _inPicker(find.widgetWithText(ElevatedButton, '추가')),
          );
          expect(add.onPressed, isNotNull);
          await tester.tap(addConfirmButton());
          await tester.pumpAndSettle();
          expect(_returned, isTrue);
          final r = _result!;
          expect(r, hasLength(1));
          expect(r.single['label'], '내 박스');
          expect(r.single['w'], closeTo(0.5, 1e-9));
          expect(r.single['d'], closeTo(0.4, 1e-9));
          expect(r.single['h'], closeTo(0.3, 1e-9));
          expect(r.single['category'], BoxCategory.custom.index);
          expect(r.single.containsKey('weight'), isFalse);

          e.stage = '빈 치수 (페이지)';
          await _reopen(tester);
          await _fillCustom(tester, w: '');
          await tester.tap(addConfirmButton());
          await tester.pump();
          // 닫히지 않고 스낵바
          expect(find.byType(AddBoxDialog), findsOneWidget);
          expect(_returned, isFalse);
          expect(find.text('유효한 크기를 입력하세요'), findsOneWidget);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('닫기'));
          await tester.pumpAndSettle();

          e.stage = '빈 치수 (다이얼로그, 같은 동작)';
          await _open(tester, size, fullScreen: false);
          await _fillCustom(tester, w: '');
          await tester.tap(addConfirmButton());
          await tester.pump();
          expect(find.byType(AddBoxDialog), findsOneWidget);
          expect(_returned, isFalse);
          expect(find.text('유효한 크기를 입력하세요'), findsOneWidget);
          await tester.pumpAndSettle();
        });
      });

      testWidgets('5. 앱바 ✕ 와 안드로이드 뒤로가기는 null 로 닫는다', (tester) async {
        await _collecting(tester, (e) async {
          e.stage = '✕';
          await _open(tester, size);
          await _tapBundle(tester, '4인 가족 캠핑');
          await tester.tap(find.byTooltip('닫기'));
          await tester.pumpAndSettle();
          expect(find.byType(AddBoxDialog), findsNothing);
          expect(_returned, isTrue);
          expect(_result, isNull);

          e.stage = '뒤로가기 (handlePopRoute → Navigator.maybePop)';
          await _reopen(tester);
          final handled = await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(handled, isTrue);
          expect(find.byType(AddBoxDialog), findsNothing);
          expect(_returned, isTrue);
          expect(_result, isNull);
          // 호스트는 그대로 살아 있다
          expect(find.text('열기'), findsOneWidget);
        });
      });

      testWidgets('6. 키보드 인셋 300: 검색·하단 바가 보이고 목록이 120px 이상 남는다', (
        tester,
      ) async {
        await _collecting(tester, (e) async {
          await _open(tester, size);
          final visibleBottom = size.height - _keyboard;

          e.stage = '키보드 (프리셋)';
          _showKeyboard(tester);
          await tester.pumpAndSettle();
          final search = tester.getRect(_searchField());
          expect(search.bottom, lessThanOrEqualTo(visibleBottom));
          expect(search.top, greaterThanOrEqualTo(kToolbarHeight));
          final add = tester.getRect(_inPicker(find.byType(ElevatedButton)));
          expect(add.bottom, lessThanOrEqualTo(visibleBottom));
          expect(add.height, greaterThanOrEqualTo(48));
          final list = tester.getRect(_listView());
          expect(list.height, greaterThanOrEqualTo(120));
          expect(list.bottom, lessThanOrEqualTo(visibleBottom));
          expect(list.top, greaterThanOrEqualTo(search.bottom));

          e.stage = '키보드 + 검색 + 선택 + 추가';
          await tester.enterText(_searchField(), '헬리녹스 체어원');
          await tester.pumpAndSettle();
          final rows = presetRowLabels(tester);
          expect(rows, contains('헬리녹스 체어원'));
          await tester.tap(dialogLabel('헬리녹스 체어원'));
          await tester.pumpAndSettle();
          expect(find.text('추가 (1개)'), findsOneWidget);
          final addNow = tester.getRect(_inPicker(find.byType(ElevatedButton)));
          expect(addNow.bottom, lessThanOrEqualTo(visibleBottom));
          await tester.tap(addConfirmButton());
          await tester.pumpAndSettle();
          expect(_returned, isTrue);
          expect(_result, hasLength(1));
          expect(_result!.single['label'], '헬리녹스 체어원');

          e.stage = '키보드 (직접 입력)';
          await _reopen(tester);
          await _fillCustom(tester);
          await tester.pumpAndSettle();
          final addCustom = tester.getRect(
            _inPicker(find.byType(ElevatedButton)),
          );
          expect(addCustom.bottom, lessThanOrEqualTo(visibleBottom));
          expect(
            _inPicker(find.widgetWithText(TextField, '라벨')),
            findsOneWidget,
          );

          e.stage = '키보드 내림';
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          final addDown = tester.getRect(
            _inPicker(find.byType(ElevatedButton)),
          );
          expect(addDown.bottom, lessThanOrEqualTo(size.height));
          expect(addDown.bottom, greaterThan(visibleBottom));
        });
      });

      testWidgets('7. 전 플로우에서 RenderFlex overflow 등 오류 0', (tester) async {
        await _collecting(tester, (e) async {
          e.stage = '열기';
          await _open(tester, size);
          e.stage = '세트 선택';
          await _tapBundle(tester, '4인 가족 캠핑');
          e.stage = '카테고리 전환';
          for (final cat in ['캐리어', '이사박스', '캠핑']) {
            await tester.tap(find.widgetWithText(ChoiceChip, cat));
            await tester.pumpAndSettle();
          }
          e.stage = '서브카테고리';
          await tester.tap(find.widgetWithText(ChoiceChip, '텐트'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
          await tester.pumpAndSettle();
          e.stage = '행 선택 + 수량';
          // 카테고리·서브카테고리를 오가도 앞서 고른 세트(16개)는 남는다 (세트 + 다른 카테고리 짐을
          // 한 번에 담을 수 있게). 보이는 첫 행을 더 고르면 17개.
          final before = RegExp(r'(\d+)개 선택')
              .firstMatch(allTexts(tester).firstWhere((t) => t.endsWith('개 선택'), orElse: () => '0개 선택'))!
              .group(1)!;
          final firstLabel = presetRowLabels(tester).first;
          await tester.tap(dialogLabel(firstLabel));
          await tester.pumpAndSettle();
          final base = int.parse(before) + 1;
          expect(find.text('$base개 선택'), findsOneWidget);
          // 세트 행도 선택돼 있어 수량 버튼이 여럿이다 → 방금 고른 행의 것만
          final firstRow = find
              .ancestor(of: dialogLabel(firstLabel), matching: find.byType(InkWell))
              .first;
          await tester.tap(
              find.descendant(of: firstRow, matching: find.byTooltip('수량 늘리기')));
          await tester.pumpAndSettle();
          expect(find.text('${base + 1}개 선택'), findsOneWidget);
          // 세트 카드: 이미 다 골라져 있으면 해제, 아니면 세트 전부 선택 (개수는 실제 칩으로 확인)
          await _tapBundle(tester, '4인 가족 캠핑');
          expect(_selectedCount(tester), greaterThanOrEqualTo(2));
          e.stage = '검색';
          await tester.enterText(_searchField(), '스노우피크');
          await tester.pumpAndSettle();
          e.stage = '검색 + 키보드';
          _showKeyboard(tester);
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          e.stage = '검색 지우기 + 선택 해제';
          await tester.tap(find.byTooltip('검색어 지우기'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('선택 해제'));
          await tester.pumpAndSettle();
          expect(find.textContaining('개 선택'), findsNothing);
          e.stage = '직접 입력 + 키보드';
          await _fillCustom(tester);
          _showKeyboard(tester);
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          e.stage = '닫기';
          await tester.tap(find.byTooltip('닫기'));
          await tester.pumpAndSettle();
          expect(find.byType(AddBoxDialog), findsNothing);
        });
      });

      testWidgets('8. 탭 영역: 행 48px 이상, 체크박스·수량 버튼 40px 이상', (tester) async {
        await _collecting(tester, (e) async {
          await _open(tester, size);
          final checkboxes = _inPicker(find.byType(Checkbox));
          expect(checkboxes.evaluate().length, greaterThanOrEqualTo(5));
          for (var i = 0; i < 5; i++) {
            e.stage = '행 $i';
            final box = checkboxes.at(i);
            await tester.ensureVisible(box);
            await tester.pumpAndSettle();
            final row = find
                .ancestor(of: box, matching: find.byType(InkWell))
                .first;
            final label = presetRowLabels(tester)[i];

            final boxRect = tester.getRect(box);
            expect(boxRect.width, greaterThanOrEqualTo(40), reason: label);
            expect(boxRect.height, greaterThanOrEqualTo(40), reason: label);
            expect(
              tester.getRect(row).height,
              greaterThanOrEqualTo(48),
              reason: label,
            );

            // 선택하면 수량 버튼이 나오고, 행 높이는 그대로 48 이상
            await tester.tap(row);
            await tester.pumpAndSettle();
            // 앞 단계의 선택(세트 등)은 카테고리를 오가도 남으므로 상대 개수로 본다
            final base = _selectedCount(tester);
            expect(base, greaterThanOrEqualTo(1), reason: label);
            for (final tip in ['수량 줄이기', '수량 늘리기']) {
              final r = tester.getRect(find.byTooltip(tip));
              expect(r.width, greaterThanOrEqualTo(40), reason: '$label $tip');
              expect(r.height, greaterThanOrEqualTo(40), reason: '$label $tip');
              expect(
                r.right,
                lessThanOrEqualTo(size.width),
                reason: '$label $tip',
              );
            }
            expect(
              tester.getRect(row).height,
              greaterThanOrEqualTo(48),
              reason: label,
            );
            // + 를 눌러 2개, − 로 되돌린 뒤 체크박스로 해제
            await tester.tap(find.byTooltip('수량 늘리기'));
            await tester.pumpAndSettle();
            expect(find.text('${base + 1}개 선택'), findsOneWidget, reason: label);
            await tester.tap(find.byTooltip('수량 줄이기'));
            await tester.pumpAndSettle();
            expect(find.text('$base개 선택'), findsOneWidget, reason: label);
            await tester.tap(checkboxes.at(i));
            await tester.pumpAndSettle();
            expect(find.textContaining('개 선택'), findsNothing, reason: label);
          }
        });
      });
    });
  }
}
