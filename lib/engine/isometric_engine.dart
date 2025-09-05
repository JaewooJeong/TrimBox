import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../math/vector2d.dart';
import '../math/vector3d.dart';
import '../math/isometric_transform.dart';
import '../objects/isometric_object.dart';

/// 아이소메트릭 렌더링 엔진의 핵심 클래스
/// 3D 객체들을 관리하고 2D 아이소메트릭 뷰로 렌더링
class IsometricEngine {
  /// 현재 변환 매트릭스
  IsometricTransform _transform;
  
  /// 렌더링할 객체들
  final List<IsometricObject> _objects = [];
  
  /// 배경 색상
  Color backgroundColor;
  
  /// 조명 설정
  IsometricLighting lighting;
  
  /// 카메라 설정
  IsometricCamera camera;
  
  /// 성능 모니터링
  final IsometricPerformance _performance = IsometricPerformance();

  IsometricEngine({
    IsometricTransform? transform,
    this.backgroundColor = Colors.white,
    IsometricLighting? lighting,
    IsometricCamera? camera,
  }) : _transform = transform ?? IsometricTransform.standard(),
        lighting = lighting ?? IsometricLighting.standard(),
        camera = camera ?? IsometricCamera.standard();

  /// 현재 변환 매트릭스
  IsometricTransform get transform => _transform;
  
  /// 모든 객체 목록 (읽기 전용)
  UnmodifiableListView<IsometricObject> get objects => 
      UnmodifiableListView(_objects);

  /// 성능 정보
  IsometricPerformance get performance => _performance;

  /// 객체 추가
  void addObject(IsometricObject object) {
    _objects.add(object);
    _sortObjectsByRenderPriority();
  }

  /// 객체 제거
  bool removeObject(IsometricObject object) {
    return _objects.remove(object);
  }

  /// ID로 객체 제거
  bool removeObjectById(String id) {
    final index = _objects.indexWhere((obj) => obj.id == id);
    if (index != -1) {
      _objects.removeAt(index);
      return true;
    }
    return false;
  }

  /// 모든 객체 제거
  void clearObjects() {
    _objects.clear();
  }

  /// ID로 객체 찾기
  IsometricObject? findObjectById(String id) {
    try {
      return _objects.firstWhere((obj) => obj.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 위치로 객체 찾기 (클릭 감지)
  IsometricObject? findObjectAt(Vector2D screenPoint) {
    // 앞에서부터 (가장 나중에 렌더링된) 순서로 확인
    for (int i = _objects.length - 1; i >= 0; i--) {
      final obj = _objects[i];
      if (obj.visible && obj.hitTest(screenPoint, _transform)) {
        return obj;
      }
    }
    return null;
  }

  /// 영역 내의 모든 객체 찾기
  List<IsometricObject> findObjectsInBounds(IsometricBounds bounds) {
    return _objects.where((obj) {
      if (!obj.visible) return false;
      final objBounds = obj.getBounds(_transform);
      return bounds.intersects(objBounds);
    }).toList();
  }

  /// 변환 매트릭스 업데이트
  void setTransform(IsometricTransform newTransform) {
    _transform = newTransform;
  }

  /// 스케일 변경
  void setScale(double scale) {
    _transform = _transform.withScale(scale);
  }

  /// 오프셋 변경
  void setOffset(Vector2D offset) {
    _transform = _transform.withOffset(offset);
  }

  /// 카메라 위치 변경
  void setCameraPosition(Vector3D position) {
    camera = camera.withPosition(position);
    _updateTransformFromCamera();
  }

  /// 카메라 각도 변경
  void setCameraRotation(double yaw, double pitch) {
    camera = camera.withRotation(yaw, pitch);
    _updateTransformFromCamera();
  }

  /// 줌 인/아웃
  void zoom(double factor) {
    final newScale = (_transform.scale * factor).clamp(0.1, 10.0);
    setScale(newScale);
  }

  /// 화면을 특정 영역에 맞추기
  void fitToBounds(IsometricBounds bounds, Size screenSize) {
    final scaleX = screenSize.width / bounds.width;
    final scaleY = screenSize.height / bounds.height;
    final scale = math.min(scaleX, scaleY) * 0.8; // 여백을 위해 80%
    
    final centerOffset = Vector2D(
      screenSize.width / 2 - bounds.center.x * scale,
      screenSize.height / 2 - bounds.center.y * scale,
    );
    
    _transform = IsometricTransform(
      scale: scale,
      offset: centerOffset,
    );
  }

  /// 모든 객체가 보이도록 화면 조정
  void fitToAllObjects(Size screenSize) {
    if (_objects.isEmpty) return;
    
    final allBounds = getAllObjectsBounds();
    if (allBounds != null) {
      fitToBounds(allBounds, screenSize);
    }
  }

  /// 모든 객체의 경계 계산
  IsometricBounds? getAllObjectsBounds() {
    if (_objects.isEmpty) return null;
    
    final visibleObjects = _objects.where((obj) => obj.visible);
    if (visibleObjects.isEmpty) return null;
    
    final firstBounds = visibleObjects.first.getBounds(_transform);
    double minX = firstBounds.min.x;
    double maxX = firstBounds.max.x;
    double minY = firstBounds.min.y;
    double maxY = firstBounds.max.y;
    
    for (final obj in visibleObjects.skip(1)) {
      final bounds = obj.getBounds(_transform);
      minX = math.min(minX, bounds.min.x);
      maxX = math.max(maxX, bounds.max.x);
      minY = math.min(minY, bounds.min.y);
      maxY = math.max(maxY, bounds.max.y);
    }
    
    return IsometricBounds(
      min: Vector2D(minX, minY),
      max: Vector2D(maxX, maxY),
    );
  }

  /// 장면 렌더링
  void render(Canvas canvas, Size size) {
    _performance._startFrame();
    
    // 배경 그리기
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
    
    // 클리핑 영역 설정
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    // 객체들을 렌더링 우선순위 순으로 그리기
    _sortObjectsByRenderPriority();
    
    for (final object in _objects) {
      if (object.visible) {
        _performance._incrementObjectsRendered();
        
        // 객체가 화면 내에 있는지 확인 (컬링)
        final bounds = object.getBounds(_transform);
        final screenBounds = IsometricBounds(
          min: Vector2D.zero,
          max: Vector2D(size.width, size.height),
        );
        
        if (bounds.intersects(screenBounds)) {
          object.render(canvas, _transform);
        } else {
          _performance._incrementObjectsCulled();
        }
      }
    }
    
    _performance._endFrame();
  }

  /// 객체들을 렌더링 우선순위로 정렬
  void _sortObjectsByRenderPriority() {
    _objects.sort((a, b) => a.renderPriority.compareTo(b.renderPriority));
  }

  /// 카메라 설정으로부터 변환 매트릭스 업데이트
  void _updateTransformFromCamera() {
    // 카메라 각도와 위치를 고려한 변환 계산
    // 간단한 구현 - 실제로는 더 복잡한 3D 변환이 필요
    final scale = camera.zoom;
    final offset = Vector2D(
      -camera.position.x * scale,
      -camera.position.z * scale,
    );
    
    _transform = IsometricTransform(
      scale: scale,
      offset: offset,
    );
  }

  /// 디버그 정보 출력
  String getDebugInfo() {
    return '''
IsometricEngine Debug Info:
- Objects: ${_objects.length}
- Scale: ${_transform.scale.toStringAsFixed(2)}
- Offset: ${_transform.offset}
- Performance: ${_performance.averageFps.toStringAsFixed(1)} FPS
- Camera: ${camera.position}
''';
  }

  /// 메모리 정리
  void dispose() {
    _objects.clear();
    _performance.reset();
  }
}

/// 조명 설정
class IsometricLighting {
  final Vector3D direction;
  final Color color;
  final double intensity;
  final double ambientIntensity;

  const IsometricLighting({
    required this.direction,
    this.color = Colors.white,
    this.intensity = 1.0,
    this.ambientIntensity = 0.3,
  });

  factory IsometricLighting.standard() {
    return IsometricLighting(
      direction: Vector3D(-1, -1, -1).normalized,
      intensity: 0.8,
      ambientIntensity: 0.4,
    );
  }

  IsometricLighting withDirection(Vector3D newDirection) {
    return IsometricLighting(
      direction: newDirection.normalized,
      color: color,
      intensity: intensity,
      ambientIntensity: ambientIntensity,
    );
  }
}

/// 카메라 설정
class IsometricCamera {
  final Vector3D position;
  final double yaw;
  final double pitch;
  final double zoom;

  const IsometricCamera({
    this.position = Vector3D.zero,
    this.yaw = 0.0,
    this.pitch = 0.0,
    this.zoom = 1.0,
  });

  factory IsometricCamera.standard() {
    return const IsometricCamera(
      position: Vector3D(0, 5, 0),
      zoom: 1.0,
    );
  }

  IsometricCamera withPosition(Vector3D newPosition) {
    return IsometricCamera(
      position: newPosition,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
  }

  IsometricCamera withRotation(double newYaw, double newPitch) {
    return IsometricCamera(
      position: position,
      yaw: newYaw,
      pitch: newPitch,
      zoom: zoom,
    );
  }

  IsometricCamera withZoom(double newZoom) {
    return IsometricCamera(
      position: position,
      yaw: yaw,
      pitch: pitch,
      zoom: newZoom,
    );
  }
}

/// 성능 모니터링
class IsometricPerformance {
  final List<Duration> _frameTimes = [];
  DateTime? _frameStartTime;
  int _objectsRendered = 0;
  int _objectsCulled = 0;
  int _totalFrames = 0;

  double get averageFps {
    if (_frameTimes.isEmpty) return 0.0;
    final avgDuration = _frameTimes
        .map((d) => d.inMicroseconds)
        .reduce((a, b) => a + b) / _frameTimes.length;
    return 1000000.0 / avgDuration; // 1초 = 1,000,000 마이크로초
  }

  int get objectsRendered => _objectsRendered;
  int get objectsCulled => _objectsCulled;
  int get totalFrames => _totalFrames;

  void _startFrame() {
    _frameStartTime = DateTime.now();
    _objectsRendered = 0;
    _objectsCulled = 0;
  }

  void _endFrame() {
    if (_frameStartTime != null) {
      final frameDuration = DateTime.now().difference(_frameStartTime!);
      _frameTimes.add(frameDuration);
      
      // 최근 60 프레임만 유지
      if (_frameTimes.length > 60) {
        _frameTimes.removeAt(0);
      }
      
      _totalFrames++;
    }
  }

  void _incrementObjectsRendered() => _objectsRendered++;
  void _incrementObjectsCulled() => _objectsCulled++;

  void reset() {
    _frameTimes.clear();
    _totalFrames = 0;
    _objectsRendered = 0;
    _objectsCulled = 0;
  }
}