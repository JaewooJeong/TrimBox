// 성능 가드: 앱과 같은 설정(restarts 24, 예산 2.5초)으로 가장 무거운 추천 세트를
// 쏘렌토(2열 최후방 = 전부는 안 들어가서 재시도·보수·전수 탐색이 모두 도는 경우)에
// 배치한다. 예산 2.5초 + 보수 0.7초 + 전수 탐색 0.5초 + 여유 → 6초.
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'packing_test_kit.dart';

void main() {
  test('4인 가족 세트 자동배치는 6초 안에 끝난다 (restarts 24, 앱과 같은 예산)', () {
    final family = gearBundles().firstWhere((b) => b.name == '4인 가족 캠핑');
    final trunk = TrunkSpace.sorento();
    final input = bundleBoxes(family);
    // 워밍업 (JIT) 은 일부러 하지 않는다: 사용자가 처음 누를 때도 같은 조건이다
    final sw = Stopwatch()..start();
    final r = AutoLayoutEngine.computeLayout(trunk, input,
        restarts: 24, budget: const Duration(milliseconds: 2500));
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(6000));
    expect(r.placedCount, greaterThanOrEqualTo(14));
    expectPackingInvariants(trunk, input, r, strictRigidOnSoft: false);
  });
}
