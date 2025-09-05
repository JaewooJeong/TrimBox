import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/engine/isometric_engine.dart';
import 'package:trimbox/math/vector3d.dart';
import 'package:trimbox/objects/isometric_box.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

void main() {
  group('IsometricEngine Performance Tests', () {
    late IsometricEngine engine;
    
    setUp(() {
      engine = IsometricEngine(
        backgroundColor: Colors.grey.shade100,
      );
    });
    
    tearDown(() {
      engine.dispose();
    });

    test('엔진 초기화 성능 테스트', () {
      final stopwatch = Stopwatch()..start();
      
      final testEngine = IsometricEngine();
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
      expect(testEngine.objects.length, equals(0));
      
      testEngine.dispose();
    });

    test('대량 객체 추가 성능 테스트', () {
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < 1000; i++) {
        final box = IsometricBox(
          id: 'box_$i',
          position: Vector3D(
            i % 10.0,
            (i / 10) % 10.0,
            (i / 100) % 10.0,
          ),
          dimensions: const Vector3D(1, 1, 1),
          color: Colors.blue,
        );
        engine.addObject(box);
      }
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
      expect(engine.objects.length, equals(1000));
    });

    test('객체 렌더링 우선순위 정렬 성능', () {
      // 무작위 위치의 객체들 추가
      final random = math.Random();
      for (int i = 0; i < 500; i++) {
        final box = IsometricBox(
          id: 'box_$i',
          position: Vector3D(
            random.nextDouble() * 10,
            random.nextDouble() * 5,
            random.nextDouble() * 10,
          ),
          dimensions: const Vector3D(1, 1, 1),
          color: Colors.red,
        );
        engine.addObject(box);
      }
      
      final stopwatch = Stopwatch()..start();
      
      // 렌더링 호출 (정렬 포함)
      final canvas = MockCanvas();
      engine.render(canvas, const Size(800, 600));
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('경계 계산 성능 테스트', () {
      for (int i = 0; i < 100; i++) {
        final box = IsometricBox(
          id: 'box_$i',
          position: Vector3D(i.toDouble(), 0, 0),
          dimensions: const Vector3D(1, 2, 1),
          color: Colors.green,
        );
        engine.addObject(box);
      }
      
      final stopwatch = Stopwatch()..start();
      
      final bounds = engine.getAllObjectsBounds();
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(10));
      expect(bounds, isNotNull);
      expect(bounds!.width, greaterThan(90));
    });

    test('히트 테스트 성능', () {
      // 격자 패턴으로 객체 배치
      for (int x = 0; x < 10; x++) {
        for (int z = 0; z < 10; z++) {
          final box = IsometricBox(
            id: 'box_${x}_$z',
            position: Vector3D(x.toDouble(), 0, z.toDouble()),
            dimensions: const Vector3D(0.8, 1, 0.8),
            color: Colors.orange,
          );
          engine.addObject(box);
        }
      }
      
      final stopwatch = Stopwatch()..start();
      
      // 여러 점에서 히트 테스트 수행
      for (int i = 0; i < 100; i++) {
        final point = engine.transform.to2D(Vector3D(
          i % 10.0,
          0,
          (i / 10) % 10.0,
        ));
        engine.findObjectAt(point);
      }
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(20));
    });

    test('메모리 사용량 테스트', () {
      final initialObjectCount = engine.objects.length;
      
      // 대량 객체 추가
      for (int i = 0; i < 1000; i++) {
        final box = IsometricBox(
          id: 'temp_box_$i',
          position: Vector3D(i.toDouble(), 0, 0),
          dimensions: const Vector3D(1, 1, 1),
          color: Colors.purple,
        );
        engine.addObject(box);
      }
      
      expect(engine.objects.length, equals(initialObjectCount + 1000));
      
      // 모든 객체 제거
      engine.clearObjects();
      
      expect(engine.objects.length, equals(0));
    });

    test('변환 매트릭스 성능 테스트', () {
      final transform = engine.transform;
      final testPoints = List.generate(1000, (i) => Vector3D(
        i.toDouble(),
        (i * 0.5) % 10,
        (i * 0.3) % 10,
      ));
      
      final stopwatch = Stopwatch()..start();
      
      for (final point in testPoints) {
        transform.to2D(point);
      }
      
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(5));
    });

    test('프레임 레이트 시뮬레이션', () {
      // 복합적인 씬 생성
      _createComplexScene(engine);
      
      final frameCount = 60;
      final frameTimes = <int>[];
      
      for (int frame = 0; frame < frameCount; frame++) {
        final stopwatch = Stopwatch()..start();
        
        final canvas = MockCanvas();
        engine.render(canvas, const Size(1920, 1080));
        
        stopwatch.stop();
        frameTimes.add(stopwatch.elapsedMicroseconds);
      }
      
      final averageFrameTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;
      final fps = 1000000 / averageFrameTime;
      
      print('평균 FPS: ${fps.toStringAsFixed(2)}');
      print('평균 프레임 시간: ${averageFrameTime.toStringAsFixed(2)}μs');
      
      expect(fps, greaterThan(30)); // 최소 30 FPS
    });
  });
}

void _createComplexScene(IsometricEngine engine) {
  // 바닥
  final floor = IsometricBox(
    id: 'floor',
    position: const Vector3D(-10, -0.5, -10),
    dimensions: const Vector3D(20, 0.5, 20),
    color: Colors.grey.shade300,
  );
  engine.addObject(floor);
  
  // 건물들
  final random = math.Random(42); // 시드 고정으로 재현 가능한 테스트
  for (int i = 0; i < 50; i++) {
    final building = IsometricBox(
      id: 'building_$i',
      position: Vector3D(
        (random.nextDouble() - 0.5) * 15,
        0,
        (random.nextDouble() - 0.5) * 15,
      ),
      dimensions: Vector3D(
        1 + random.nextDouble() * 2,
        2 + random.nextDouble() * 5,
        1 + random.nextDouble() * 2,
      ),
      color: Color.fromRGBO(
        100 + random.nextInt(155),
        100 + random.nextInt(155),
        100 + random.nextInt(155),
        1.0,
      ),
    );
    engine.addObject(building);
  }
}

class MockCanvas implements Canvas {
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {}

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) {}

  @override
  void clipRect(Rect rect, {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) {}

  @override
  void clipRSuperellipse(ui.RSuperellipse rsuperellipse, {bool doAntiAlias = true}) {}

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {}

  @override
  void drawAtlas(ui.Image atlas, List<ui.RSTransform> transforms, List<Rect> rects, List<Color>? colors, ui.BlendMode? blendMode, Rect? cullRect, Paint paint) {}

  @override
  void drawCircle(Offset c, double radius, Paint paint) {}

  @override
  void drawColor(Color color, ui.BlendMode blendMode) {}

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {}

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {}

  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) {}

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {}

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {}

  @override
  void drawOval(Rect rect, Paint paint) {}

  @override
  void drawPaint(Paint paint) {}

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {}

  @override
  void drawPath(Path path, Paint paint) {}

  @override
  void drawPicture(ui.Picture picture) {}

  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) {}

  @override
  void drawRRect(RRect rrect, Paint paint) {}

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, Paint paint) {}

  @override
  void drawRawAtlas(ui.Image atlas, Float32List rstTransforms, Float32List rects, Int32List? colors, ui.BlendMode? blendMode, Rect? cullRect, Paint paint) {}

  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) {}

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {}

  @override
  void drawVertices(ui.Vertices vertices, ui.BlendMode blendMode, Paint paint) {}

  @override
  Rect getDestinationClipBounds() => Rect.zero;

  @override
  Rect getLocalClipBounds() => Rect.zero;

  @override
  int getSaveCount() => 0;

  @override
  Float64List getTransform() => Float64List(16);

  @override
  void restore() {}

  @override
  void restoreToCount(int count) {}

  @override
  void rotate(double radians) {}

  @override
  void save() {}

  @override
  void saveLayer(Rect? bounds, Paint paint) {}

  @override
  void scale(double sx, [double? sy]) {}

  @override
  void skew(double sx, double sy) {}

  @override
  void transform(Float64List matrix4) {}

  @override
  void translate(double dx, double dy) {}
}