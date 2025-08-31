class TrunkSpace {
  final double width;
  final double depth;
  final double height;
  final double gridSize;
  final List<Wheelhouse> wheelhouses;
  
  const TrunkSpace({
    required this.width,
    required this.depth,
    required this.height,
    this.gridSize = 0.1, // 10cm grid
    this.wheelhouses = const [],
  });
  
  // Predefined trunk sizes
  static const small = TrunkSpace(
    width: 2.0,
    depth: 2.0,
    height: 1.2,
    wheelhouses: [
      Wheelhouse(x: 0.1, z: 0.1, width: 0.3, depth: 0.4, height: 0.2),
      Wheelhouse(x: 1.6, z: 0.1, width: 0.3, depth: 0.4, height: 0.2),
    ],
  );
  
  static const medium = TrunkSpace(
    width: 3.0,
    depth: 3.0,
    height: 1.2,
    wheelhouses: [
      Wheelhouse(x: 0.15, z: 0.15, width: 0.35, depth: 0.5, height: 0.25),
      Wheelhouse(x: 2.5, z: 0.15, width: 0.35, depth: 0.5, height: 0.25),
    ],
  );
  
  static const large = TrunkSpace(
    width: 4.0,
    depth: 4.0,
    height: 1.2,
    wheelhouses: [
      Wheelhouse(x: 0.2, z: 0.2, width: 0.4, depth: 0.6, height: 0.3),
      Wheelhouse(x: 3.4, z: 0.2, width: 0.4, depth: 0.6, height: 0.3),
    ],
  );
  
  Map<String, dynamic> toJson() => {
    'width': width,
    'depth': depth,
    'height': height,
    'gridSize': gridSize,
    'wheelhouses': wheelhouses.map((w) => w.toJson()).toList(),
  };
  
  factory TrunkSpace.fromJson(Map<String, dynamic> json) => TrunkSpace(
    width: json['width'],
    depth: json['depth'],
    height: json['height'],
    gridSize: json['gridSize'] ?? 0.1,
    wheelhouses: (json['wheelhouses'] as List<dynamic>?)
        ?.map((w) => Wheelhouse.fromJson(w))
        .toList() ?? [],
  );
}

class Wheelhouse {
  final double x;
  final double z;
  final double width;
  final double depth;
  final double height;
  
  const Wheelhouse({
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
    required this.height,
  });
  
  Map<String, dynamic> toJson() => {
    'x': x,
    'z': z,
    'width': width,
    'depth': depth,
    'height': height,
  };
  
  factory Wheelhouse.fromJson(Map<String, dynamic> json) => Wheelhouse(
    x: json['x'],
    z: json['z'],
    width: json['width'],
    depth: json['depth'],
    height: json['height'],
  );
}