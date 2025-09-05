import 'package:flutter/material.dart';
import '../math/vector3d.dart';

class ApartmentBlueprint {
  final ApartmentInfo info;
  final Dimensions dimensions;
  final List<Room> rooms;
  final List<Wall> walls;
  final List<Door> doors;
  final List<Window> windows;
  final List<Fixture> fixtures;
  final AreasSummary areasSummary;

  const ApartmentBlueprint({
    required this.info,
    required this.dimensions,
    required this.rooms,
    required this.walls,
    required this.doors,
    required this.windows,
    required this.fixtures,
    required this.areasSummary,
  });

  factory ApartmentBlueprint.fromJson(Map<String, dynamic> json) {
    return ApartmentBlueprint(
      info: ApartmentInfo.fromJson(json['apartment_info']),
      dimensions: Dimensions.fromJson(json['dimensions']),
      rooms: (json['rooms'] as List)
          .map((room) => Room.fromJson(room))
          .toList(),
      walls: (json['walls'] as List)
          .map((wall) => Wall.fromJson(wall))
          .toList(),
      doors: (json['doors'] as List)
          .map((door) => Door.fromJson(door))
          .toList(),
      windows: (json['windows'] as List)
          .map((window) => Window.fromJson(window))
          .toList(),
      fixtures: (json['fixtures'] as List)
          .map((fixture) => Fixture.fromJson(fixture))
          .toList(),
      areasSummary: AreasSummary.fromJson(json['areas_summary']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apartment_info': info.toJson(),
      'dimensions': dimensions.toJson(),
      'rooms': rooms.map((room) => room.toJson()).toList(),
      'walls': walls.map((wall) => wall.toJson()).toList(),
      'doors': doors.map((door) => door.toJson()).toList(),
      'windows': windows.map((window) => window.toJson()).toList(),
      'fixtures': fixtures.map((fixture) => fixture.toJson()).toList(),
      'areas_summary': areasSummary.toJson(),
    };
  }

  double get scaleFactor => 0.01;
  
  Vector3D get size3D => Vector3D(
    dimensions.totalWidth * scaleFactor,
    2.4,
    dimensions.totalHeight * scaleFactor,
  );
}

class ApartmentInfo {
  final String name;
  final int sizePyeong;
  final double sizeSqm;
  final String layoutType;
  final String description;
  final String createdDate;

  const ApartmentInfo({
    required this.name,
    required this.sizePyeong,
    required this.sizeSqm,
    required this.layoutType,
    required this.description,
    required this.createdDate,
  });

  factory ApartmentInfo.fromJson(Map<String, dynamic> json) {
    return ApartmentInfo(
      name: json['name'],
      sizePyeong: json['size_pyeong'],
      sizeSqm: json['size_sqm'].toDouble(),
      layoutType: json['layout_type'],
      description: json['description'],
      createdDate: json['created_date'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size_pyeong': sizePyeong,
      'size_sqm': sizeSqm,
      'layout_type': layoutType,
      'description': description,
      'created_date': createdDate,
    };
  }
}

class Dimensions {
  final double totalWidth;
  final double totalHeight;
  final double wallThickness;
  final String unit;

  const Dimensions({
    required this.totalWidth,
    required this.totalHeight,
    required this.wallThickness,
    required this.unit,
  });

  factory Dimensions.fromJson(Map<String, dynamic> json) {
    return Dimensions(
      totalWidth: json['total_width'].toDouble(),
      totalHeight: json['total_height'].toDouble(),
      wallThickness: json['wall_thickness'].toDouble(),
      unit: json['unit'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_width': totalWidth,
      'total_height': totalHeight,
      'wall_thickness': wallThickness,
      'unit': unit,
    };
  }
}

class Room {
  final String id;
  final String name;
  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double areaSqm;
  final String colorHex;

  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.areaSqm,
    required this.colorHex,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      areaSqm: json['area_sqm'].toDouble(),
      colorHex: json['color'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'area_sqm': areaSqm,
      'color': colorHex,
    };
  }

  Color get color => Color(int.parse(colorHex.replaceAll('#', '0xFF')));
  
  Vector3D get position3D => Vector3D(x * 0.01, 0.0, y * 0.01);
  
  Vector3D get size3D => Vector3D(width * 0.01, 0.1, height * 0.01);

  double get roomHeight {
    switch (type) {
      case 'bathroom':
        return 2.3;
      case 'balcony':
        return 2.2;
      case 'utility':
      case 'storage':
        return 2.2;
      default:
        return 2.4;
    }
  }
}

class Wall {
  final String id;
  final String name;
  final String type;
  final List<List<double>> points;
  final double thickness;
  final String material;

  const Wall({
    required this.id,
    required this.name,
    required this.type,
    required this.points,
    required this.thickness,
    required this.material,
  });

  factory Wall.fromJson(Map<String, dynamic> json) {
    return Wall(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      points: (json['points'] as List)
          .map((point) => (point as List)
              .map((coord) => coord.toDouble())
              .toList())
          .toList(),
      thickness: json['thickness'].toDouble(),
      material: json['material'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'points': points,
      'thickness': thickness,
      'material': material,
    };
  }

  Vector3D get start3D => Vector3D(
    points[0][0] * 0.01,
    0.0,
    points[0][1] * 0.01,
  );

  Vector3D get end3D => Vector3D(
    points[1][0] * 0.01,
    0.0,
    points[1][1] * 0.01,
  );

  double get wallHeight {
    switch (type) {
      case 'exterior':
        return 2.4;
      case 'interior':
        return 2.3;
      default:
        return 2.3;
    }
  }
}

class Door {
  final String id;
  final String name;
  final String type;
  final String roomFrom;
  final String roomTo;
  final Position position;
  final double width;
  final String direction;
  final String material;

  const Door({
    required this.id,
    required this.name,
    required this.type,
    required this.roomFrom,
    required this.roomTo,
    required this.position,
    required this.width,
    required this.direction,
    required this.material,
  });

  factory Door.fromJson(Map<String, dynamic> json) {
    return Door(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      roomFrom: json['room_from'],
      roomTo: json['room_to'],
      position: Position.fromJson(json['position']),
      width: json['width'].toDouble(),
      direction: json['direction'],
      material: json['material'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'room_from': roomFrom,
      'room_to': roomTo,
      'position': position.toJson(),
      'width': width,
      'direction': direction,
      'material': material,
    };
  }

  Vector3D get position3D => Vector3D(
    position.x * 0.01,
    0.0,
    position.y * 0.01,
  );

  double get doorHeight => 2.1;
}

class Window {
  final String id;
  final String name;
  final String room;
  final Position position;
  final double width;
  final double height;
  final String type;

  const Window({
    required this.id,
    required this.name,
    required this.room,
    required this.position,
    required this.width,
    required this.height,
    required this.type,
  });

  factory Window.fromJson(Map<String, dynamic> json) {
    return Window(
      id: json['id'],
      name: json['name'],
      room: json['room'],
      position: Position.fromJson(json['position']),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      type: json['type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'room': room,
      'position': position.toJson(),
      'width': width,
      'height': height,
      'type': type,
    };
  }

  Vector3D get position3D => Vector3D(
    position.x * 0.01,
    1.0,
    position.y * 0.01,
  );
}

class Fixture {
  final String id;
  final String name;
  final String type;
  final String room;
  final Position position;
  final double width;
  final double height;

  const Fixture({
    required this.id,
    required this.name,
    required this.type,
    required this.room,
    required this.position,
    required this.width,
    required this.height,
  });

  factory Fixture.fromJson(Map<String, dynamic> json) {
    return Fixture(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      room: json['room'],
      position: Position.fromJson(json['position']),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'room': room,
      'position': position.toJson(),
      'width': width,
      'height': height,
    };
  }

  Vector3D get position3D => Vector3D(
    position.x * 0.01,
    0.0,
    position.y * 0.01,
  );

  Vector3D get size3D => Vector3D(
    width * 0.01,
    fixtureHeight,
    height * 0.01,
  );

  double get fixtureHeight {
    switch (type) {
      case 'sink':
        return 0.85;
      case 'stove':
        return 0.85;
      case 'toilet':
        return 0.4;
      case 'appliance':
        return 1.0;
      default:
        return 0.8;
    }
  }
}

class Position {
  final double x;
  final double y;

  const Position({required this.x, required this.y});

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y};
  }
}

class AreasSummary {
  final double totalAreaSqm;
  final double livingAreaSqm;
  final double serviceAreaSqm;
  final Map<String, int> roomsCount;

  const AreasSummary({
    required this.totalAreaSqm,
    required this.livingAreaSqm,
    required this.serviceAreaSqm,
    required this.roomsCount,
  });

  factory AreasSummary.fromJson(Map<String, dynamic> json) {
    return AreasSummary(
      totalAreaSqm: json['total_area_sqm'].toDouble(),
      livingAreaSqm: json['living_area_sqm'].toDouble(),
      serviceAreaSqm: json['service_area_sqm'].toDouble(),
      roomsCount: Map<String, int>.from(json['rooms_count']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_area_sqm': totalAreaSqm,
      'living_area_sqm': livingAreaSqm,
      'service_area_sqm': serviceAreaSqm,
      'rooms_count': roomsCount,
    };
  }
}