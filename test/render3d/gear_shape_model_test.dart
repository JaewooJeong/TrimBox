import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/gear_physics.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

GearShape _shapeOf(String label) {
  final g = gearCatalog().firstWhere((e) => e.label == label);
  return gearPhysicsFor(
    label: g.label,
    category: g.category,
    subCategory: g.subCategory,
    wCm: g.w,
    dCm: g.d,
    hCm: g.h,
  ).shape;
}

void main() {
  group('TrimBox.shape 저장', () {
    TrimBox make(GearShape shape) => TrimBox(
          id: 'a',
          label: '짐',
          w: 0.4,
          d: 0.3,
          h: 0.2,
          color: const Color(0xFF556B2F),
          shape: shape,
        );

    test('기본값은 box 이고 JSON 에 쓰지 않는다 (예전 파일과 같은 모양)', () {
      final b = TrimBox(
          id: 'a', label: '짐', w: 1, d: 1, h: 1, color: const Color(0xFF000000));
      expect(b.shape, GearShape.box);
      expect(b.toJson().containsKey('shape'), isFalse);
    });

    test('모든 모양이 JSON 왕복에서 유지된다 (이름으로 저장)', () {
      for (final shape in GearShape.values) {
        final json = jsonDecode(jsonEncode(make(shape).toJson()))
            as Map<String, dynamic>;
        if (shape != GearShape.box) expect(json['shape'], shape.name);
        expect(TrimBox.fromJson(json).shape, shape);
      }
    });

    test('모르는 값·없는 값·타입이 다른 값은 box 로', () {
      final base = make(GearShape.cooler).toJson();
      expect(TrimBox.fromJson({...base, 'shape': 'hovercraft'}).shape,
          GearShape.box);
      expect(TrimBox.fromJson({...base, 'shape': 3}).shape, GearShape.box);
      expect(TrimBox.fromJson({...base, 'shape': null}).shape, GearShape.box);
      expect(TrimBox.fromJson({...base}..remove('shape')).shape, GearShape.box);
      expect(gearShapeFromName('cylinder'), GearShape.cylinder);
    });

    test('copyWith 는 모양을 유지하고 바꿀 수 있다', () {
      final b = make(GearShape.crate);
      expect(b.copyWith(x: 1).shape, GearShape.crate);
      expect(b.copyWith(shape: GearShape.flat).shape, GearShape.flat);
    });
  });

  group('장비 → 모양 매핑', () {
    test('대표 장비', () {
      const expected = {
        // 원통: 텐트·타프·폴대·의자·롤테이블·만 매트·세워 두는 통
        '코베아 네스트W (4인 거실형)': GearShape.cylinder,
        '렉타타프 (대형/폴대 포함)': GearShape.cylinder,
        '타프 폴대 세트 (280cm)': GearShape.cylinder,
        '타프폴대 수납백': GearShape.cylinder,
        '일반 캠핑의자 (접이식)': GearShape.cylinder,
        '헬리녹스 체어원': GearShape.cylinder,
        '롤테이블 (4인/120cm)': GearShape.cylinder,
        '자충매트 (싱글)': GearShape.cylinder,
        '에어매트 (싱글)': GearShape.cylinder,
        '워터저그 10L (일반)': GearShape.cylinder,
        '코펠세트 (2-3인)': GearShape.cylinder,
        '더치오븐 10인치': GearShape.cylinder,
        '파세코 캠프-10 등유 난로': GearShape.cylinder,
        '리어게이트 차량 텐트': GearShape.cylinder,
        // 천 가방
        '일반 침낭 (3계절)': GearShape.softBag,
        '다운침낭 (경량)': GearShape.softBag,
        '모포/담요': GearShape.softBag,
        '캠핑 베개 (접이식)': GearShape.softBag,
        '캠핑 더플백 60L': GearShape.softBag,
        '등산 배낭 65L': GearShape.softBag,
        '다이소 소프트 쿨러백': GearShape.softBag,
        '아이스 토트백': GearShape.softBag,
        '대형 메쉬 수납백': GearShape.softBag,
        '힐레베르그 아틀라스': GearShape.softBag, // 뭉툭한 텐트 가방
        // 쿨러
        '대형 아이스박스 (50L)': GearShape.cooler,
        '예티 탄드라 45': GearShape.cooler,
        '차량용 냉장고 (25L)': GearShape.cooler,
        // 컨테이너
        '스노우피크 쉘프컨테이너 50': GearShape.crate,
        '폴딩박스 (56L)': GearShape.crate,
        '이케아 SAMLA 박스 45L': GearShape.crate,
        '코베아 컨테이너 하드케이스 45L': GearShape.crate,
        // 납작한 판
        '접이식 테이블 (2인/60cm)': GearShape.flat,
        '코베아 슬림2폴딩 테이블': GearShape.flat,
        '그리들 (철판)': GearShape.flat,
        '스노우피크 화로대 L': GearShape.flat,
        '차박매트 SUV 접이식': GearShape.flat,
        '코베아 팝업 텐트 (2-3인)': GearShape.flat,
        // 하드 케이스
        '대형 캐리어 (28")': GearShape.hardCase,
        'EcoFlow DELTA 2': GearShape.hardCase,
        '잭커리 500 파워뱅크': GearShape.hardCase,
        // 그 밖은 상자
        '코베아 슬림트윈 투버너': GearShape.box,
        '장작 한 묶음': GearShape.box,
        '중형 이사박스': GearShape.box,
        '써모레스트 Z라이트솔': GearShape.box, // 아코디언 폼 매트 (오버라이드)
        '커스텀': GearShape.box,
      };
      expected.forEach((label, shape) {
        expect(_shapeOf(label), shape, reason: label);
      });
    });

    test('카탈로그 전체가 모양을 갖고, 물리 값은 모양 추가 전과 같다', () {
      final counts = <GearShape, int>{};
      for (final g in gearCatalog()) {
        final ph = gearPhysicsFor(
          label: g.label,
          category: g.category,
          subCategory: g.subCategory,
          wCm: g.w,
          dCm: g.d,
          hCm: g.h,
        );
        counts[ph.shape] = (counts[ph.shape] ?? 0) + 1;
        // 연질이 아닌데 가방으로 그리는 건 괜찮지만, 원통/판은 치수 비율이 맞아야 한다
        final dims = [g.w, g.d, g.h]..sort();
        if (ph.shape == GearShape.flat) {
          expect(dims[0] / dims[1], lessThanOrEqualTo(0.5), reason: g.label);
        }
        final override = gearOverrides[g.label];
        if (override != null) {
          expect(ph.weightKg, override.weightKg, reason: g.label);
          expect(ph.soft, override.soft, reason: g.label);
          expect(ph.compress, override.compress, reason: g.label);
          expect(ph.upright, override.upright, reason: g.label);
          expect(ph.access, override.access, reason: g.label);
        }
      }
      for (final shape in GearShape.values) {
        expect(counts[shape] ?? 0, greaterThan(0), reason: shape.name);
      }
      // ignore: avoid_print
      print('[gear shapes] ${counts.map((k, v) => MapEntry(k.name, v))}');
    });

    test('다이얼로그 결과 맵에 shape 이 이름으로 실린다', () {
      final fields = gearPhysicsFor(
        label: '대형 아이스박스 (50L)',
        category: 'camping',
        subCategory: 'cooler',
        wCm: 60,
        dCm: 40,
        hCm: 42,
      ).toItemFields();
      expect(fields['shape'], 'cooler');
      expect(gearShapeFromName(fields['shape']), GearShape.cooler);
    });
  });
}
