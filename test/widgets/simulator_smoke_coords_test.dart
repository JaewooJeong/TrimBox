// 웹 스모크 E2E(e2e/smoke.spec.ts)는 캔버스라서 고정 뷰포트 좌표를 누른다.
// 이 테스트는 같은 뷰포트에서 그 좌표가 여전히 의도한 위젯 안에 있는지 확인한다 —
// 레이아웃을 바꿨다면 여기서 먼저 걸리고, 그때 smoke.spec.ts 의 좌표를 함께 갱신한다.
//
// 글꼴이 웹(Roboto + Noto Sans KR)과 완전히 같지는 않으므로 가장자리 몇 px 차이는 있을 수 있다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';

import 'sim_harness.dart';

/// e2e/smoke.spec.ts 의 D (데스크톱 1280×960)
const _d = (
  onboarding: Offset(460, 480),
  cta: Offset(1097, 597),
  bundleFamily: Offset(608, 430),
  bundleSolo: Offset(778, 430),
  dialogAdd: Offset(790, 744),
  quickCheck: Offset(1029, 773),
  autoLayout: Offset(1180, 773),
  preset: Offset(230, 28),
  presetSorento7: Offset(300, 122),
  seatSlide: Offset(450, 28),
  seatSlideFront: Offset(520, 150),
);

/// e2e/smoke.spec.ts 의 M (모바일 390×844)
const _m = (onboarding: Offset(195, 300), cta: Offset(195, 787));

void _expectInside(WidgetTester tester, Finder f, Offset p, String what) {
  expect(f, findsOneWidget, reason: what);
  final r = tester.getRect(f);
  expect(r.contains(p), isTrue, reason: '$what: $p 가 $r 밖');
}

Finder _button(String text) => find.ancestor(
    of: find.text(text), matching: find.bySubtype<ButtonStyleButton>());

void main() {
  setUpAll(loadRealFonts);

  testWidgets('데스크톱 1280×960: 스모크 좌표가 의도한 위젯 안에 있다', (tester) async {
    await pumpApp(tester, size: kDesktop);

    // 온보딩 (캔버스 위 아무 곳)
    expect(canvasRect(tester).contains(_d.onboarding), isTrue);
    await tester.tapAt(_d.onboarding);
    await tester.pumpAndSettle();
    expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);

    // 앱바
    _expectInside(tester, presetButton(), _d.preset, '차종 드롭다운');
    _expectInside(tester, seatSlideControl(), _d.seatSlide, '2열 드롭다운');

    // 빈 상태 CTA → 다이얼로그
    _expectInside(tester, _button('캠핑 장비 선택하기'), _d.cta, 'CTA');
    await tester.tapAt(_d.cta);
    await tester.pumpAndSettle();
    _expectInside(
        tester,
        find.ancestor(
            of: find.text('4인 가족 캠핑'), matching: find.byType(InkWell)),
        _d.bundleFamily,
        '4인 가족 캠핑 카드');
    _expectInside(
        tester,
        find.ancestor(
            of: find.text('솔로 백패킹'), matching: find.byType(InkWell)),
        _d.bundleSolo,
        '솔로 백패킹 카드');
    await tester.tapAt(_d.bundleFamily);
    await tester.pumpAndSettle();
    _expectInside(tester, _button('추가 (16개)'), _d.dialogAdd, '추가 버튼');
    await tester.tapAt(_d.dialogAdd);
    await tester.pumpAndSettle();
    expect(boxesOf(tester), hasLength(16));
    await flushSnackBars(tester);

    // 히어로 버튼
    _expectInside(tester, _button('들어갈까?'), _d.quickCheck, '들어갈까?');
    _expectInside(
        tester,
        find.ancestor(
            of: find.text('자동 배치'), matching: find.bySubtype<ButtonStyleButton>()),
        _d.autoLayout,
        '자동 배치');

    // 2열 메뉴 3번째 항목
    await tester.tapAt(_d.seatSlide);
    await tester.pumpAndSettle();
    _expectInside(
        tester,
        find.ancestor(
            of: find.text('2열 최전방 (+27cm)'),
            matching: find.byType(PopupMenuItem<double>)),
        _d.seatSlideFront,
        '메뉴: 2열 최전방');
    await tester.tapAt(_d.seatSlideFront);
    await tester.pumpAndSettle();
    expect(spaceOf(tester).seatSlide, closeTo(sorentoSeatSlideMax, 1e-9));
    await flushSnackBars(tester);

    // 2열을 당긴 뒤에도 (라벨의 깊이 숫자만 바뀐다) 같은 좌표에 두 드롭다운이 있다
    _expectInside(tester, presetButton(), _d.preset, '차종 드롭다운 (+27cm)');
    _expectInside(tester, seatSlideControl(), _d.seatSlide, '2열 드롭다운 (+27cm)');

    // 차종 메뉴 2번째 항목
    await tester.tapAt(_d.preset);
    await tester.pumpAndSettle();
    _expectInside(
        tester,
        find.ancestor(
            of: find.text(TrunkPreset.sorento7.label),
            matching: find.byType(PopupMenuItem<TrunkPreset>)),
        _d.presetSorento7,
        '메뉴: 쏘렌토 7인승');
    await tester.tapAt(_d.presetSorento7);
    await tester.pumpAndSettle();
    expect(spaceOf(tester).vehicleName, TrunkSpace.sorento7().vehicleName);
    await flushSnackBars(tester);
    await flushAutosave(tester);
  });

  testWidgets('모바일 390×844: 스모크 좌표가 의도한 위젯 안에 있다', (tester) async {
    await pumpApp(tester, size: kPhone);
    expect(canvasRect(tester).contains(_m.onboarding), isTrue);
    await tester.tapAt(_m.onboarding);
    await tester.pumpAndSettle();
    expect(find.text('아무 곳이나 탭하여 닫기'), findsNothing);
    _expectInside(tester, _button('캠핑 장비 선택하기'), _m.cta, 'CTA (시트 안)');
  });
}
