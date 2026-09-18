// SimulatorScreen 레이아웃 테스트 — 데스크톱·태블릿·폰·낮은 폰에서 주요 화면과 다이얼로그를
// 전부 열어 보며 RenderFlex overflow 등 FlutterError 가 하나도 없는지 확인한다.
//
// 실제 글꼴(sim_harness.loadRealFonts)을 써야 의미가 있다: 기본 테스트 글꼴은 라틴·숫자를
// 2배 폭으로 재서 거짓 overflow 를 낸다. 실제 글꼴을 못 찾으면 overflow 검사는 건너뛴다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';
import 'package:trimbox/widgets/box_list_panel.dart';
import 'package:trimbox/widgets/trunk_size_dialog.dart';

import 'sim_harness.dart';

const _sizes = <String, Size>{
  '데스크톱 1280×960': kDesktop,
  '태블릿 820×1180': kTablet,
  '폰 390×844': kPhone,
  '안드로이드 폰 360×800': Size(360, 800),
  '낮은 폰 390×600': kPhoneShort,
};

/// pump 중 보고된 FlutterError 를 단계 라벨과 함께 모은다.
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
          .firstWhere((l) => l.contains('overflowed') || l.contains('Exception') || l.contains('Error'),
              orElse: () => details.exceptionAsString().split('\n').first)
          .trim();
      final where = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(text)?.group(0) ?? '';
      if (!realFontsLoaded && head.contains('overflowed')) return;
      found.add('[$stage] $head $where');
    };
  }

  void restore() => FlutterError.onError = _original;
}

/// 단계별로 오류를 모으며 [body] 를 돌리고, 끝에 한꺼번에 검사한다.
/// 어느 화면 크기에서도 예외로 봐주는 overflow 는 없다.
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

/// 2열 컨트롤이 화면 안에 있어 누를 수 있는가
bool _seatControlReachable(WidgetTester tester, Size size) {
  final f = seatSlideControl();
  if (f.evaluate().isEmpty) return false;
  return tester.getRect(f).right <= size.width;
}

/// 패널(폰에서는 시트 안 ListView)을 맨 위로 되돌린다. 앞 단계의 ensureVisible 이
/// 목록을 내려놓으면 위쪽 버튼이 캐시 범위 밖으로 나가 트리에서 빠진다.
Future<void> _panelToTop(WidgetTester tester) async {
  final c = panelOf(tester).scrollController;
  if (c != null && c.hasClients && c.offset > 0) {
    c.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) await _panelToTop(tester);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 80,
        scrollable: find
            .descendant(
                of: find.byType(BoxListPanel), matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRealFonts);

  for (final entry in _sizes.entries) {
    final name = entry.key;
    final size = entry.value;
    final isPhone = size.width < 600;

    group('10. 레이아웃 — $name', () {
      testWidgets('첫 실행 화면과 빈 상태 CTA', (tester) async {
        await _collecting(tester, (e) async {
          e.stage = '온보딩';
          await pumpApp(tester, size: size);
          expect(find.text('아무 곳이나 탭하여 닫기'), findsOneWidget);
          // 낮은 화면에서는 안내 문구가 잘려 화면 밖이다 → 카드 위쪽 제목을 누른다
          await tester.tap(find.text('박스를 추가하여\n시뮬레이션을 시작하세요'));
          await tester.pumpAndSettle();
          expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);

          e.stage = '빈 상태';
          expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
          expect(find.byType(DraggableScrollableSheet),
              isPhone ? findsOneWidget : findsNothing);
          if (size.height >= 800) {
            // 시트를 올리지 않아도 CTA 가 화면 안에 있다
            final r = tester.getRect(find.text('캠핑 장비 선택하기'));
            expect(r.bottom, lessThanOrEqualTo(size.height));
            expect(r.top, greaterThanOrEqualTo(0));
          }
          await openAddDialog(tester);
          expect(find.byType(AddBoxDialog), findsOneWidget);
        });
      });

      testWidgets('장비 선택 다이얼로그: 모든 카테고리·검색·직접 입력', (tester) async {
        await _collecting(tester, (e) async {
          await pumpApp(tester, size: size, prefs: seenPrefs());
          e.stage = '다이얼로그 열기';
          await openAddDialog(tester);
          for (final cat in ['캐리어', '이사박스', '직접 입력', '캠핑']) {
            e.stage = '카테고리 $cat';
            // 좁은 다이얼로그에서는 칩 줄이 가로 스크롤이다
            await _tapVisible(tester, find.widgetWithText(ChoiceChip, cat));
            expect(
                tester
                    .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, cat))
                    .selected,
                isTrue);
          }
          e.stage = '서브카테고리 타프';
          await _tapVisible(tester, find.widgetWithText(ChoiceChip, '타프'));
          await _tapVisible(tester, find.widgetWithText(ChoiceChip, '전체'));
          e.stage = '세트 선택';
          await tester.ensureVisible(find.text('4인 가족 캠핑'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('4인 가족 캠핑'));
          await tester.pumpAndSettle();
          expect(find.text('추가 (16개)'), findsOneWidget);
          e.stage = '검색';
          await tester.enterText(
              find.descendant(
                  of: find.byType(AddBoxDialog),
                  matching: find.byType(TextField)),
              '스노우피크');
          await tester.pumpAndSettle();
          e.stage = '키보드가 올라온 상태 (viewInsets 300)';
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        });
      });

      testWidgets('4인 세트 적재 후: 히어로 버튼·판정·자동 배치·스텝 뷰·경고', (tester) async {
        await _collecting(tester, (e) async {
          await pumpApp(tester, size: size, prefs: seenPrefs());
          e.stage = '세트 추가 + 스낵바';
          await addBundle(tester, '4인 가족 캠핑');
          expect(boxesOf(tester), hasLength(16));
          await flushSnackBars(tester);

          e.stage = '적재 후 화면';
          await _panelToTop(tester);
          expect(find.text('들어갈까?'), findsOneWidget);
          expect(find.text('자동 배치'), findsOneWidget);
          if (size.height >= 800) {
            for (final t in ['들어갈까?', '자동 배치']) {
              final r = tester.getRect(find.text(t));
              expect(r.bottom, lessThanOrEqualTo(size.height), reason: t);
            }
          }

          e.stage = '판정 다이얼로그';
          await _tapVisible(tester, find.text('들어갈까?'));
          expect(find.textContaining('적재 가능'), findsWidgets);
          await tester.tap(find.text('확인'));
          await tester.pumpAndSettle();

          e.stage = '스텝 뷰';
          await _tapVisible(tester, find.text('적재 순서 가이드'));
          expect(find.textContaining('STEP 1 / '), findsOneWidget);
          await tester.tap(stepButton(Icons.chevron_right));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('스텝뷰 닫기'));
          await tester.pumpAndSettle();

          e.stage = '상태 줄 → 사유 다이얼로그';
          final status = find.descendant(
              of: find.byType(BoxListPanel),
              matching: find.byWidgetPredicate((w) =>
                  w is Icon && w.icon == Icons.chevron_right && w.size == 14));
          if (status.evaluate().isNotEmpty) {
            await _tapVisible(tester, status);
            expect(find.byType(AlertDialog), findsOneWidget);
            await tester.tap(find.text('확인'));
            await tester.pumpAndSettle();
          }

          e.stage = '자동 배치 대안 다이얼로그';
          await _tapVisible(tester, find.text('자동 배치'));
          expect(find.text('이 배치 적용'), findsOneWidget);
          e.stage = '적용 후 판정 다이얼로그 + 스낵바';
          await tester.tap(find.text('이 배치 적용'));
          await tester.pumpAndSettle();
          expect(find.textContaining('적재 가능'), findsWidgets);
          await tester.tap(find.text('확인'));
          await tester.pumpAndSettle();
          await flushSnackBars(tester);

          expect(_seatControlReachable(tester, size), isTrue);
          {
            e.stage = '2열 최전방 + 전부 적재';
            await tester.tap(seatSlideControl());
            await tester.pumpAndSettle();
            await tester.tap(find.text('2열 최전방 (+27cm)'));
            await tester.pumpAndSettle();
            await flushSnackBars(tester);
            e.stage = '전부 적재 판정 다이얼로그';
            await _tapVisible(tester, find.text('들어갈까?'));
            expect(find.textContaining('적재 가능'), findsWidgets);
            await tester.tap(find.text('확인'));
            await tester.pumpAndSettle();
          }
          await flushAutosave(tester);
        });
      });

      testWidgets('앱바 메뉴·커스텀 트렁크·저장/불러오기·도움말 다이얼로그', (tester) async {
        await _collecting(tester, (e) async {
          await pumpAppWithScene(
              tester,
              [
                mkBox('box-001', '대형 아이스박스 (50L)',
                    w: 0.60, d: 0.40, h: 0.42, x: 0.30, z: 0.30, weightKg: 32,
                    upright: true, access: true),
              ],
              size: size);

          expect(_seatControlReachable(tester, size), isTrue);
          {
            e.stage = '2열 메뉴';
            await tester.tap(seatSlideControl());
            await tester.pumpAndSettle();
            await tester.tap(find.text('2열 최전방 (+27cm)'));
            await tester.pumpAndSettle();
          }

          e.stage = '차종 메뉴 → 7인승 (가장 긴 라벨)';
          await tester.tap(presetButton());
          await tester.pumpAndSettle();
          await tester.tap(find.text(TrunkPreset.sorento7.label));
          await tester.pumpAndSettle();

          e.stage = '커스텀 트렁크 다이얼로그 (휠하우스 펼침)';
          await tester.tap(presetButton());
          await tester.pumpAndSettle();
          await tester.tap(find.text('커스텀'));
          await tester.pumpAndSettle();
          expect(find.byType(TrunkSizeDialog), findsOneWidget);
          await tester.tap(find.text('휠하우스 (선택)'));
          await tester.pumpAndSettle();
          await tester.enterText(find.widgetWithText(TextField, '가로(cm)'), '-1');
          await tester.tap(find.text('확인'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('취소'));
          await tester.pumpAndSettle();

          e.stage = '저장 다이얼로그';
          await _tapVisible(tester, find.byTooltip('배치 저장'));
          expect(find.text('배치 이름'), findsOneWidget);
          await tester.tap(find.text('취소'));
          await tester.pumpAndSettle();

          e.stage = '불러오기 다이얼로그';
          await _tapVisible(tester, find.byTooltip('불러오기'));
          expect(find.text('저장된 배치 불러오기'), findsOneWidget);
          await tester.tap(find.text('취소'));
          await tester.pumpAndSettle();

          e.stage = '단축키 도움말';
          await tester.tap(find.byTooltip('키보드 단축키 (?)'));
          await tester.pumpAndSettle();
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();
          await flushAutosave(tester);
        });
      });

      if (isPhone) {
        testWidgets('시트를 끝까지 올리고 내려도 오류 없음, 목록 끝까지 스크롤', (tester) async {
          await _collecting(tester, (e) async {
            await pumpApp(tester, size: size, prefs: seenPrefs());
            await addBundle(tester, '2인 미니멀 캠핑');
            await flushSnackBars(tester);
            e.stage = '시트 올리기';
            final sheet = find.byType(BoxListPanel);
            final bodyH = size.height - kToolbarHeight;
            await expandSheet(tester);
            expect(tester.getRect(sheet).height, closeTo(bodyH * 0.85, 2),
                reason: '최대 85%');
            e.stage = '목록 스크롤';
            for (var i = 0; i < 4; i++) {
              await tester.fling(sheet, const Offset(0, -300), 1000);
              await tester.pumpAndSettle();
            }
            // 마지막 타일까지 닿는다
            expect(find.text(boxesOf(tester).last.label), findsWidgets);
            e.stage = '시트 내리기';
            for (var i = 0; i < 10; i++) {
              await tester.fling(sheet, const Offset(0, 300), 1000);
              await tester.pumpAndSettle();
            }
            // 최소 12% 에서도 손잡이가 남는다
            expect(tester.getRect(sheet).height, closeTo(bodyH * 0.12, 2),
                reason: '최소 12%');
            await flushAutosave(tester);
          });
        });
      }
    });
  }

  group('10. 레이아웃 — 좁은·낮은 화면 회귀', () {
    testWidgets('폰 폭(390)에서 앱바가 넘치지 않고 2열 컨트롤을 누를 수 있다', (tester) async {
      await _collecting(tester, (e) async {
        await pumpApp(tester, size: kPhone, prefs: seenPrefs());
        expect(_seatControlReachable(tester, kPhone), isTrue);
        expect(tester.getRect(presetButton()).right,
            lessThanOrEqualTo(tester.getRect(seatSlideControl()).left));
        // 폰에서는 차종명만 (치수는 메뉴에)
        expect(find.descendant(of: presetButton(), matching: find.text('쏘렌토 5인승')),
            findsOneWidget);
      });
    });

    testWidgets('낮은 화면에서 온보딩 카드가 넘치지 않는다', (tester) async {
      await _collecting(tester, (e) async {
        e.stage = '온보딩';
        await pumpApp(tester, size: const Size(844, 390)); // 폰 가로
      });
    });

    testWidgets('낮은 화면에서 판정 다이얼로그가 넘치지 않는다', (tester) async {
      final e = _Errors()..install();
      try {
        await pumpApp(tester, size: const Size(844, 390), prefs: seenPrefs());
        await addBundle(tester, '솔로 백패킹');
        await flushSnackBars(tester);
        e.stage = '판정 다이얼로그';
        await tester.tap(find.text('들어갈까?'));
        await tester.pumpAndSettle();
        expect(find.text('모두 적재 가능!'), findsOneWidget);
        e.stage = '끝';
        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();
        await flushAutosave(tester);
      } finally {
        e.restore();
      }
      expect(e.found.where((f) => f.startsWith('[판정 다이얼로그]')), isEmpty);
    });

    testWidgets('폭 360 에서 장비 선택 다이얼로그 하단 버튼 줄이 넘치지 않는다', (tester) async {
      final e = _Errors()..install();
      try {
        await pumpApp(tester, size: const Size(360, 800), prefs: seenPrefs());
        await openAddDialog(tester);
        e.stage = '세트 선택';
        await tester.ensureVisible(find.text('4인 가족 캠핑'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('4인 가족 캠핑'));
        await tester.pumpAndSettle();
      } finally {
        e.restore();
      }
      expect(e.found.where((f) => f.startsWith('[세트 선택]')), isEmpty);
    });

    testWidgets('낮은 화면에서 키보드가 올라와도 장비 선택 다이얼로그가 넘치지 않는다', (tester) async {
      await _collecting(tester, (e) async {
        await pumpApp(tester, size: kPhoneShort, prefs: seenPrefs());
        await expandSheet(tester);
        await openAddDialog(tester);
        final search = find.descendant(
            of: find.byType(AddBoxDialog), matching: find.byType(TextField));
        await tester.tap(search);
        await tester.enterText(search, '헬리녹스');
        await tester.pumpAndSettle();
        e.stage = '키보드';
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        // 머리말이 목록 안으로 옮겨져도 검색어·포커스·결과는 그대로다
        final field = tester.widget<TextField>(search);
        expect(field.controller!.text, '헬리녹스');
        expect(field.focusNode!.hasFocus, isTrue);
        expect(presetRowLabels(tester).every((l) => l.contains('헬리녹스')), isTrue);
        // 키보드가 내려가면 원래 배치로
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller!.text, '헬리녹스');
      });
    });
  });

  group('11. 접근성 점검', () {
    testWidgets('화면의 아이콘 버튼은 전부 툴팁이 있다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      final missing = <String>[];
      for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
        if ((b.tooltip ?? '').isEmpty) missing.add('${(b.icon as Icon).icon}');
      }
      expect(missing, isEmpty);
      for (final tip in [
        '키보드 단축키 (?)',
        '차종 선택',
        '2열 시트 슬라이드',
        '배치 저장',
        '불러오기',
        '자동 배치',
        '실행 취소',
        '다시 실행',
        '90° 회전',
        '삭제',
      ]) {
        expect(find.byTooltip(tip), findsWidgets, reason: tip);
      }
      await flushAutosave(tester);
    });

    testWidgets('스텝 뷰의 이전/다음 버튼에도 툴팁(라벨)이 있다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      await addBundle(tester, '솔로 백패킹');
      await flushSnackBars(tester);
      await tester.tap(find.text('적재 순서 가이드'));
      await tester.pumpAndSettle();
      for (final icon in [Icons.chevron_left, Icons.chevron_right]) {
        final b = tester.widget<IconButton>(
            find.ancestor(of: stepButton(icon), matching: find.byType(IconButton)));
        expect(b.tooltip, isNotNull, reason: '$icon');
      }
      await flushAutosave(tester);
    });

    testWidgets('차종 메뉴 버튼의 툴팁이 한국어다', (tester) async {
      await pumpApp(tester, prefs: seenPrefs());
      final menu = tester.widget<PopupMenuButton<TrunkPreset>>(
          find.byType(PopupMenuButton<TrunkPreset>));
      expect(menu.tooltip, '차종 선택');
    });

    testWidgets('목록 타일의 회전·삭제 버튼 크기가 더 줄지 않는다 (현재 32px+)', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ], size: kTablet);
      // 현재 약 32~36px (VisualDensity.compact). Material 권장 48dp 보다 작다 — 더 줄어들지 않게만 막는다.
      for (final tip in ['90° 회전', '삭제']) {
        final s = tester.getSize(find.byTooltip(tip));
        expect(s.width, greaterThanOrEqualTo(32), reason: '$tip $s');
        expect(s.height, greaterThanOrEqualTo(32), reason: '$tip $s');
      }
    });

    testWidgets('터치 기기에서도 실행 취소를 할 수 있다 (버튼)', (tester) async {
      await pumpAppWithScene(tester, [
        mkBox('box-001', '가', w: 0.50, d: 0.30, h: 0.30, x: 0.20, z: 0.20),
      ], size: kTablet);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();
      expect(boxesOf(tester), isEmpty);
      // 패널 액션바의 버튼으로 되돌리고 다시 실행한다 (Ctrl+Z 없이)
      await tester.tap(find.byTooltip('실행 취소'));
      await tester.pumpAndSettle();
      expect(boxesOf(tester).map((b) => b.label), ['가']);
      await tester.tap(find.byTooltip('다시 실행'));
      await tester.pumpAndSettle();
      expect(boxesOf(tester), isEmpty);
      await flushAutosave(tester);
    });
  });
}
