import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../models/scene.dart';
import '../painters/isometric_painter.dart';
import '../utils/collision.dart';
import '../utils/file_io.dart' as file_io;
import '../utils/json_io.dart';
import '../widgets/add_box_dialog.dart';
import '../widgets/box_list_panel.dart';
import '../widgets/trunk_size_dialog.dart';

/// 박스 파스텔 색상 팔레트
const _boxColors = [
  Color(0xFFFFB3BA),
  Color(0xFFBAE1FF),
  Color(0xFFBAFFC9),
  Color(0xFFFFFFBA),
  Color(0xFFE3BAFF),
  Color(0xFFFFD4A3),
  Color(0xFFA3FFE0),
  Color(0xFFFFA3D4),
];

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen>
    with TickerProviderStateMixin {
  late TrunkSpace _space;
  final List<TrimBox> _boxes = [];
  String? _selectedBoxId;
  Set<String> _collidingIds = {};
  int _boxCounter = 0;
  TrunkPreset _selectedPreset = TrunkPreset.tucson;

  // 카메라 방향 + 회전 애니메이션
  CameraDirection _cameraDir = CameraDirection.dir0;
  late final AnimationController _rotationController;
  CameraDirection _pendingDir = CameraDirection.dir0;
  bool _hasSwitchedDir = false;

  // 드래그 상태
  bool _isDragging = false;
  Offset? _dragStartScreen;
  double _dragStartX = 0;
  double _dragStartZ = 0;

  // 줌 & 패닝
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;
  static const double _minZoom = 0.5;
  static const double _maxZoom = 3.0;

  // 핀치 줌 제스처 추적
  double _gestureStartZoom = 1.0;
  Offset _gestureStartPanOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  // 우클릭/미들클릭 패닝
  bool _isPanning = false;
  Offset _panStartScreenPos = Offset.zero;
  Offset _panStartPanOffset = Offset.zero;

  // Undo/Redo 스택 (박스 리스트 스냅샷)
  static const int _maxUndoSteps = 50;
  final List<List<TrimBox>> _undoStack = [];
  final List<List<TrimBox>> _redoStack = [];

  // 아이소메트릭 변환에 사용하는 상수
  static const double _isoAngle = 30.0 * math.pi / 180.0;
  static final double _cosA = math.cos(_isoAngle);
  static final double _sinA = math.sin(_isoAngle);
  double _lastScale = 280.0;
  Size _lastCanvasSize = Size.zero;

  late CollisionDetector _detector;
  final FocusNode _canvasFocusNode = FocusNode();
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _space = TrunkPreset.tucson.toTrunkSpace()!;
    _detector = CollisionDetector(_space);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_rotationController.value >= 0.5 && !_hasSwitchedDir) {
          _hasSwitchedDir = true;
          setState(() {
            _cameraDir = _pendingDir;
          });
        }
      });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _canvasFocusNode.dispose();
    super.dispose();
  }

  double _calculateScale(Size canvasSize) {
    final isoWidth = (_space.w + _space.d) * _cosA;
    final isoHeight = (_space.w + _space.d) * _sinA + _space.h;
    final scaleX = canvasSize.width * 0.8 / isoWidth;
    final scaleY = canvasSize.height * 0.8 / isoHeight;
    return math.min(scaleX, scaleY);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        title: Row(
          children: [
            const Text('TrimBox'),
            const SizedBox(width: 16),
            PopupMenuButton<TrunkPreset>(
              initialValue: _selectedPreset,
              color: const Color(0xFF333333),
              onSelected: _onPresetChanged,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF555555)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedPreset == TrunkPreset.custom
                          ? '커스텀 (${(_space.w * 100).round()}×${(_space.d * 100).round()}cm)'
                          : _selectedPreset.label,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
                  ],
                ),
              ),
              itemBuilder: (_) => _buildVehicleMenuItems(),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1C1C1C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 가로가 넓으면 우측 패널, 좁으면 하단 패널
          final isWide = constraints.maxWidth > 600;
          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 3, child: _buildCanvas()),
                SizedBox(width: 280, child: _buildPanel()),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(flex: 3, child: _buildCanvas()),
                SizedBox(height: 240, child: _buildPanel()),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final baseScale = _calculateScale(canvasSize);
        final effectiveScale = baseScale * _zoomLevel;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _lastScale = effectiveScale;
          _lastCanvasSize = canvasSize;
        });

        return Stack(
          children: [
            // 캔버스 + 제스처
            Listener(
              onPointerSignal: _onPointerSignal,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              child: KeyboardListener(
                focusNode: _canvasFocusNode,
                autofocus: true,
                onKeyEvent: _onKeyEvent,
                child: GestureDetector(
                  onTapUp: _onTapUp,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      final t = _rotationController.isAnimating
                          ? (1.0 -
                              (2.0 * _rotationController.value - 1.0).abs())
                          : 0.0;
                      return Opacity(
                        opacity: 1.0 - 0.5 * t,
                        child: Transform.scale(
                          scale: 1.0 - 0.05 * t,
                          child: child,
                        ),
                      );
                    },
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: CustomPaint(
                        painter: IsometricPainter(
                          space: _space,
                          boxes: _boxes,
                          selectedBoxId: _selectedBoxId,
                          collidingBoxIds: _collidingIds,
                          scale: effectiveScale,
                          panOffset: _panOffset,
                          direction: _cameraDir,
                          draggingBoxId:
                              _isDragging ? _selectedBoxId : null,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 회전 컨트롤 오버레이
            Positioned(
              bottom: 16,
              left: 16,
              child: _buildRotationControls(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRotationControls() {
    const dirLabels = ['0°', '90°', '180°', '270°'];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.rotate_left, size: 18),
            color: Colors.white70,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            splashRadius: 18,
            tooltip: '좌회전 (Q)',
            onPressed: () => _rotateCamera(-1),
          ),
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: _cameraDir.index * math.pi / 2,
              child: const Icon(
                Icons.navigation,
                color: Colors.white54,
                size: 16,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              dirLabels[_cameraDir.index],
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.rotate_right, size: 18),
            color: Colors.white70,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            splashRadius: 18,
            tooltip: '우회전 (E)',
            onPressed: () => _rotateCamera(1),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return BoxListPanel(
      boxes: _boxes,
      space: _space,
      selectedBoxId: _selectedBoxId,
      collidingBoxIds: _collidingIds,
      onSelect: _selectBox,
      onRotate: _rotateBox,
      onDelete: _deleteBox,
      onAddBox: _showAddDialog,
      onSave: _saveScene,
      onLoad: _loadScene,
      onScreenshot: _takeScreenshot,
    );
  }

  // ──── 카메라 회전 (애니메이션) ────

  void _rotateCamera(int delta) {
    if (_rotationController.isAnimating) return;
    _pendingDir = CameraDirection.values[(_cameraDir.index + delta + 4) % 4];
    _hasSwitchedDir = false;
    _rotationController.forward(from: 0);
  }

  // ──── 이벤트 핸들러 ────

  void _onTapUp(TapUpDetails details) {
    final hit = _hitTest(details.localPosition);
    setState(() {
      _selectedBoxId = hit?.id;
    });
  }

  // ──── 줌: 마우스 휠 ────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _lastCanvasSize != Size.zero) {
      final oldZoom = _zoomLevel;
      final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final newZoom = (oldZoom * factor).clamp(_minZoom, _maxZoom);
      if (newZoom == oldZoom) return;

      // 커서 중심 줌: 커서 아래 월드 포인트가 줌 후에도 동일 위치에 유지
      final sc = Offset(_lastCanvasSize.width / 2, _lastCanvasSize.height / 2);
      final r = newZoom / oldZoom;
      setState(() {
        _panOffset = (event.localPosition - sc) * (1 - r) + _panOffset * r;
        _zoomLevel = newZoom;
      });
    }
  }

  // ──── 패닝: 우클릭/미들클릭 드래그 ────

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton ||
        event.buttons == kMiddleMouseButton) {
      _isPanning = true;
      _panStartScreenPos = event.localPosition;
      _panStartPanOffset = _panOffset;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isPanning) {
      setState(() {
        _panOffset =
            _panStartPanOffset + (event.localPosition - _panStartScreenPos);
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isPanning) {
      _isPanning = false;
    }
  }

  // ──── 제스처: 박스 드래그 + 핀치 줌 ────

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartZoom = _zoomLevel;
    _gestureStartPanOffset = _panOffset;
    _gestureStartFocalPoint = details.localFocalPoint;

    // 싱글 터치: 박스 드래그 시작 시도
    if (details.pointerCount == 1) {
      final hit = _hitTest(details.localFocalPoint);
      if (hit != null) {
        setState(() {
          _selectedBoxId = hit.id;
          _isDragging = true;
          _dragStartScreen = details.localFocalPoint;
          _dragStartX = hit.x;
          _dragStartZ = hit.z;
        });
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 멀티 터치: 핀치 줌 + 패닝
    if (details.pointerCount >= 2) {
      if (_isDragging) {
        _isDragging = false;
        _dragStartScreen = null;
      }
      final newZoom =
          (_gestureStartZoom * details.scale).clamp(_minZoom, _maxZoom);
      final sc = Offset(_lastCanvasSize.width / 2, _lastCanvasSize.height / 2);
      final r = newZoom / _gestureStartZoom;
      final zoomPan = (_gestureStartFocalPoint - sc) * (1 - r) +
          _gestureStartPanOffset * r;
      final focalDelta = details.localFocalPoint - _gestureStartFocalPoint;

      setState(() {
        _zoomLevel = newZoom;
        _panOffset = zoomPan + focalDelta;
      });
      return;
    }

    // 싱글 터치: 박스 드래그
    if (!_isDragging || _selectedBoxId == null || _dragStartScreen == null) {
      return;
    }
    final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
    final delta = details.localFocalPoint - _dragStartScreen!;

    final dx3d = _screenToWorldDX(delta.dx, delta.dy);
    final dz3d = _screenToWorldDZ(delta.dx, delta.dy);

    setState(() {
      box.x = _dragStartX + dx3d;
      box.z = _dragStartZ + dz3d;
      box.clampTo(_space.w, _space.d);
      _resolveStackingY(box);
      _updateCollisions();
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDragging && _selectedBoxId != null) {
      final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
      _pushUndo();
      setState(() {
        box.snapToGrid(_space.gridUnit);
        box.clampTo(_space.w, _space.d);
        _resolveGravity();
        _isDragging = false;
        _dragStartScreen = null;
        _updateCollisions();
      });
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+Z = Undo, Ctrl+Shift+Z / Ctrl+Y = Redo
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _redo();
      } else {
        _undo();
      }
      return;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return;
    }

    // Q: 좌회전 (CCW), E: 우회전 (CW)
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      _rotateCamera(-1);
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      _rotateCamera(1);
      return;
    }

    // 숫자 0: 줌/패닝 리셋
    if (event.logicalKey == LogicalKeyboardKey.digit0 ||
        event.logicalKey == LogicalKeyboardKey.numpad0) {
      setState(() {
        _zoomLevel = 1.0;
        _panOffset = Offset.zero;
      });
      return;
    }

    if (_selectedBoxId == null) return;
    final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
    final unit = _space.gridUnit;

    _pushUndo();
    setState(() {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          box.x -= unit;
          break;
        case LogicalKeyboardKey.arrowRight:
          box.x += unit;
          break;
        case LogicalKeyboardKey.arrowUp:
          box.z -= unit;
          break;
        case LogicalKeyboardKey.arrowDown:
          box.z += unit;
          break;
        case LogicalKeyboardKey.keyR:
          box.rotate90();
          break;
        case LogicalKeyboardKey.delete:
        case LogicalKeyboardKey.backspace:
          _boxes.removeWhere((b) => b.id == _selectedBoxId);
          _selectedBoxId = null;
          _resolveGravity();
          _updateCollisions();
          return;
        default:
          // 알 수 없는 키 → undo 스택에서 불필요한 스냅샷 제거
          if (_undoStack.isNotEmpty) _undoStack.removeLast();
          return;
      }
      box.snapToGrid(_space.gridUnit);
      box.clampTo(_space.w, _space.d);
      _resolveGravity();
      _updateCollisions();
    });
  }

  // ──── 역 아이소메트릭 변환 (direction-aware) ────

  /// Screen delta → view-space delta (X axis)
  double _screenToViewDX(double sx, double sy) {
    return (sx / (_cosA * _lastScale) + sy / (_sinA * _lastScale)) / 2;
  }

  /// Screen delta → view-space delta (Z axis)
  double _screenToViewDZ(double sx, double sy) {
    return (-sx / (_cosA * _lastScale) + sy / (_sinA * _lastScale)) / 2;
  }

  /// Screen delta → world-space delta X
  double _screenToWorldDX(double sx, double sy) {
    final dvx = _screenToViewDX(sx, sy);
    final dvz = _screenToViewDZ(sx, sy);
    switch (_cameraDir) {
      case CameraDirection.dir0: return dvx;
      case CameraDirection.dir1: return -dvz;
      case CameraDirection.dir2: return -dvx;
      case CameraDirection.dir3: return dvz;
    }
  }

  /// Screen delta → world-space delta Z
  double _screenToWorldDZ(double sx, double sy) {
    final dvx = _screenToViewDX(sx, sy);
    final dvz = _screenToViewDZ(sx, sy);
    switch (_cameraDir) {
      case CameraDirection.dir0: return dvz;
      case CameraDirection.dir1: return dvx;
      case CameraDirection.dir2: return -dvz;
      case CameraDirection.dir3: return -dvx;
    }
  }

  // ──── 히트 테스트: 탭 위치에서 박스 찾기 ────

  TrimBox? _hitTest(Offset localPos) {
    if (_lastCanvasSize == Size.zero) return null;

    // painter와 동일한 중심점 계산 (panOffset 포함)
    final center = IsometricPainter.computeCenter(
        _lastCanvasSize, _space, _lastScale, _cameraDir);
    final adjusted = Offset(
      localPos.dx - center.dx - _panOffset.dx,
      localPos.dy - center.dy - _panOffset.dy,
    );

    // 앞에 그려진 것부터 (뒤에서부터) 검사
    for (final box in _boxes.reversed) {
      if (_isPointInBox(adjusted, box)) return box;
    }
    return null;
  }

  /// 박스의 보이는 헥사곤(6각형) 외곽선 안에 포인트가 있는지 판정
  bool _isPointInBox(Offset pt, TrimBox box) {
    final w = box.effectiveW;
    final d = box.effectiveD;
    // 헥사곤 꼭짓점: p4→p5→p1→p2→p3→p7 (시계 방향, p2가 정면 아래)
    final polygon = [
      _toIso(box.x, box.y + box.h, box.z),             // p4 윗면-뒤
      _toIso(box.x + w, box.y + box.h, box.z),         // p5 윗면-오른
      _toIso(box.x + w, box.y, box.z),                  // p1 바닥-오른
      _toIso(box.x + w, box.y, box.z + d),              // p2 바닥-앞 (정면)
      _toIso(box.x, box.y, box.z + d),                  // p3 바닥-왼
      _toIso(box.x, box.y + box.h, box.z + d),          // p7 윗면-왼
    ];
    return _pointInPolygon(pt, polygon);
  }

  /// Ray-casting 알고리즘으로 폴리곤 내부 판정
  static bool _pointInPolygon(Offset pt, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i].dy, yj = polygon[j].dy;
      final xi = polygon[i].dx, xj = polygon[j].dx;
      if (((yi > pt.dy) != (yj > pt.dy)) &&
          (pt.dx < (xj - xi) * (pt.dy - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  Offset _toIso(double x, double y, double z) {
    // World → view-space transform
    double vx, vz;
    switch (_cameraDir) {
      case CameraDirection.dir0:
        vx = x; vz = z;
      case CameraDirection.dir1:
        vx = z; vz = _space.w - x;
      case CameraDirection.dir2:
        vx = _space.w - x; vz = _space.d - z;
      case CameraDirection.dir3:
        vx = _space.d - z; vz = x;
    }
    final sx = (vx - vz) * _cosA * _lastScale;
    final sy = (vx + vz) * _sinA * _lastScale - y * _lastScale;
    return Offset(sx, sy);
  }

  // ──── 박스 CRUD ────

  void _selectBox(String id) {
    setState(() {
      _selectedBoxId = _selectedBoxId == id ? null : id;
    });
  }

  void _rotateBox(String id) {
    _pushUndo();
    final box = _boxes.firstWhere((b) => b.id == id);
    setState(() {
      box.rotate90();
      box.snapToGrid(_space.gridUnit);
      box.clampTo(_space.w, _space.d);
      _resolveGravity();
      _updateCollisions();
    });
  }

  void _deleteBox(String id) {
    _pushUndo();
    setState(() {
      _boxes.removeWhere((b) => b.id == id);
      if (_selectedBoxId == id) _selectedBoxId = null;
      _resolveGravity();
      _updateCollisions();
    });
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const AddBoxDialog(),
    );
    if (result == null) return;

    _boxCounter++;
    final colorIndex = (_boxCounter - 1) % _boxColors.length;
    final selectedColor = result['color'] != null
        ? Color(result['color'] as int)
        : _boxColors[colorIndex];
    final newBox = TrimBox(
      id: 'box-${_boxCounter.toString().padLeft(3, '0')}',
      label: result['label'] as String? ?? 'Box $_boxCounter',
      w: result['w'] as double,
      d: result['d'] as double,
      h: result['h'] as double,
      color: selectedColor,
    );
    newBox.snapToGrid(_space.gridUnit);

    _pushUndo();
    setState(() {
      _boxes.add(newBox);
      _resolveStackingY(newBox);
      _selectedBoxId = newBox.id;
      _updateCollisions();
    });
  }

  // ──── 트렁크 프리셋 변경 ────

  /// 카테고리별 그룹 구분이 포함된 차종 메뉴 항목
  List<PopupMenuEntry<TrunkPreset>> _buildVehicleMenuItems() {
    final items = <PopupMenuEntry<TrunkPreset>>[];
    VehicleCategory? lastCat;

    for (final p in TrunkPreset.values) {
      final cat = p.category;

      // 카테고리 변경 시 구분 헤더
      if (cat != null && cat != lastCat) {
        if (items.isNotEmpty) {
          items.add(const PopupMenuDivider(height: 1));
        }
        items.add(PopupMenuItem<TrunkPreset>(
          enabled: false,
          height: 28,
          child: Text(
            cat.label,
            style: const TextStyle(
              color: Color(0xFF999999),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ));
      }
      lastCat = cat;

      final vol = p.volumeLiters;
      items.add(PopupMenuItem<TrunkPreset>(
        value: p,
        child: Row(
          children: [
            Expanded(
              child: Text(
                p.label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (vol != null)
              Text(
                '${vol}L',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
          ],
        ),
      ));
    }
    return items;
  }

  Future<void> _onPresetChanged(TrunkPreset preset) async {
    TrunkSpace? newSpace;

    if (preset == TrunkPreset.custom) {
      newSpace = await showDialog<TrunkSpace>(
        context: context,
        builder: (_) => const TrunkSizeDialog(),
      );
      if (newSpace == null) return;
    } else {
      newSpace = preset.toTrunkSpace();
    }

    if (newSpace == null) return;

    setState(() {
      _selectedPreset = preset;
      _space = newSpace!;
      _detector = CollisionDetector(_space);
      for (final box in _boxes) {
        box.snapToGrid(_space.gridUnit);
        box.clampTo(_space.w, _space.d);
      }
      _updateCollisions();
    });
  }

  // ──── 저장/불러오기 (파일 기반) ────

  Future<void> _saveScene() async {
    final scene = Scene(space: _space, boxes: _boxes);
    final jsonStr = JsonIO.exportScene(scene);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = 'trimbox-$timestamp.json';

    try {
      file_io.downloadJson(jsonStr, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$filename 저장 완료'),
            backgroundColor: const Color(0xFF6BD06B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: const Color(0xFFFF4D4D),
          ),
        );
      }
    }
  }

  Future<void> _loadScene() async {
    try {
      final jsonStr = await file_io.pickJsonFile();
      if (jsonStr == null || jsonStr.isEmpty) return;

      final scene = JsonIO.importScene(jsonStr);
      setState(() {
        _space = scene.space;
        _detector = CollisionDetector(_space);
        _selectedPreset = TrunkPreset.custom;
        _boxes
          ..clear()
          ..addAll(scene.boxes);
        int maxId = 0;
        for (final b in _boxes) {
          final match = RegExp(r'box-(\d+)').firstMatch(b.id);
          if (match != null) {
            final n = int.tryParse(match.group(1)!) ?? 0;
            if (n > maxId) maxId = n;
          }
        }
        _boxCounter = maxId > _boxes.length ? maxId : _boxes.length;
        _selectedBoxId = null;
        _updateCollisions();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${scene.boxes.length}개 박스를 불러왔습니다'),
            backgroundColor: const Color(0xFF6BD06B),
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('잘못된 파일 형식: $e'),
            backgroundColor: const Color(0xFFFF4D4D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('불러오기 실패: $e'),
            backgroundColor: const Color(0xFFFF4D4D),
          ),
        );
      }
    }
  }

  // ──── 스크린샷 ────

  Future<void> _takeScreenshot() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(
          format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final filename = 'trimbox-$timestamp.png';

      file_io.downloadBytes(bytes, filename, 'image/png');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$filename 저장 완료'),
            backgroundColor: const Color(0xFF6BD06B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('스크린샷 실패: $e'),
            backgroundColor: const Color(0xFFFF4D4D),
          ),
        );
      }
    }
  }

  // ──── Undo/Redo ────

  /// 현재 박스 상태를 undo 스택에 저장 (변경 전 호출)
  void _pushUndo() {
    _undoStack.add(_boxes.map((b) => b.copyWith()).toList());
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    // 현재 상태를 redo에 저장
    _redoStack.add(_boxes.map((b) => b.copyWith()).toList());
    final prev = _undoStack.removeLast();
    setState(() {
      _boxes
        ..clear()
        ..addAll(prev);
      _selectedBoxId = null;
      _updateCollisions();
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_boxes.map((b) => b.copyWith()).toList());
    final next = _redoStack.removeLast();
    setState(() {
      _boxes
        ..clear()
        ..addAll(next);
      _selectedBoxId = null;
      _updateCollisions();
    });
  }

  // ──── 스태킹 Y 해소 ────

  /// 박스의 Y를 XZ 겹침 기반으로 계산 (50% 이상 겹치면 위에 적재)
  void _resolveStackingY(TrimBox box) {
    double supportY = 0;
    final boxArea = box.effectiveW * box.effectiveD;

    for (final other in _boxes) {
      if (other.id == box.id) continue;
      final overlapX =
          math.min(box.x + box.effectiveW, other.x + other.effectiveW) -
              math.max(box.x, other.x);
      final overlapZ =
          math.min(box.z + box.effectiveD, other.z + other.effectiveD) -
              math.max(box.z, other.z);

      if (overlapX > 0 && overlapZ > 0) {
        final overlapArea = overlapX * overlapZ;
        if (overlapArea >= boxArea * 0.5) {
          final candidateY = other.y + other.h;
          if (candidateY > supportY) supportY = candidateY;
        }
      }
    }

    box.y = supportY;
  }

  /// 모든 박스의 Y를 아래에서 위로 재계산 (중력)
  void _resolveGravity() {
    // 원래 Y 순서(아래→위)로 정렬
    final sorted = List<TrimBox>.from(_boxes)
      ..sort((a, b) => a.y.compareTo(b.y));

    // 아래에서 위로 순차 처리: 이미 정착된 아래 박스만 지지면으로 사용
    for (int i = 0; i < sorted.length; i++) {
      final box = sorted[i];
      double supportY = 0;
      final boxArea = box.effectiveW * box.effectiveD;

      for (int j = 0; j < i; j++) {
        final other = sorted[j];
        final overlapX = math.min(
                box.x + box.effectiveW, other.x + other.effectiveW) -
            math.max(box.x, other.x);
        final overlapZ = math.min(
                box.z + box.effectiveD, other.z + other.effectiveD) -
            math.max(box.z, other.z);
        if (overlapX > 0 && overlapZ > 0) {
          final overlapArea = overlapX * overlapZ;
          if (overlapArea >= boxArea * 0.5) {
            final candidateY = other.y + other.h;
            if (candidateY > supportY) supportY = candidateY;
          }
        }
      }
      box.y = supportY;
    }
  }

  // ──── 충돌 업데이트 ────

  void _updateCollisions() {
    _collidingIds = _detector.findAllCollisions(_boxes);
  }
}
