import 'auto_layout.dart';
import 'support.dart';
import 'trim_box.dart';
import 'trunk_space.dart';

/// 조언의 종류 (충돌이 아니라 "이렇게 싣지 않는 게 좋다" 수준)
enum AdviceKind {
  heavyHigh, // 무거운 짐이 위층에
  heavyOnLight, // 무거운 짐이 훨씬 가벼운 짐 위에
  rigidOnSoft, // 단단한 짐이 연질 짐 위에
  accessBuried, // 자주 꺼내는 짐이 안쪽 깊이
}

class Advice {
  final AdviceKind kind;
  final TrimBox box;
  final String message;

  const Advice(this.kind, this.box, this.message);
}

/// 현재 배치에 대한 적재 조언. 물리 유효성([CollisionDetector]·[SupportRule])과
/// 별개로, 무게·연질·접근성 상식을 검사한다. 자동배치는 같은 규칙을 점수로 쓴다.
class PackingAdvisor {
  static List<Advice> advise(List<TrimBox> boxes, TrunkSpace space) {
    final out = <Advice>[];
    for (final b in boxes) {
      if (b.z >= space.d - 0.005) continue; // 트렁크 밖에 세워 둔 짐
      final name = b.label.isNotEmpty ? b.label : b.id;
      final supporters = SupportRule.supportersAt(b, b.y, boxes);

      // 자동배치가 바닥에만 두는 기준(floorOnlyKg)과 같은 문턱: 20kg 이상이 위층이면 조언
      if (b.weightKg >= AutoLayoutEngine.floorOnlyKg && b.y > SupportRule.heightTol) {
        out.add(Advice(AdviceKind.heavyHigh, b,
            '$name (${_kg(b.weightKg)}): 무거운 짐은 바닥에 두는 게 좋습니다'));
      }
      if (!b.soft && b.weightKg >= 5 && supporters.any((s) => s.soft)) {
        final under = supporters.firstWhere((s) => s.soft);
        out.add(Advice(AdviceKind.rigidOnSoft, b,
            '$name 이(가) ${_name(under)} 위에 있습니다 — 연질 짐은 맨 위나 틈에'));
      } else if (b.weightKg >= AutoLayoutEngine.lightBaseKg && supporters.isNotEmpty) {
        final light = supporters.where((s) =>
            s.weightKg > 0 &&
            s.weightKg < b.weightKg * AutoLayoutEngine.lightBaseRatio);
        if (light.isNotEmpty) {
          out.add(Advice(AdviceKind.heavyOnLight, b,
              '$name (${_kg(b.weightKg)}) 이(가) ${_name(light.first)} (${_kg(light.first.weightKg)}) 위에 있습니다'));
        }
      }
      if (b.accessPriority && b.z + b.effectiveD < space.d * 0.5) {
        // 앞쪽 절반에 있고 뒤에 다른 짐이 막고 있으면
        final blocked = boxes.any((o) =>
            o.id != b.id &&
            o.z >= b.z + b.effectiveD - 0.01 &&
            o.x < b.x + b.effectiveW &&
            o.x + o.effectiveW > b.x &&
            o.y < b.top &&
            o.top > b.y);
        if (blocked) {
          out.add(Advice(AdviceKind.accessBuried, b,
              '$name: 자주 꺼내는 짐인데 안쪽에 있고 뒤가 막혀 있습니다'));
        }
      }
    }
    return out;
  }

  static String _name(TrimBox b) => b.label.isNotEmpty ? b.label : b.id;
  static String _kg(double kg) =>
      kg == kg.roundToDouble() ? '${kg.round()}kg' : '${kg.toStringAsFixed(1)}kg';
}
