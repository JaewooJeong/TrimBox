import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/auto_layout.dart';
import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../models/scene.dart';
import '../models/support.dart';
import '../render3d/camera.dart';
import '../render3d/geometry.dart';
import '../render3d/picking.dart';
import '../render3d/trunk_painter_3d.dart';
import '../render3d/vec3.dart';
import '../utils/collision.dart';
import '../utils/file_io.dart' as file_io;
import '../utils/json_io.dart';
import '../utils/scene_storage.dart' as storage;
import '../widgets/add_box_dialog.dart';
import '../widgets/box_list_panel.dart';
import '../widgets/keyboard_shortcuts_dialog.dart';
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
  TrunkPreset _selectedPreset = TrunkPreset.sorento;

  // 온보딩
  bool _showOnboarding = true;
  bool _hasEverAddedBox = false;

  /// 사용자가 손으로 옮기거나 돌린 적이 있으면 true.
  /// false 인 동안은 장비를 추가할 때마다 전체를 다시 자동 배치한다.
  bool _manualEdited = false;
  Timer? _autosaveTimer;

  /// 1차 배포 차종 메뉴: 쏘렌토 MQ4 두 구성 + 커스텀
  static const List<TrunkPreset> _releasePresets = [
    TrunkPreset.sorento,
    TrunkPreset.sorento7,
    TrunkPreset.custom,
  ];

  // 3D 카메라 (첫 레이아웃에서 트렁크에 맞춰 초기화)
  OrbitCamera? _camera;
  double _fitDistance = 1.0;
  final SceneCache _sceneCache = SceneCache();
  static const double _minZoomFactor = 0.45;
  static const double _maxZoomFactor = 2.5;
  static const double _defaultPitch = 22 * math.pi / 180;

  // 드래그 상태 (박스 이동)
  bool _isDragging = false;
  Vec3 _dragGrabOffset = Vec3.zero; // 잡은 지점 - 박스 원점 (x, z)

  // 빈 곳 드래그 = 카메라 회전
  bool _isOrbiting = false;
  Offset _orbitLastPos = Offset.zero;

  // 핀치 줌 제스처 추적
  OrbitCamera? _gestureStartCamera;
  Offset _gestureStartFocalPoint = Offset.zero;

  // 미들클릭 / 우클릭 패닝
  bool _isPanning = false;
  Offset _panStartScreenPos = Offset.zero;
  Offset _panStartPan = Offset.zero;

  // Undo/Redo 스택
  static const int _maxUndoSteps = 50;
  final List<List<TrimBox>> _undoStack = [];
  final List<List<TrimBox>> _redoStack = [];

  // 터치/마우스 판별
  bool _lastPointerIsTouch = false;

  // Step-by-step loading guide
  bool _stepViewActive = false;
  int _stepViewCurrentStep = 1; // 1-based load order

  Size _lastCanvasSize = Size.zero;

  late CollisionDetector _detector;
  final FocusNode _canvasFocusNode = FocusNode();
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _space = TrunkPreset.sorento.toTrunkSpace()!;
    _detector = CollisionDetector(_space);
    // 웹에서 한글 폴백 폰트가 늦게 로드되면 캔버스 라벨이 □ 로 남는다.
    // 폰트 변경 알림을 받으면 다시 그린다.
    PaintingBinding.instance.systemFonts.addListener(_onSystemFontsChanged);
    _restoreSession();
  }

  void _onSystemFontsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChanged);
    _autosaveTimer?.cancel();
    _canvasFocusNode.dispose();
    _sceneCache.dispose();
    super.dispose();
  }

  /// 온보딩 표시 여부와 마지막 작업 상태 복원
  Future<void> _restoreSession() async {
    try {
      final seen = await storage.hasSeenOnboarding();
      final auto = await storage.loadAutosave();
      if (!mounted) return;
      if (seen) setState(() => _showOnboarding = false);
      if (auto != null && _boxes.isEmpty) _applySceneJson(auto, silent: true);
    } catch (_) {
      // 저장소를 못 쓰는 환경에서는 조용히 넘어간다
    }
  }

  /// 마지막 작업 상태를 잠시 뒤 저장 (연속 조작 중 과도한 저장 방지)
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        storage.saveAutosave(
            JsonIO.exportScene(Scene(space: _space, boxes: _boxes)));
      } catch (_) {}
    });
  }

  /// 씬의 트렁크가 어느 프리셋인지 (차종명으로 식별), 없으면 커스텀
  TrunkPreset _presetForSpace(TrunkSpace space) {
    for (final p in TrunkPreset.values) {
      if (p == TrunkPreset.custom) continue;
      if (p.toTrunkSpace()?.vehicleName == space.vehicleName) return p;
    }
    return TrunkPreset.custom;
  }

  /// 캔버스 크기에 맞는 카메라 확보. 크기가 바뀌면 현재 각도·줌 비율을 유지한 채
  /// 거리만 다시 맞춘다.
  OrbitCamera _ensureCamera(Size canvasSize) {
    final cam = _camera;
    if (cam != null && _lastCanvasSize == canvasSize) return cam;
    final fitted = OrbitCamera.fitTrunk(
      _space,
      canvasSize,
      yaw: cam?.yaw ?? 0.0,
      pitch: cam?.pitch ?? _defaultPitch,
    );
    final zoomRatio = cam == null ? 1.0 : cam.distance / _fitDistance;
    _fitDistance = fitted.distance;
    _lastCanvasSize = canvasSize;
    _camera = fitted.copyWith(
      distance: fitted.distance * zoomRatio,
      pan: cam?.pan ?? Offset.zero,
    );
    return _camera!;
  }

  /// 각도·거리 제한을 적용해 카메라를 갱신
  void _setCamera(OrbitCamera cam) {
    _camera = cam.clamped(
      minDistance: _fitDistance * _minZoomFactor,
      maxDistance: _fitDistance * _maxZoomFactor,
    );
  }

  void _resetCamera() {
    setState(() {
      _camera = null;
      if (_lastCanvasSize != Size.zero) _ensureCamera(_lastCanvasSize);
    });
  }

  /// 트렁크가 바뀌었을 때 (프리셋 변경/불러오기) 거리를 다시 맞춘다.
  void _refitCamera() {
    final cam = _camera;
    if (cam == null || _lastCanvasSize == Size.zero) return;
    final fitted = OrbitCamera.fitTrunk(_space, _lastCanvasSize,
        yaw: cam.yaw, pitch: cam.pitch);
    _fitDistance = fitted.distance;
    _camera = fitted;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 22),
            tooltip: '키보드 단축키 (?)',
            onPressed: _showKeyboardShortcuts,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w > 900) {
            return Row(
              children: [
                Expanded(flex: 3, child: _buildCanvas()),
                SizedBox(width: 320, child: _buildPanel()),
              ],
            );
          } else if (w >= 600) {
            return Row(
              children: [
                Expanded(flex: 3, child: _buildCanvas()),
                SizedBox(width: 280, child: _buildPanel()),
              ],
            );
          } else {
            return Stack(
              children: [
                // 시트 초기 높이만큼 비워 트렁크가 가려지지 않게 한다
                Positioned.fill(
                  bottom: constraints.maxHeight * 0.28,
                  child: _buildCanvas(),
                ),
                DraggableScrollableSheet(
                  initialChildSize: 0.28,
                  minChildSize: 0.12,
                  maxChildSize: 0.85,
                  builder: (ctx, scrollCtrl) => _buildDraggablePanel(scrollCtrl),
                ),
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
        final camera = _ensureCamera(canvasSize);

        return Stack(
          children: [
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
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CustomPaint(
                      painter: TrunkPainter3D(
                        space: _space,
                        boxes: _boxes,
                        camera: camera,
                        selectedBoxId: _selectedBoxId,
                        collidingBoxIds: _collidingIds,
                        draggingBoxId: _isDragging ? _selectedBoxId : null,
                        highlightLoadOrder: _stepViewActive ? _stepViewCurrentStep : null,
                        cache: _sceneCache,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            // Utilization progress bar (top)
            if (_boxes.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildUtilizationBar(),
              ),
            // Utilization info overlay (top-right)
            if (_boxes.isNotEmpty)
              Positioned(
                top: 12,
                right: 12,
                child: _buildUtilizationOverlay(),
              ),
            // Step view controls
            if (_stepViewActive)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: _buildStepViewControls(),
              ),
            // Onboarding
            if (_showOnboarding && _boxes.isEmpty)
              _buildOnboardingOverlay(canvasSize),
          ],
        );
      },
    );
  }

  // ──── 적재율 계산 ────

  double _totalTrunkVolume() => _space.usableVolume;

  double _usedVolume() {
    return _boxes.fold<double>(0.0, (sum, b) => sum + b.w * b.d * b.h);
  }

  double _utilizationPercent() {
    final total = _totalTrunkVolume();
    if (total <= 0) return 0;
    return (_usedVolume() / total * 100).clamp(0, 999);
  }

  Color _utilizationColor(double pct) {
    if (pct < 70) return const Color(0xFF4CAF50);
    if (pct < 90) return const Color(0xFFFFC107);
    return const Color(0xFFFF5252);
  }

  Widget _buildUtilizationBar() {
    final pct = _utilizationPercent();
    final color = _utilizationColor(pct);
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0.0, 1.0),
        backgroundColor: const Color(0x33FFFFFF),
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 3,
      ),
    );
  }

  Widget _buildUtilizationOverlay() {
    final pct = _utilizationPercent();
    final color = _utilizationColor(pct);
    final totalLiters = (_totalTrunkVolume() * 1000).round();
    final usedLiters = (_usedVolume() * 1000).round();
    final remainingLiters = (totalLiters - usedLiters).clamp(0, 999999);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC1C1C1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '적재율 ',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '총 짐: ${_boxes.length}개',
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            '남은 공간: ~${remainingLiters}L',
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ──── Step View Controls ────

  int get _maxLoadOrder {
    int max = 0;
    for (final b in _boxes) {
      if (b.loadOrder != null && b.loadOrder! > max) max = b.loadOrder!;
    }
    return max;
  }

  void _enterStepView() {
    if (_maxLoadOrder < 1) return;
    setState(() {
      _stepViewActive = true;
      _stepViewCurrentStep = 1;
    });
  }

  void _exitStepView() {
    setState(() {
      _stepViewActive = false;
    });
  }

  Widget _buildStepViewControls() {
    final maxStep = _maxLoadOrder;
    final currentBox = _boxes.where((b) => b.loadOrder == _stepViewCurrentStep).firstOrNull;
    final boxName = currentBox != null
        ? (currentBox.label.isNotEmpty ? currentBox.label : currentBox.id)
        : '';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xEE1C1C1C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00E676), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              tooltip: '스텝뷰 닫기',
              onPressed: _exitStepView,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 8),
            // Previous
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
              onPressed: _stepViewCurrentStep > 1
                  ? () => setState(() => _stepViewCurrentStep--)
                  : null,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),
            // Step info
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP $_stepViewCurrentStep / $maxStep',
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (boxName.isNotEmpty)
                  Text(
                    boxName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            const SizedBox(width: 8),
            // Next
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white, size: 28),
              onPressed: _stepViewCurrentStep < maxStep
                  ? () => setState(() => _stepViewCurrentStep++)
                  : null,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingOverlay(Size canvasSize) {
    final isNarrow = canvasSize.width < 600;
    final isTouch = _lastPointerIsTouch;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() => _showOnboarding = false);
          storage.markOnboardingSeen();
        },
        child: Container(
          color: const Color(0x88000000),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF4DA3FF), width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined, color: Color(0xFF4DA3FF), size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '박스를 추가하여\n시뮬레이션을 시작하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Icon(isNarrow ? Icons.arrow_downward : Icons.arrow_forward, color: const Color(0xFF4DA3FF), size: 28),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('조작법', style: TextStyle(color: Color(0xFF4DA3FF), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        if (isTouch) ...[
                          _controlRow('박스 드래그', '박스 이동'),
                          _controlRow('빈 곳 드래그', '카메라 회전'),
                          _controlRow('핀치', '줌 인/아웃'),
                          _controlRow('두 손가락 드래그', '패닝'),
                        ] else ...[
                          _controlRow('박스 드래그', '박스 이동'),
                          _controlRow('빈 곳 드래그', '카메라 회전'),
                          _controlRow('마우스 휠', '줌 인/아웃'),
                          _controlRow('우클릭 드래그', '패닝'),
                          _controlRow('R', '박스 회전'),
                          _controlRow('?', '단축키 도움말'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('아무 곳이나 탭하여 닫기', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlRow(String key, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 11))),
          Expanded(child: Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 11))),
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
      onAutoLayout: _boxes.isNotEmpty ? _showAutoLayoutDialog : null,
      onQuickCheck: _boxes.isNotEmpty ? _showQuickFitCheck : null,
      onStepView: _boxes.isNotEmpty ? _enterStepView : null,
      onShareCard: _boxes.isNotEmpty ? _generateShareCard : null,
    );
  }

  Widget _buildDraggablePanel(ScrollController scrollCtrl) {
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
      onAutoLayout: _boxes.isNotEmpty ? _showAutoLayoutDialog : null,
      onQuickCheck: _boxes.isNotEmpty ? _showQuickFitCheck : null,
      onStepView: _boxes.isNotEmpty ? _enterStepView : null,
      onShareCard: _boxes.isNotEmpty ? _generateShareCard : null,
      scrollController: scrollCtrl,
      showDragHandle: true,
    );
  }

  void _showKeyboardShortcuts() {
    showDialog(context: context, builder: (_) => const KeyboardShortcutsDialog());
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
    final cam = _camera;
    if (event is PointerScrollEvent && cam != null) {
      final factor = event.scrollDelta.dy > 0 ? 1.1 : 0.9;
      setState(() => _setCamera(cam.copyWith(distance: cam.distance * factor)));
    }
  }

  // ──── 우클릭/미들클릭 = pan ────

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton ||
        event.buttons == kMiddleMouseButton) {
      _isPanning = true;
      _panStartScreenPos = event.localPosition;
      _panStartPan = _camera?.pan ?? Offset.zero;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    final cam = _camera;
    if (_isPanning && cam != null) {
      setState(() {
        _camera = cam.copyWith(
            pan: _panStartPan + (event.localPosition - _panStartScreenPos));
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _isPanning = false;
  }

  // ──── 제스처: 박스 드래그 / 카메라 회전 / 핀치 줌 ────

  void _onScaleStart(ScaleStartDetails details) {
    final cam = _camera;
    if (cam == null) return;
    _gestureStartCamera = cam;
    _gestureStartFocalPoint = details.localFocalPoint;
    _canvasFocusNode.requestFocus();

    if (details.pointerCount != 1) return;
    _lastPointerIsTouch = details.kind == PointerDeviceKind.touch;

    final hit = _hitTest(details.localFocalPoint);
    if (hit != null) {
      final ray = cam.ray(details.localFocalPoint, _lastCanvasSize);
      final p = rayPlaneY(ray, hit.y) ?? Vec3(hit.x, hit.y, hit.z);
      _pushUndo();
      setState(() {
        _manualEdited = true;
        _selectedBoxId = hit.id;
        _isDragging = true;
        _dragGrabOffset = Vec3(p.x - hit.x, 0, p.z - hit.z);
        // 수동 이동은 자동배치 순서를 무효화
        for (final b in _boxes) {
          b.loadOrder = null;
        }
      });
    } else {
      _isOrbiting = true;
      _orbitLastPos = details.localFocalPoint;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final cam = _camera;
    if (cam == null) return;

    if (details.pointerCount >= 2) {
      // 핀치 줌 + 두 손가락 패닝
      _isDragging = false;
      _isOrbiting = false;
      final start = _gestureStartCamera ?? cam;
      final focalDelta = details.localFocalPoint - _gestureStartFocalPoint;
      setState(() {
        _setCamera(start.copyWith(
          distance: start.distance / details.scale.clamp(0.2, 5.0),
          pan: start.pan + focalDelta,
        ));
      });
      return;
    }

    if (_isOrbiting) {
      final delta = details.localFocalPoint - _orbitLastPos;
      _orbitLastPos = details.localFocalPoint;
      const k = 0.004; // rad/px: 화면 폭 ~800px 드래그 = 약 180°
      setState(() {
        _setCamera(cam.copyWith(
          yaw: cam.yaw - delta.dx * k,
          pitch: cam.pitch + delta.dy * k,
        ));
      });
      return;
    }

    if (!_isDragging || _selectedBoxId == null) return;
    final boxIndex = _boxes.indexWhere((b) => b.id == _selectedBoxId);
    if (boxIndex == -1) return;
    final box = _boxes[boxIndex];

    // 현재 박스 바닥 높이의 수평면에 커서를 투영. 적층 높이가 바뀌면
    // 다음 이동에서 새 높이의 평면을 쓴다.
    final ray = cam.ray(details.localFocalPoint, _lastCanvasSize);
    final p = rayPlaneY(ray, box.y);
    if (p == null) return;

    setState(() {
      box.x = p.x - _dragGrabOffset.x;
      box.z = p.z - _dragGrabOffset.z;
      box.clampTo(_space.w, _space.d);
      _resolveStackingY(box);
      _updateCollisions();
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isOrbiting = false;
    _gestureStartCamera = null;
    if (_isDragging && _selectedBoxId != null) {
      final boxIndex = _boxes.indexWhere((b) => b.id == _selectedBoxId);
      setState(() {
        if (boxIndex != -1) {
          final box = _boxes[boxIndex];
          box.snapToGrid(_space.gridUnit);
          box.clampTo(_space.w, _space.d);
          _resolveGravity();
        }
        _isDragging = false;
        _updateCollisions();
      });
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) { _redo(); } else { _undo(); }
      return;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return;
    }

    if (event.character == '?') {
      _showKeyboardShortcuts();
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.digit0 ||
        event.logicalKey == LogicalKeyboardKey.numpad0) {
      _resetCamera();
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ ||
        event.logicalKey == LogicalKeyboardKey.keyE) {
      final cam = _camera;
      if (cam != null) {
        final dir = event.logicalKey == LogicalKeyboardKey.keyQ ? 1.0 : -1.0;
        setState(() => _setCamera(
            cam.copyWith(yaw: cam.yaw + dir * 10 * math.pi / 180)));
      }
      return;
    }

    if (_selectedBoxId == null) return;
    final boxIndex = _boxes.indexWhere((b) => b.id == _selectedBoxId);
    if (boxIndex == -1) return;
    final box = _boxes[boxIndex];
    final unit = _space.gridUnit;

    _pushUndo();
    setState(() {
      _manualEdited = true;
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
          if (_undoStack.isNotEmpty) _undoStack.removeLast();
          return;
      }
      box.snapToGrid(_space.gridUnit);
      box.clampTo(_space.w, _space.d);
      _resolveGravity();
      _updateCollisions();
    });
  }

  // ──── 히트 테스트 (레이캐스트) ────

  /// 화면 좌표에서 카메라 반직선을 쏴 가장 가까운 박스를 고른다.
  TrimBox? _hitTest(Offset localPos) {
    final cam = _camera;
    if (cam == null || _lastCanvasSize == Size.zero) return null;
    final ray = cam.ray(localPos, _lastCanvasSize);
    TrimBox? best;
    var bestT = double.infinity;
    for (final box in _boxes) {
      if (_stepViewActive &&
          box.loadOrder != null &&
          box.loadOrder! > _stepViewCurrentStep) {
        continue; // 스텝 뷰에서 숨겨진 박스
      }
      final t = rayAabbHit(ray, Aabb.fromBox(box));
      if (t != null && t < bestT) {
        bestT = t;
        best = box;
      }
    }
    return best;
  }

  // ──── 박스 CRUD ────

  void _selectBox(String id) {
    setState(() { _selectedBoxId = _selectedBoxId == id ? null : id; });
  }

  void _rotateBox(String id) {
    _pushUndo();
    final box = _boxes.firstWhere((b) => b.id == id);
    setState(() {
      _manualEdited = true;
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
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => const AddBoxDialog(),
    );
    if (result == null || result.isEmpty) return;

    _pushUndo();
    setState(() {
      String? lastBoxId;
      for (int i = 0; i < result.length; i++) {
        final item = result[i];
        _boxCounter++;
        final colorIndex = (_boxCounter - 1) % _boxColors.length;
        final selectedColor = item['color'] != null
            ? Color(item['color'] as int)
            : _boxColors[colorIndex];
        final catIndex = item['category'] as int?;
        final boxCategory = catIndex != null
            ? BoxCategory.values[
                catIndex.clamp(0, BoxCategory.values.length - 1)]
            : BoxCategory.custom;

        final newBox = TrimBox(
          id: 'box-${_boxCounter.toString().padLeft(3, '0')}',
          label: item['label'] as String? ?? 'Box $_boxCounter',
          w: item['w'] as double,
          d: item['d'] as double,
          h: item['h'] as double,
          color: selectedColor,
          category: boxCategory,
          keepUpright: item['upright'] == true,
        );

        _placeNewBox(newBox);
        _boxes.add(newBox);
        lastBoxId = newBox.id;
      }

      _selectedBoxId = lastBoxId;
      _updateCollisions();
      if (!_hasEverAddedBox) {
        _hasEverAddedBox = true;
        _showOnboarding = false;
        storage.markOnboardingSeen();
      }
    });
    // 손으로 옮긴 적이 없으면 전체를 다시 자동 배치해 바로 판정을 보여준다
    if (!_manualEdited) _autoPackQuietly();
  }

  /// 모달 없이 자동 배치를 적용하고 스낵바로 판정만 알린다
  void _autoPackQuietly() {
    if (_boxes.isEmpty) return;
    final result =
        AutoLayoutEngine.computeLayout(_space, _boxes, restarts: 24);
    setState(() {
      for (final p in result.placements) {
        p.applyTo(_boxes.firstWhere((b) => b.id == p.box.id));
      }
      _parkUnfitBoxes(result);
      _selectedBoxId = null;
      _updateCollisions();
    });
    if (mounted) _showVerdictSnackBar(result);
  }

  /// 못 넣은 박스는 테일게이트 앞 바닥에 나란히 둔다 (경계 밖 = 빨간 표시)
  void _parkUnfitBoxes(AutoLayoutResult result) {
    var x = 0.0;
    for (final u in result.unfitBoxes) {
      final box = _boxes.firstWhere((b) => b.id == u.id);
      box
        ..rotY = 0
        ..x = x
        ..z = _space.d + 0.06
        ..y = 0
        ..loadOrder = null;
      x += box.effectiveW + 0.05;
    }
  }

  /// 새 박스를 비어 있는 자리에 놓는다: 바닥(뒷좌석 쪽부터) → 기존 박스 위 →
  /// 그래도 없으면 테일게이트 앞쪽 (충돌 표시로 사용자에게 알림).
  void _placeNewBox(TrimBox box) {
    const step = 0.05;
    for (final allowStack in [false, true]) {
      for (final rot in [0, 90]) {
        box.rotY = rot;
        final maxX = _space.w - box.effectiveW;
        final maxZ = _space.d - box.effectiveD;
        if (maxX < 0 || maxZ < 0) continue;
        for (var z = 0.0; z <= maxZ + 1e-9; z += step) {
          for (var x = 0.0; x <= maxX + 1e-9; x += step) {
            box.x = x;
            box.z = z;
            box.y = allowStack ? SupportRule.highestLevel(box, _boxes, _space) : 0.0;
            if (!_detector.hasCollision(box, _boxes)) return;
          }
        }
      }
    }
    box.rotY = 0;
    box.x = ((_space.w - box.effectiveW) / 2).clamp(0.0, _space.w);
    box.z = (_space.d - box.effectiveD).clamp(0.0, _space.d);
    box.y = SupportRule.highestLevel(box, _boxes, _space);
  }

  // ──── 트렁크 프리셋 변경 ────

  List<PopupMenuEntry<TrunkPreset>> _buildVehicleMenuItems() {
    final items = <PopupMenuEntry<TrunkPreset>>[];
    VehicleCategory? lastCat;

    for (final p in _releasePresets) {
      final cat = p.category;

      if (cat != null && cat != lastCat) {
        if (items.isNotEmpty) {
          items.add(const PopupMenuDivider(height: 1));
        }
        items.add(PopupMenuItem<TrunkPreset>(
          enabled: false,
          height: 28,
          child: Text(cat.label, style: const TextStyle(color: Color(0xFF999999), fontSize: 11, fontWeight: FontWeight.bold)),
        ));
      }
      lastCat = cat;

      final vol = p.volumeLiters;
      items.add(PopupMenuItem<TrunkPreset>(
        value: p,
        child: Row(
          children: [
            Expanded(child: Text(p.label, style: const TextStyle(color: Colors.white, fontSize: 13))),
            if (vol != null) Text('${vol}L', style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
          ],
        ),
      ));
    }
    return items;
  }

  Future<void> _onPresetChanged(TrunkPreset preset) async {
    TrunkSpace? newSpace;

    if (preset == TrunkPreset.custom) {
      newSpace = await showDialog<TrunkSpace>(context: context, builder: (_) => const TrunkSizeDialog());
      if (newSpace == null) return;
    } else {
      newSpace = preset.toTrunkSpace();
    }

    if (newSpace == null) return;

    setState(() {
      _selectedPreset = preset;
      _space = newSpace!;
      _detector = CollisionDetector(_space);
      _refitCamera();
      for (final box in _boxes) {
        box.snapToGrid(_space.gridUnit);
        box.clampTo(_space.w, _space.d);
      }
      _resolveGravity();
      _updateCollisions();
    });
  }

  // ──── 저장/불러오기 ────

  String get _currentVehicleName {
    if (_selectedPreset == TrunkPreset.custom) return '커스텀';
    return _selectedPreset.label.split(' (').first;
  }

  Future<void> _saveScene() async {
    final defaultName = '$_currentVehicleName - ${_boxes.length}개 적재';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: defaultName);
        return AlertDialog(
          backgroundColor: const Color(0xFF333333),
          title: const Text('배치 저장', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: '배치 이름',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF555555)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4DA3FF)),
              ),
            ),
            onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveSceneToFile();
              },
              child: const Text('파일로 내보내기',
                  style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DA3FF),
              ),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    try {
      // Check for duplicate name and confirm overwrite
      final existingScenes = await storage.listSavedScenes();
      final hasDuplicate = existingScenes.any((s) => s.name == name);
      if (hasDuplicate && mounted) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF333333),
            title: const Text('배치 덮어쓰기', style: TextStyle(color: Colors.white)),
            content: Text(
              "'$name' 배치가 이미 존재합니다. 덮어쓰시겠습니까?",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFAA33),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('덮어쓰기'),
              ),
            ],
          ),
        );
        if (overwrite != true) return;
      }

      final scene = Scene(space: _space, boxes: _boxes);
      final jsonStr = JsonIO.exportScene(scene);
      await storage.saveSceneToStorage(
          name, jsonStr, _currentVehicleName, _boxes.length);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('"$name" 저장 완료'),
              backgroundColor: const Color(0xFF6BD06B)),
        );
      }
    } on UnsupportedError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('이 플랫폼에서는 저장 기능을 지원하지 않습니다'),
              backgroundColor: Color(0xFFFF4D4D)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('저장 실패: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    }
  }

  void _saveSceneToFile() {
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
              backgroundColor: const Color(0xFF6BD06B)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('파일 저장 실패: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    }
  }

  Future<void> _loadScene() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _SavedScenesDialog(onLoadFile: () => _loadSceneFromFile(ctx)),
    );

    if (result == null || result.isEmpty) return;
    _applySceneJson(result);
  }

  Future<void> _loadSceneFromFile(BuildContext dialogContext) async {
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();

    try {
      final jsonStr = await file_io.pickJsonFile();
      if (jsonStr == null || jsonStr.isEmpty) return;
      _applySceneJson(jsonStr);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('잘못된 파일 형식: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('불러오기 실패: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    }
  }

  void _applySceneJson(String jsonStr, {bool silent = false}) {
    try {
      final scene = JsonIO.importScene(jsonStr);
      setState(() {
        _space = scene.space;
        _detector = CollisionDetector(_space);
        _refitCamera();
        _selectedPreset = _presetForSpace(scene.space);
        _boxes..clear()..addAll(scene.boxes);
        _resolveGravity();
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
        if (_boxes.isNotEmpty) {
          _hasEverAddedBox = true;
          _showOnboarding = false;
        }
      });
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${scene.boxes.length}개 박스를 불러왔습니다'),
              backgroundColor: const Color(0xFF6BD06B)),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('잘못된 파일 형식: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('불러오기 실패: $e'),
              backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    }
  }

  // ──── 스크린샷 ────

  Future<void> _takeScreenshot() async {
    final pixelRatio = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('스크린샷 해상도', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF333333),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 1.0), child: const Text('1x (표준)', style: TextStyle(color: Colors.white70))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 2.0), child: const Text('2x (고해상도)', style: TextStyle(color: Colors.white))),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 3.0), child: const Text('3x (최고해상도)', style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (pixelRatio == null) return;

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final rawImage = await boundary.toImage(pixelRatio: pixelRatio);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final imgW = rawImage.width.toDouble();
      final imgH = rawImage.height.toDouble();

      canvas.drawImage(rawImage, Offset.zero, Paint());

      const barHeight = 32.0;
      canvas.drawRect(Rect.fromLTWH(0, imgH - barHeight, imgW, barHeight), Paint()..color = const Color(0x66000000));

      final presetName = _selectedPreset == TrunkPreset.custom ? '커스텀' : _selectedPreset.label.split(' (').first;
      final totalBoxVol = _boxes.fold<double>(0.0, (sum, b) => sum + b.effectiveW * b.effectiveD * b.h);
      final lhVol = _space.leftWheelhouse.w * _space.leftWheelhouse.d * _space.leftWheelhouse.h;
      final rhVol = _space.rightWheelhouse.w * _space.rightWheelhouse.d * _space.rightWheelhouse.h;
      final totalSpaceVol = _space.w * _space.d * _space.h - lhVol - rhVol;
      final volPct = totalSpaceVol > 0 ? ((totalBoxVol / totalSpaceVol) * 100).round() : 0;

      final leftText = '$presetName | ${_boxes.length}개 | 점유율 $volPct%';
      const rightText = 'TrimBox';

      final textStyle = ui.TextStyle(color: const Color(0xCCFFFFFF), fontSize: 14 * pixelRatio);

      final leftParagraph = (ui.ParagraphBuilder(ui.ParagraphStyle())..pushStyle(textStyle)..addText(leftText)).build()
        ..layout(ui.ParagraphConstraints(width: imgW - 20));
      canvas.drawParagraph(leftParagraph, Offset(8 * pixelRatio, imgH - barHeight + (barHeight - leftParagraph.height) / 2));

      final rightParagraph = (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.right))..pushStyle(textStyle)..addText(rightText)).build()
        ..layout(ui.ParagraphConstraints(width: imgW - 20));
      canvas.drawParagraph(rightParagraph, Offset(imgW - rightParagraph.maxIntrinsicWidth - 8 * pixelRatio, imgH - barHeight + (barHeight - rightParagraph.height) / 2));

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(imgW.toInt(), imgH.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'trimbox-$timestamp.png';

      await file_io.shareOrDownloadImage(bytes, filename, 'image/png');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$filename 저장 완료'), backgroundColor: const Color(0xFF6BD06B)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('스크린샷 실패: $e'), backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
    }
  }

  // ──── 공유 카드 ────

  Future<void> _generateShareCard() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      const pixelRatio = 2.0;
      final rawImage = await boundary.toImage(pixelRatio: pixelRatio);
      final imgW = rawImage.width.toDouble();
      final imgH = rawImage.height.toDouble();

      // Share card layout: rendering on top, info panel at bottom
      const panelH = 180.0 * pixelRatio;
      final cardW = imgW;
      final cardH = imgH + panelH;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw trunk rendering
      canvas.drawImage(rawImage, Offset.zero, Paint());

      // Info panel background
      final panelRect = Rect.fromLTWH(0, imgH, cardW, panelH);
      canvas.drawRect(panelRect, Paint()..color = const Color(0xFF1C1C1C));

      // Divider line
      canvas.drawLine(
        Offset(0, imgH),
        Offset(cardW, imgH),
        Paint()..color = const Color(0xFF4DA3FF)..strokeWidth = 3 * pixelRatio,
      );

      // Calculate stats
      final presetName = _selectedPreset == TrunkPreset.custom
          ? '커스텀'
          : _selectedPreset.label.split(' (').first;
      final volPct = _utilizationPercent().round();
      final totalLiters = (_totalTrunkVolume() * 1000).round();
      final usedLiters = (_usedVolume() * 1000).round();
      final remainLiters = totalLiters - usedLiters;

      final r = pixelRatio;

      // Vehicle name + box count (title row)
      _drawShareText(canvas, '$presetName 트렁크', Offset(20 * r, imgH + 16 * r),
          fontSize: 22 * r, color: Colors.white, bold: true);
      _drawShareText(canvas, '${_boxes.length}개 장비 적재', Offset(20 * r, imgH + 48 * r),
          fontSize: 14 * r, color: Colors.white70);

      // Utilization bar
      final barX = 20 * r;
      final barY = imgH + 78 * r;
      final barW = cardW - 40 * r;
      const barH = 12.0;
      final barHScaled = barH * r;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(barX, barY, barW, barHScaled), Radius.circular(barHScaled / 2)),
        Paint()..color = const Color(0xFF444444),
      );
      final filledW = barW * (volPct / 100).clamp(0.0, 1.0);
      final barColor = volPct < 70
          ? const Color(0xFF4CAF50)
          : volPct < 90
              ? const Color(0xFFFFC107)
              : const Color(0xFFFF5252);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(barX, barY, filledW, barHScaled), Radius.circular(barHScaled / 2)),
        Paint()..color = barColor,
      );

      // Stats row
      _drawShareText(canvas, '적재율 $volPct%',
          Offset(20 * r, barY + barHScaled + 10 * r),
          fontSize: 16 * r, color: barColor, bold: true);
      _drawShareText(canvas, '사용 ${usedLiters}L / 총 ${totalLiters}L | 남은 공간 ${remainLiters}L',
          Offset(20 * r, barY + barHScaled + 34 * r),
          fontSize: 12 * r, color: Colors.grey);

      // Box list (compact, max 6)
      final boxLines = <String>[];
      for (int i = 0; i < _boxes.length && i < 6; i++) {
        final b = _boxes[i];
        final name = b.label.isNotEmpty ? b.label : b.id;
        final dims = '${(b.w * 100).round()}x${(b.d * 100).round()}x${(b.h * 100).round()}cm';
        boxLines.add('$name ($dims)');
      }
      if (_boxes.length > 6) boxLines.add('...외 ${_boxes.length - 6}개');
      final boxListStr = boxLines.join(' | ');
      _drawShareText(canvas, boxListStr,
          Offset(20 * r, barY + barHScaled + 58 * r),
          fontSize: 10 * r, color: const Color(0xFF888888), maxWidth: cardW - 40 * r);

      // TrimBox branding
      _drawShareText(canvas, 'TrimBox',
          Offset(cardW - 90 * r, imgH + 16 * r),
          fontSize: 18 * r, color: const Color(0xFF4DA3FF), bold: true);

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(cardW.toInt(), cardH.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final filename = 'trimbox-share-$timestamp.png';

      await file_io.shareOrDownloadImage(bytes, filename, 'image/png');

      // Also copy text summary to clipboard
      final textSummary = _buildShareText();
      await Clipboard.setData(ClipboardData(text: textSummary));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('공유 카드 저장 완료! (텍스트도 클립보드에 복사됨)'),
            backgroundColor: Color(0xFF6BD06B),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유 카드 생성 실패: $e'),
            backgroundColor: const Color(0xFFFF4D4D),
          ),
        );
      }
    }
  }

  void _drawShareText(Canvas canvas, String text, Offset pos, {
    required double fontSize,
    Color color = Colors.white,
    bool bold = false,
    double? maxWidth,
  }) {
    final style = ui.TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    final para = (ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, ellipsis: '...'))
          ..pushStyle(style)
          ..addText(text))
        .build()
      ..layout(ui.ParagraphConstraints(width: maxWidth ?? 1000));
    canvas.drawParagraph(para, pos);
  }

  String _buildShareText() {
    final presetName = _selectedPreset == TrunkPreset.custom
        ? '커스텀'
        : _selectedPreset.label.split(' (').first;
    final volPct = _utilizationPercent().round();
    final totalLiters = (_totalTrunkVolume() * 1000).round();
    final usedLiters = (_usedVolume() * 1000).round();

    final sb = StringBuffer();
    sb.writeln('$presetName 트렁크 적재 시뮬레이션');
    sb.writeln('적재율: $volPct% (${usedLiters}L / ${totalLiters}L)');
    sb.writeln('장비 ${_boxes.length}개:');
    for (final b in _boxes) {
      final name = b.label.isNotEmpty ? b.label : b.id;
      sb.writeln('  - $name (${(b.w * 100).round()}x${(b.d * 100).round()}x${(b.h * 100).round()}cm)');
    }
    sb.writeln('#TrimBox #캠핑 #트렁크패킹');
    return sb.toString();
  }

  // ──── 자동 배치 ────

  Future<void> _showAutoLayoutDialog() async {
    if (_boxes.isEmpty) return;

    // 계산 시간 측정
    final sw = Stopwatch()..start();
    final alternatives = AutoLayoutEngine.generateAlternatives(_space, _boxes, restarts: 24);
    sw.stop();
    final computeMs = sw.elapsedMilliseconds;

    if (!mounted) return;

    final selected = await showDialog<AutoLayoutResult>(
      context: context,
      builder: (ctx) => _AutoLayoutDialog(
        alternatives: alternatives,
        computeTimeMs: computeMs,
        trunkVolumeLiters: (_totalTrunkVolume() * 1000).round(),
      ),
    );

    if (selected != null) {
      _applyAutoLayout(selected);
    }
  }

  /// Quick fit check — just validates without applying layout
  void _showQuickFitCheck() {
    if (_boxes.isEmpty) return;

    final sw = Stopwatch()..start();
    final result = AutoLayoutEngine.computeLayout(_space, _boxes, restarts: 24);
    sw.stop();

    if (!mounted) return;
    _showVerdictDialog(result, computeTimeMs: sw.elapsedMilliseconds);
  }

  void _applyAutoLayout(AutoLayoutResult result) {
    _pushUndo();
    setState(() {
      for (final placement in result.placements) {
        final box = _boxes.firstWhere((b) => b.id == placement.box.id);
        placement.applyTo(box);
      }

      _parkUnfitBoxes(result);
      _manualEdited = false;

      _selectedBoxId = null;
      _updateCollisions();
    });

    if (mounted) {
      _showVerdictDialog(result);
      _showVerdictSnackBar(result);
    }
  }

  /// "라벨 — 사유" (사유가 있을 때)
  String _labelWithReason(AutoLayoutResult result, TrimBox b) {
    final label = b.label.isNotEmpty ? b.label : b.id;
    final reason = result.unfitReasons[b.id];
    return reason == null ? label : '$label — $reason';
  }

  void _showVerdictSnackBar(AutoLayoutResult result) {
    final pct = result.utilizationPercent.round();
    final placed = result.placements.length;
    final total = placed + result.unfitBoxes.length;
    final msg = result.allBoxesFit
        ? '${result.strategy.label}: $total개 배치 완료 (적재율 $pct%)'
        : '${result.strategy.label}: $placed/$total개 배치 (적재율 $pct%)';

    String snackMsg = msg;
    if (result.unfitBoxes.isNotEmpty) {
      final unfitLabels = result.unfitBoxes
          .map((b) => _labelWithReason(result, b))
          .join(', ');
      snackMsg = '$msg\n적재 불가: $unfitLabels';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMsg),
        backgroundColor:
            result.allBoxesFit ? const Color(0xFF6BD06B) : const Color(0xFFFFAA33),
        duration: const Duration(seconds: 5),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  void _showVerdictDialog(AutoLayoutResult result, {int? computeTimeMs}) {
    final pct = result.utilizationPercent.round();
    final placed = result.placements.length;
    final total = placed + result.unfitBoxes.length;

    // 남은 공간 계산
    final totalSpaceVol = _totalTrunkVolume();
    final totalBoxVol = result.placements.fold<double>(
        0.0, (sum, p) => sum + p.box.w * p.box.d * p.box.h);
    final remainingLiters = ((totalSpaceVol - totalBoxVol) * 1000).round();
    final capacityLiters = (totalSpaceVol * 1000).round();

    showDialog(
      context: context,
      builder: (ctx) {
        // Shared utilization bar widget
        Widget utilizationVisual() {
          final ratio = (pct / 100).clamp(0.0, 1.0);
          final barColor = pct < 70
              ? const Color(0xFF4CAF50)
              : pct < 90
                  ? const Color(0xFFFFC107)
                  : const Color(0xFFFF5252);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '적재율',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: barColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: const Color(0xFF444444),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '사용: ${(totalBoxVol * 1000).round()}L',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  Text(
                    '남은 공간: ${remainingLiters}L / ${capacityLiters}L',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          );
        }

        Widget computeTimeBadge() {
          if (computeTimeMs == null) return const SizedBox.shrink();
          final timeStr = computeTimeMs < 1000
              ? '${computeTimeMs}ms'
              : '${(computeTimeMs / 1000).toStringAsFixed(1)}s';
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt, color: Colors.grey[600], size: 14),
                const SizedBox(width: 4),
                Text(
                  '$timeStr 만에 계산 완료',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          );
        }

        if (result.placements.isEmpty && result.unfitBoxes.isNotEmpty) {
          // NO boxes fit
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF4D4D),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '적재 불가',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '선택한 장비가 트렁크에 맞지 않습니다.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                utilizationVisual(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1E1E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '장비 크기를 확인하거나\n더 큰 차량을 선택하세요.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                computeTimeBadge(),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          );
        } else if (result.allBoxesFit) {
          // ALL boxes fit
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6BD06B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '모두 적재 가능!',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                utilizationVisual(),
                const SizedBox(height: 12),
                _verdictInfoRow('적재 장비', '$total개 모두 트렁크에 들어갑니다'),
                if (result.placements.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _verdictLoadOrderSummary(result),
                ],
                computeTimeBadge(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인', style: TextStyle(color: Colors.grey)),
              ),
              if (_maxLoadOrder > 1)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E676),
                    side: const BorderSide(color: Color(0xFF00E676)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _enterStepView();
                  },
                  child: const Text('순서 가이드'),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveScene();
                },
                child: const Text('배치 저장'),
              ),
            ],
          );
        } else {
          // SOME boxes don't fit
          final unfitLabels = result.unfitBoxes
              .map((b) => _labelWithReason(result, b))
              .toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: Row(
              children: [
                Container(
                  width: 14, height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFAA33),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$placed/$total개 적재 가능',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                utilizationVisual(),
                const SizedBox(height: 12),
                const Text(
                  '적재 불가 장비:',
                  style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                ),
                const SizedBox(height: 4),
                ...unfitLabels.map((name) => Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.close, color: Color(0xFFFF6B6B), size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                  color: Color(0xFFFF6B6B), fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2A1E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '더 작은 장비를 선택하거나\n시트를 접어보세요.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                computeTimeBadge(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAutoLayoutDialog();
                },
                child: const Text('다시 배치'),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _verdictLoadOrderSummary(AutoLayoutResult result) {
    final sorted = List<BoxPlacement>.from(result.placements)
      ..sort((a, b) => a.loadOrder.compareTo(b.loadOrder));
    final displayCount = sorted.length > 5 ? 5 : sorted.length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '적재 순서 (안쪽부터)',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...List.generate(displayCount, (i) {
            final p = sorted[i];
            final name = p.box.label.isNotEmpty ? p.box.label : p.box.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Container(
                    width: 20, height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4DA3FF).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${p.loadOrder}',
                      style: const TextStyle(color: Color(0xFF4DA3FF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (sorted.length > 5)
            Text(
              '...외 ${sorted.length - 5}개',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _verdictInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ──── Undo/Redo ────

  void _pushUndo() {
    _undoStack.add(_boxes.map((b) => b.copyWith()).toList());
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    _exitStepView();
    if (_undoStack.isEmpty) return;
    _redoStack.add(_boxes.map((b) => b.copyWith()).toList());
    final prev = _undoStack.removeLast();
    setState(() {
      _boxes..clear()..addAll(prev);
      _selectedBoxId = null;
      _updateCollisions();
    });
  }

  void _redo() {
    _exitStepView();
    if (_redoStack.isEmpty) return;
    _undoStack.add(_boxes.map((b) => b.copyWith()).toList());
    final next = _redoStack.removeLast();
    setState(() {
      _boxes..clear()..addAll(next);
      _selectedBoxId = null;
      _updateCollisions();
    });
  }

  // ──── 스태킹 (규칙은 SupportRule 하나) ────

  void _resolveStackingY(TrimBox box) {
    box.y = SupportRule.nearestLevel(box, _boxes, _space);
  }

  void _resolveGravity() {
    SupportRule.settle(_boxes, _space);
  }

  // ──── 충돌 업데이트 ────

  void _updateCollisions() {
    _collidingIds = _detector.findAllCollisions(_boxes);
    _scheduleAutosave();
  }
}

// ──── 자동 배치 대안 선택 다이얼로그 ────

class _AutoLayoutDialog extends StatefulWidget {
  final List<AutoLayoutResult> alternatives;
  final int computeTimeMs;
  final int trunkVolumeLiters;

  const _AutoLayoutDialog({
    required this.alternatives,
    required this.computeTimeMs,
    required this.trunkVolumeLiters,
  });

  @override
  State<_AutoLayoutDialog> createState() => _AutoLayoutDialogState();
}

class _AutoLayoutDialogState extends State<_AutoLayoutDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Find the best strategy (highest utilization with all fit, or most placed)
    int bestIdx = 0;
    for (int i = 1; i < widget.alternatives.length; i++) {
      final curr = widget.alternatives[i];
      final best = widget.alternatives[bestIdx];
      if (curr.allBoxesFit && !best.allBoxesFit) {
        bestIdx = i;
      } else if (curr.allBoxesFit == best.allBoxesFit) {
        if (curr.placements.length > best.placements.length ||
            (curr.placements.length == best.placements.length &&
                curr.utilizationPercent > best.utilizationPercent)) {
          bestIdx = i;
        }
      }
    }

    final timeStr = widget.computeTimeMs < 1000
        ? '${widget.computeTimeMs}ms'
        : '${(widget.computeTimeMs / 1000).toStringAsFixed(1)}s';

    // Max utilization for bar scaling
    double maxPct = 1;
    for (final a in widget.alternatives) {
      if (a.utilizationPercent > maxPct) maxPct = a.utilizationPercent;
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: Color(0xFF4DA3FF), size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '자동 배치',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Color(0xFF6BD06B), size: 14),
                const SizedBox(width: 3),
                Text(
                  timeStr,
                  style: const TextStyle(color: Color(0xFF6BD06B), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: math.min(400.0, MediaQuery.sizeOf(context).width - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '배치 전략을 선택하세요:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.alternatives.length, (i) {
              final result = widget.alternatives[i];
              final isSelected = i == _selectedIndex;
              final isBest = i == bestIdx;
              final pct = result.utilizationPercent.round();
              final placed = result.placements.length;
              final total = placed + result.unfitBoxes.length;
              final barRatio = maxPct > 0
                  ? (result.utilizationPercent / maxPct).clamp(0.0, 1.0)
                  : 0.0;

              final statusColor = result.allBoxesFit
                  ? const Color(0xFF6BD06B)
                  : const Color(0xFFFFAA33);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedIndex = i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF333355)
                          : const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4DA3FF)
                            : const Color(0xFF444444),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isSelected
                                  ? const Color(0xFF4DA3FF)
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    result.strategy.label,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (isBest) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4DA3FF)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '추천',
                                        style: TextStyle(
                                          color: Color(0xFF4DA3FF),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              result.allBoxesFit
                                  ? '$total개 모두'
                                  : '$placed/$total개',
                              style: TextStyle(color: statusColor, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$pct%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Utilization bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: barRatio,
                            backgroundColor: const Color(0xFF444444),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              result.allBoxesFit
                                  ? const Color(0xFF4DA3FF)
                                  : const Color(0xFFFFAA33),
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (widget.alternatives.isNotEmpty &&
                widget.alternatives[_selectedIndex].unfitBoxes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A2A1A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFFAA33), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '배치 불가: ${widget.alternatives[_selectedIndex].unfitBoxes.map((b) => b.label.isNotEmpty ? b.label : b.id).join(", ")}',
                        style: const TextStyle(
                            color: Color(0xFFFFAA33), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4DA3FF),
            foregroundColor: Colors.white,
          ),
          onPressed: () =>
              Navigator.pop(context, widget.alternatives[_selectedIndex]),
          child: const Text('이 배치 적용'),
        ),
      ],
    );
  }
}

// ──── 저장된 배치 목록 다이얼로그 ────

class _SavedScenesDialog extends StatefulWidget {
  final VoidCallback onLoadFile;

  const _SavedScenesDialog({required this.onLoadFile});

  @override
  State<_SavedScenesDialog> createState() => _SavedScenesDialogState();
}

class _SavedScenesDialogState extends State<_SavedScenesDialog> {
  List<storage.SavedSceneMeta> _scenes = [];

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  Future<void> _refreshList() async {
    List<storage.SavedSceneMeta> list;
    try {
      list = await storage.listSavedScenes();
    } catch (_) {
      list = [];
    }
    if (mounted) setState(() => _scenes = list);
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF333333),
      title: const Text(
        '저장된 배치 불러오기',
        style: TextStyle(color: Colors.white, fontSize: 18),
      ),
      content: SizedBox(
        width: math.min(400.0, MediaQuery.sizeOf(context).width - 48),
        height: 360,
        child: _scenes.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined,
                        color: Colors.grey[700], size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      '저장된 배치가 없습니다',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _scenes.length,
                itemBuilder: (ctx, i) {
                  final scene = _scenes[i];
                  return Card(
                    color: const Color(0xFF2E2E2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      onTap: () async {
                        final jsonStr =
                            await storage.loadSceneFromStorage(scene.key);
                        if (!context.mounted) return;
                        if (jsonStr != null) {
                          Navigator.pop(context, jsonStr);
                        }
                      },
                      title: Text(
                        scene.name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(
                        '${scene.vehicle} | ${scene.boxCount}개 | '
                        '${_formatDate(scene.date)}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFFF6B6B), size: 20),
                        tooltip: '삭제',
                        onPressed: () => _confirmDelete(scene),
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: widget.onLoadFile,
          child: const Text(
            '파일에서 불러오기',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(storage.SavedSceneMeta scene) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text('배치 삭제', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${scene.name}"을(를) 삭제하시겠습니까?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4D4D),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await storage.deleteSceneFromStorage(scene.key);
      await _refreshList();
    }
  }
}
