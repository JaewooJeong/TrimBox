import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/load_stats.dart';

TrimBox _box(String id, double w, double d, double h,
        {double x = 0, double y = 0, double z = 0, double squash = 0}) =>
    TrimBox(
        id: id,
        label: id,
        w: w,
        d: d,
        h: h,
        x: x,
        y: y,
        z: z,
        color: const Color(0xFFBAE1FF),
        soft: squash > 0,
        compressibility: squash > 0 ? 0.4 : 0,
        squash: squash);

void main() {
  final space = TrunkSpace.sorento();

  test('트렁크 밖에 세워 둔 짐은 통계에서 빠진다', () {
    final inside = _box('in', 0.5, 0.4, 0.3, x: 0.3, z: 0.3);
    final parked = _box('out', 0.8, 0.35, 0.35, z: space.d + 0.06);
    final stats = LoadStats.of([inside, parked], space);
    expect(stats.inside.map((b) => b.id), ['in']);
    expect(stats.parked.map((b) => b.id), ['out']);
    expect(stats.usedVolume, closeTo(0.5 * 0.4 * 0.3, 1e-9));
    expect(stats.volumePercent,
        closeTo(0.5 * 0.4 * 0.3 / space.usableVolume * 100, 1e-9));
    expect(stats.maxTop, closeTo(0.3, 1e-9));
    expect(stats.remainingLiters, stats.totalLiters - stats.usedLiters);
  });

  test('경계: z = d − 0.005 부터 밖으로 본다', () {
    expect(LoadStats.isParked(_box('a', 0.1, 0.1, 0.1, z: space.d - 0.006), space),
        isFalse);
    expect(LoadStats.isParked(_box('b', 0.1, 0.1, 0.1, z: space.d - 0.005), space),
        isTrue);
  });

  test('남은 높이는 눌린 높이(box.top) 기준이고 음수가 되지 않는다', () {
    final base = _box('base', 0.5, 0.4, 0.55, x: 0.3, z: 0.3);
    final bag = _box('bag', 0.4, 0.3, 0.30, x: 0.3, y: 0.55, z: 0.3, squash: 0.3);
    final stats = LoadStats.of([base, bag], space);
    expect(stats.maxTop, closeTo(0.55 + 0.30 * 0.7, 1e-9));
    expect(stats.remainingHeightCm,
        ((space.h - stats.maxTop) * 100).round());
    final tooTall = _box('tall', 0.3, 0.3, space.h + 0.2, x: 0.3, z: 0.3);
    expect(LoadStats.of([tooTall], space).remainingHeightCm, 0);
  });

  test('빈 트렁크', () {
    final stats = LoadStats.of(const [], space);
    expect(stats.volumePercent, 0);
    expect(stats.areaRatio, 0);
    expect(stats.remainingHeightCm, (space.h * 100).round());
  });
}
