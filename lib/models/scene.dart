import 'dart:convert';

import 'trunk_space.dart';
import 'trim_box.dart';

/// 전체 씬(트렁크 + 박스들) 모델
class Scene {
  final String version;
  final TrunkSpace space;
  final double gridUnit;
  final List<TrimBox> boxes;

  Scene({
    this.version = '1.0.0',
    required this.space,
    this.gridUnit = 0.10,
    List<TrimBox>? boxes,
  }) : boxes = boxes ?? [];

  Map<String, dynamic> toJson() => {
        'version': version,
        'space': space.toJson(),
        'grid': gridUnit,
        'boxes': boxes.map((b) => b.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
        version: json['version'] as String? ?? '1.0.0',
        space: TrunkSpace.fromJson(json['space'] as Map<String, dynamic>),
        gridUnit: (json['grid'] as num?)?.toDouble() ?? 0.10,
        boxes: (json['boxes'] as List<dynamic>?)
                ?.map((b) => TrimBox.fromJson(b as Map<String, dynamic>))
                .toList() ??
            [],
      );

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  factory Scene.fromJsonString(String jsonStr) =>
      Scene.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
}
