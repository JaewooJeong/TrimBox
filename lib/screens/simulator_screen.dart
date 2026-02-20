import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../models/scene.dart';
import '../painters/isometric_painter.dart';
import '../utils/collision.dart';
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

class _SimulatorScreenState extends State<SimulatorScreen> {
  late TrunkSpace _space;
  final List<TrimBox> _boxes = [];
  String? _selectedBoxId;
  Set<String> _collidingIds = {};
  int _boxCounter = 0;
  TrunkPreset _selectedPreset = TrunkPreset.suv;

  // 드래그 상태
  bool _isDragging = false;
  Offset? _dragStartScreen;
  double _dragStartX = 0;
  double _dragStartZ = 0;

  // 아이소메트릭 변환에 사용하는 상수
  static const double _isoAngle = 30.0 * math.pi / 180.0;
  static final double _cosA = math.cos(_isoAngle);
  static final double _sinA = math.sin(_isoAngle);
  double _lastScale = 280.0;

  late CollisionDetector _detector;

  @override
  void initState() {
    super.initState();
    _space = TrunkPreset.suv.toTrunkSpace()!;
    _detector = CollisionDetector(_space);
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
            DropdownButton<TrunkPreset>(
              value: _selectedPreset,
              dropdownColor: const Color(0xFF333333),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              items: TrunkPreset.values.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(p.label),
                );
              }).toList(),
              selectedItemBuilder: (_) => TrunkPreset.values.map((p) {
                if (p == TrunkPreset.custom && _selectedPreset == TrunkPreset.custom) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '커스텀 (${(_space.w * 100).round()}×${(_space.d * 100).round()}cm)',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(p.label,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                );
              }).toList(),
              onChanged: (p) {
                if (p != null) _onPresetChanged(p);
              },
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
          final isWide = constraints.maxWidth > 700;
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
        _lastScale = _calculateScale(canvasSize);

        return KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: _onKeyEvent,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTapUp: _onTapUp,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: IsometricPainter(
                  space: _space,
                  boxes: _boxes,
                  selectedBoxId: _selectedBoxId,
                  collidingBoxIds: _collidingIds,
                  scale: _lastScale,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
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
    );
  }

  // ──── 이벤트 핸들러 ────

  void _onTapUp(TapUpDetails details) {
    final hit = _hitTest(details.localPosition);
    setState(() {
      _selectedBoxId = hit?.id;
    });
  }

  void _onPanStart(DragStartDetails details) {
    final hit = _hitTest(details.localPosition);
    if (hit != null) {
      setState(() {
        _selectedBoxId = hit.id;
        _isDragging = true;
        _dragStartScreen = details.localPosition;
        _dragStartX = hit.x;
        _dragStartZ = hit.z;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _selectedBoxId == null || _dragStartScreen == null) {
      return;
    }
    final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
    final delta = details.localPosition - _dragStartScreen!;

    // 2D 화면 이동량 → 3D 좌표 변환 (역 아이소메트릭)
    final dx3d = _screenToIsoX(delta.dx, delta.dy);
    final dz3d = _screenToIsoDx(delta.dx, delta.dy);

    setState(() {
      box.x = _dragStartX + dx3d;
      box.z = _dragStartZ + dz3d;
      box.clampTo(_space.w, _space.d);
      _updateCollisions();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDragging && _selectedBoxId != null) {
      final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
      setState(() {
        box.snapToGrid(_space.gridUnit);
        box.clampTo(_space.w, _space.d);
        _isDragging = false;
        _dragStartScreen = null;
        _updateCollisions();
      });
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _selectedBoxId == null) return;
    final box = _boxes.firstWhere((b) => b.id == _selectedBoxId);
    final unit = _space.gridUnit;

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
          break;
        default:
          return;
      }
      box.snapToGrid(_space.gridUnit);
      box.clampTo(_space.w, _space.d);
      _updateCollisions();
    });
  }

  // ──── 역 아이소메트릭 변환 ────

  double _screenToIsoX(double sx, double sy) {
    return (sx / (_cosA * _lastScale) + sy / (_sinA * _lastScale)) / 2;
  }

  double _screenToIsoDx(double sx, double sy) {
    return (-sx / (_cosA * _lastScale) + sy / (_sinA * _lastScale)) / 2;
  }

  // ──── 히트 테스트: 탭 위치에서 박스 찾기 ────

  TrimBox? _hitTest(Offset localPos) {
    // 캔버스 중앙 기준 변환
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final canvasSize = renderBox.size;
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height * 0.55;
    final adjusted = Offset(localPos.dx - cx, localPos.dy - cy);

    // 뒤에서부터(위에 그려진 것부터) 검사
    for (final box in _boxes.reversed) {
      if (_isPointInBox(adjusted, box)) return box;
    }
    return null;
  }

  bool _isPointInBox(Offset screenPt, TrimBox box) {
    // 박스 윗면의 4꼭짓점을 아이소메트릭 변환
    final pts = [
      _toIso(box.x, box.y + box.h, box.z),
      _toIso(box.x + box.effectiveW, box.y + box.h, box.z),
      _toIso(box.x + box.effectiveW, box.y + box.h, box.z + box.effectiveD),
      _toIso(box.x, box.y + box.h, box.z + box.effectiveD),
    ];
    // + 정면(오른쪽면 + 왼쪽면) 포함한 넓은 바운딩
    final allPts = [
      ...pts,
      _toIso(box.x, box.y, box.z),
      _toIso(box.x + box.effectiveW, box.y, box.z),
      _toIso(box.x + box.effectiveW, box.y, box.z + box.effectiveD),
      _toIso(box.x, box.y, box.z + box.effectiveD),
    ];

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in allPts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    return screenPt.dx >= minX &&
        screenPt.dx <= maxX &&
        screenPt.dy >= minY &&
        screenPt.dy <= maxY;
  }

  Offset _toIso(double x, double y, double z) {
    final sx = (x - z) * _cosA * _lastScale;
    final sy = (x + z) * _sinA * _lastScale - y * _lastScale;
    return Offset(sx, sy);
  }

  // ──── 박스 CRUD ────

  void _selectBox(String id) {
    setState(() {
      _selectedBoxId = _selectedBoxId == id ? null : id;
    });
  }

  void _rotateBox(String id) {
    final box = _boxes.firstWhere((b) => b.id == id);
    setState(() {
      box.rotate90();
      box.snapToGrid(_space.gridUnit);
      _updateCollisions();
    });
  }

  void _deleteBox(String id) {
    setState(() {
      _boxes.removeWhere((b) => b.id == id);
      if (_selectedBoxId == id) _selectedBoxId = null;
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
    final newBox = TrimBox(
      id: 'box-${_boxCounter.toString().padLeft(3, '0')}',
      label: result['label'] as String? ?? 'Box $_boxCounter',
      w: result['w'] as double,
      d: result['d'] as double,
      h: result['h'] as double,
      color: _boxColors[colorIndex],
    );
    newBox.snapToGrid(_space.gridUnit);

    setState(() {
      _boxes.add(newBox);
      _selectedBoxId = newBox.id;
      _updateCollisions();
    });
  }

  // ──── 트렁크 프리셋 변경 ────

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

  // ──── 저장/불러오기 ────

  Future<void> _saveScene() async {
    final scene = Scene(space: _space, boxes: _boxes);
    final jsonStr = JsonIO.exportScene(scene);

    // 클립보드에 복사
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('씬 JSON이 클립보드에 복사되었습니다'),
          backgroundColor: Color(0xFF6BD06B),
        ),
      );
    }
  }

  Future<void> _loadScene() async {
    final ctrl = TextEditingController();
    final jsonStr = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title:
            const Text('JSON 불러오기', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'JSON을 붙여넣으세요',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('불러오기'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (jsonStr == null || jsonStr.isEmpty) return;

    try {
      final scene = JsonIO.importScene(jsonStr);
      setState(() {
        _boxes
          ..clear()
          ..addAll(scene.boxes);
        _boxCounter = _boxes.length;
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

  // ──── 충돌 업데이트 ────

  void _updateCollisions() {
    _collidingIds = _detector.findAllCollisions(_boxes);
  }
}
