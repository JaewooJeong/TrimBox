import 'box.dart';
import 'trunk_space.dart';

class Scene {
  final String version;
  final TrunkSpace trunkSpace;
  final List<Box> boxes;
  
  Scene({
    this.version = '1.0.0',
    required this.trunkSpace,
    required this.boxes,
  });
  
  Map<String, dynamic> toJson() => {
    'version': version,
    'trunkSpace': trunkSpace.toJson(),
    'boxes': boxes.map((b) => b.toJson()).toList(),
  };
  
  factory Scene.fromJson(Map<String, dynamic> json) => Scene(
    version: json['version'] ?? '1.0.0',
    trunkSpace: TrunkSpace.fromJson(json['trunkSpace']),
    boxes: (json['boxes'] as List<dynamic>)
        .map((b) => Box.fromJson(b))
        .toList(),
  );
}