class Box {
  final String id;
  final double width;
  final double depth;
  final double height;
  double x;
  double y;
  double z;
  double rotationY;
  
  Box({
    required this.id,
    required this.width,
    required this.depth,
    required this.height,
    this.x = 0.0,
    this.y = 0.0,
    this.z = 0.0,
    this.rotationY = 0.0,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'width': width,
    'depth': depth,
    'height': height,
    'x': x,
    'y': y,
    'z': z,
    'rotationY': rotationY,
  };
  
  factory Box.fromJson(Map<String, dynamic> json) => Box(
    id: json['id'],
    width: json['width'],
    depth: json['depth'],
    height: json['height'],
    x: json['x'] ?? 0.0,
    y: json['y'] ?? 0.0,
    z: json['z'] ?? 0.0,
    rotationY: json['rotationY'] ?? 0.0,
  );
}