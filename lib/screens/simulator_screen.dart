import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/auto_layout.dart';
import '../models/packing_advisor.dart';
import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../models/scene.dart';
import '../models/support.dart';
import '../render3d/camera.dart';
import '../render3d/picking.dart';
import '../render3d/trunk_painter_3d.dart';
import '../render3d/vec3.dart';
import '../utils/collision.dart';
import '../utils/file_io.dart' as file_io;
import '../utils/json_io.dart';
import '../utils/load_stats.dart';
import '../utils/scene_migration.dart';
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

/// 화면 모드 — 패널 배치, 라벨·캡션 정책, 결과를 다이얼로그로 낼지 아래 시트로 낼지의 단일 기준.
/// (`backlog/phone-ux-w9.md` 2절)
enum _LayoutMode {
  /// 본문 폭 > 900: 옆 320px 고정 패널
  desktop,

  /// 600 ≤ 폭 ≤ 900: 옆 280px 고정 패널
  tablet,

  /// 가로가 더 길고 높이 < 500 (폰 가로): 옆 300px 압축 패널
  phoneLandscape,

  /// 폭 < 600 (폰 세로): 아래 시트
  phone;

  static _LayoutMode of(double bodyWidth, Size screen) {
    if (screen.width > screen.height && screen.height < 500) {
      return _LayoutMode.phoneLandscape;
    }
    if (bodyWidth > 900) return _LayoutMode.desktop;
    if (bodyWidth >= 600) return _LayoutMode.tablet;
    return _LayoutMode.phone;
  }

  /// 폰(세로·가로): 압축 라벨·한 줄 캡션·선택 도구 띠·전체 화면 장비 선택·결과는 아래 시트
  bool get isPhoneLike =>
      this == _LayoutMode.phone || this == _LayoutMode.phoneLandscape;
}

class _SimulatorScreenState extends State<SimulatorScreen>
    with WidgetsBindingObserver {
  late TrunkSpace _space;
  final List<TrimBox> _boxes = [];
  String? _selectedBoxId;
  Set<String> _collidingIds = {};
  Set<String> _tailgateBlockedIds = {};
  int _boxCounter = 0;
  TrunkPreset _selectedPreset = TrunkPreset.sorento;

  /// 자동배치 무작위 재시도 예산. 웹(JS)은 VM 보다 1.5~2배 느리므로 24회가
  /// 기기와 무관하게 다 돌도록 넉넉히 준다 (결과가 기기 속도에 따라 흔들리지 않게).
  static const Duration _packBudget = Duration(milliseconds: 2500);

  /// 재시도 횟수: 16개(번들)까지는 24 로 판정을 고정하고, 그 위는 줄여 32개도 UI 가 몇 초씩
  /// 멈추지 않게 한다 (패커는 UI 스레드에서 동기 실행 — isolate 이관은 backlog 참고).
  static int _restartsFor(int n) => n <= 16 ? 24 : (n <= 24 ? 12 : 6);

  /// 쏘렌토 2열 슬라이드 (0 = 최후방, 최대 0.27)
  double _seatSlide = 0.0;

  static const List<(double, String)> _seatSlideOptions = [
    (0.0, '2열 최후방'),
    (0.13, '2열 중간 (+13cm)'),
    (sorentoSeatSlideMax, '2열 최전방 (+27cm)'),
  ];

  bool get _hasSeatSlide =>
      _selectedPreset == TrunkPreset.sorento ||
      _selectedPreset == TrunkPreset.sorento7;

  // 온보딩. 저장소에서 "본 적 없음" 을 확인한 뒤에만 켠다 — true 로 시작하면 재방문자도
  // 첫 프레임에 온보딩이 한 번 깜빡인다.
  bool _showOnboarding = false;
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

  /// 현재 화면 모드 (build 에서 갱신). 이후에 뜨는 다이얼로그·시트가 이것을 본다.
  _LayoutMode _layout = _LayoutMode.desktop;

  /// 폰 세로 시트: 현재 높이 비율. 캔버스는 시트가 덮지 않는 부분만 쓴다 (따라 줄어든다).
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();
  double _sheetFraction = 0;
  static const double _sheetMin = 0.12;
  static const double _sheetMax = 0.85;

  /// 짐이 있을 때의 시트 높이: 히어로·도구 줄·상태·목록 2~3행이 보이고, 남는 캔버스(약 430px)에
  /// 트렁크가 꽉 찬다 (초기 28% 에서는 트렁크 위아래가 100px 씩 비어 보인다)
  static const double _sheetLoaded = 0.45;

  /// 스냅 크기 목록은 같은 인스턴스를 유지한다 — DraggableScrollableSheet 는 목록의
  /// 동일성(==)만 보고 바뀌었다고 판단해 매 프레임 다시 스냅하므로, 빌드마다 새 목록을
  /// 주면 시트를 초기 높이 너머로 끌 수 없다.
  List<double> _snapSizes = const [];

  /// 시트가 만들어질 때의 시작 높이 (붙어 있는 동안은 바꾸지 않는다)
  double _sheetStart = 0.28;

  // Step-by-step loading guide
  bool _stepViewActive = false;
  int _stepViewCurrentStep = 1; // 1-based load order

  Size _lastCanvasSize = Size.zero;

  late CollisionDetector _detector;
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'trunk-canvas');
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _space = TrunkPreset.sorento.toTrunkSpace()!;
    _detector = CollisionDetector(_space);
    // 웹에서 한글 폴백 폰트가 늦게 로드되면 캔버스 라벨이 □ 로 남는다.
    // 폰트 변경 알림을 받으면 다시 그린다.
    PaintingBinding.instance.systemFonts.addListener(_onSystemFontsChanged);
    WidgetsBinding.instance.addObserver(this);
    _sheetCtrl.addListener(_onSheetMoved);
    _restoreSession();
  }

  /// 빈 트렁크에 짐이 처음 들어오면 시트를 "짐 있음" 높이로 올린다 — 판정 버튼·목록이 보이고
  /// 캔버스는 트렁크가 꽉 차는 크기로 줄어든다. 이미 그보다 높으면 그대로.
  void _raiseSheetForContent() {
    if (!_sheetCtrl.isAttached || _boxes.isEmpty) return;
    if (_sheetCtrl.size >= _sheetLoaded - 0.01) return;
    _sheetCtrl.animateTo(_sheetLoaded,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  /// 시트가 움직이면 캔버스 높이를 맞춘다 (카메라는 _ensureCamera 가 크기 변화에 다시 맞춘다)
  void _onSheetMoved() {
    if (!_sheetCtrl.isAttached) return;
    final f = _sheetCtrl.size;
    if ((f - _sheetFraction).abs() < 0.002) return;
    setState(() => _sheetFraction = f);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 뒤로 가거나 탭이 닫히기 직전: 대기 중인 자동 저장을 바로 쓴다
    if (state != AppLifecycleState.resumed) _flushAutosave();
  }

  void _onSystemFontsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _flushAutosave();
    _canvasFocusNode.dispose();
    _sheetCtrl.removeListener(_onSheetMoved);
    _sheetCtrl.dispose();
    _sceneCache.dispose();
    super.dispose();
  }

  /// 온보딩 표시 여부와 마지막 작업 상태 복원
  Future<void> _restoreSession() async {
    // 웹 localStorage 에 JSON 이 아닌 우리 값이 있으면 지우고 읽는다 (플러그인이 조용히
    // 건너뛰어 "자동 저장 없음" 으로 보이는 쓰레기 값이 남지 않게)
    await storage.ensureReadable();
    var seen = false;
    try {
      seen = await storage.hasSeenOnboarding();
    } catch (_) {
      // 저장소를 못 쓰는 환경에서는 처음 온 사용자로 본다
    }
    String? auto;
    try {
      auto = await storage.loadAutosave();
    } catch (_) {
      // 키 타입이 다른 등 읽을 수 없는 자동 저장은 버린다
      _dropAutosave();
    }
    if (!mounted) return;
    if (auto != null && _boxes.isEmpty) {
      // 조용한 복원: 실패해도 알리지 않고, 손상된 저장본은 지운다
      if (!_applySceneJson(auto, silent: true)) _dropAutosave();
    }
    if (!seen && _boxes.isEmpty && !_hasEverAddedBox) {
      setState(() => _showOnboarding = true);
    }
  }

  void _dropAutosave() {
    storage.clearAutosave().catchError((_) {});
  }

  /// 마지막 작업 상태를 잠시 뒤 저장 (연속 조작 중 과도한 저장 방지)
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer =
        Timer(const Duration(milliseconds: 800), _writeAutosave);
  }

  /// 대기 중인 자동 저장이 있으면 기다리지 않고 바로 쓴다 (종료·백그라운드 전환 시).
  void _flushAutosave() {
    if (_autosaveTimer?.isActive != true) return;
    _autosaveTimer!.cancel();
    _writeAutosave();
  }

  void _writeAutosave() {
    try {
      storage
          .saveAutosave(JsonIO.exportScene(Scene(space: _space, boxes: _boxes)))
          .catchError((_) {});
    } catch (_) {}
  }

  /// 2열 슬라이드 변경: 트렁크를 다시 만들고, 손으로 옮긴 적이 없으면 다시 배치
  void _onSeatSlideChanged(double slide) {
    final space = _selectedPreset.toTrunkSpace(seatSlide: slide);
    if (space == null) return;
    setState(() {
      _seatSlide = slide;
      _space = space;
      _detector = CollisionDetector(_space);
      _refitCamera();
      for (final box in _boxes) {
        box.clampTo(_space.w, _space.d);
      }
      _resolveGravity();
      _updateCollisions();
    });
    if (!_manualEdited && _boxes.isNotEmpty) _autoPackQuietly();
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
      keepOutside: _space,
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
    // 앱바(도움말 툴팁)도 모드를 보므로 본문 LayoutBuilder 보다 먼저 정한다. 이 화면은
    // 옆 내비게이션이 없어 본문 폭 = 화면 폭이다 (LayoutBuilder 가 같은 값으로 다시 확인).
    final screenNow = MediaQuery.sizeOf(context);
    _layout = _LayoutMode.of(screenNow.width, screenNow);
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      // 이 화면에는 입력란이 없다 (입력은 전부 다이얼로그 안). 키보드가 올라올 때 본문을
      // 줄이면 폰 가로에서 패널이 34px 로 눌려 넘치고, 캔버스도 쓸데없이 다시 맞춰진다.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: _buildAppBarTitle(context),
        backgroundColor: const Color(0xFF1C1C1C),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 22),
            // 폰에서는 키보드가 없다 → 터치 조작법
            tooltip: _layout.isPhoneLike ? '조작법' : '키보드 단축키 (?)',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final screen = MediaQuery.sizeOf(context);
          final mode = _LayoutMode.of(w, screen);
          _layout = mode;
          switch (mode) {
            case _LayoutMode.phoneLandscape:
              // 폰 가로처럼 낮고 넓은 화면: 시트 대신 옆 패널, 패널은 압축 배치
              // (일반 패널은 액션바·히어로 버튼·통계가 높이를 다 써서 목록이 0행이 된다)
              return SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(child: _buildCanvas()),
                    SizedBox(width: 300, child: _buildPanel(compact: true)),
                  ],
                ),
              );
            case _LayoutMode.desktop:
              return SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _buildCanvas()),
                    SizedBox(width: 320, child: _buildPanel()),
                  ],
                ),
              );
            case _LayoutMode.tablet:
              return SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _buildCanvas()),
                    SizedBox(width: 280, child: _buildPanel()),
                  ],
                ),
              );
            case _LayoutMode.phone:
              // 시트 초기 높이: 빈 상태 CTA 가 온전히 보이는 약 220px (+ 제스처 바 인셋).
              // 390×844 에서는 기존 28% 그대로, 작은 폰(360×640)에서는 비율을 키운다.
              final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
              final sheetInitial =
                  ((_sheetInitialPx + bottomInset) / constraints.maxHeight)
                      .clamp(0.28, 0.5)
                      .toDouble();
              // 시트가 아직 없으면(첫 빌드, 가로→세로 복귀) 시작 높이를 정한다:
              // 빈 트렁크는 초기 높이, 짐이 있으면 "짐 있음" 높이
              if (!_sheetCtrl.isAttached) {
                _sheetStart = _boxes.isNotEmpty && _sheetLoaded > sheetInitial
                    ? _sheetLoaded
                    : sheetInitial;
                _sheetFraction = _sheetStart;
              }
              final wanted = [
                sheetInitial,
                if (_sheetLoaded > sheetInitial + 0.02) _sheetLoaded,
              ];
              if (_snapSizes.length != wanted.length ||
                  _snapSizes.first != wanted.first) {
                _snapSizes = wanted;
              }
              final sheetPx = constraints.maxHeight *
                  _sheetFraction.clamp(_sheetMin, _sheetMax);
              // 좌우 인셋은 SafeArea 가, 아래 인셋은 시트가 안쪽 여백으로 처리한다
              return SafeArea(
                top: false,
                bottom: false,
                child: Stack(
                  children: [
                    // 시트가 덮지 않는 높이만 캔버스에 준다 → 시트를 올려도 트렁크가 가려지지 않고 줄어든다
                    Positioned.fill(
                      bottom: sheetPx,
                      child: _buildCanvas(),
                    ),
                    DraggableScrollableSheet(
                      controller: _sheetCtrl,
                      initialChildSize: _sheetStart,
                      minChildSize: _sheetMin,
                      maxChildSize: _sheetMax,
                      snap: true,
                      snapSizes: _snapSizes,
                      builder: (ctx, scrollCtrl) =>
                          _buildDraggablePanel(scrollCtrl),
                    ),
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  /// 폰 시트의 초기 높이 목표 (손잡이 + 빈 상태 안내 + CTA)
  static const double _sheetInitialPx = 220;

  // ──── 앱바: 차종 · 2열 슬라이드 ────

  /// 차종 버튼 라벨. 넓은 화면은 프리셋 라벨 그대로 두되 2열을 당겼으면 바닥 깊이 숫자를
  /// 현재 값으로 바꾼다. 좁은 화면(폰)은 "(바닥 …)" 을 떼고 차종명만 — 치수는 메뉴에 있다.
  String _presetButtonLabel({required bool short}) {
    if (_selectedPreset == TrunkPreset.custom) {
      return '커스텀 (${(_space.w * 100).round()}×${(_space.d * 100).round()}cm)';
    }
    final label = _selectedPreset.label;
    if (short) return label.split(' (').first;
    if (_seatSlide.abs() < 1e-6) return label;
    return label.replaceFirst(
        RegExp(r'×\d+cm\)'), '×${(_space.d * 100).round()}cm)');
  }

  String _seatSlideLabel({required bool short}) {
    final option = _seatSlideOptions
        .where((o) => (o.$1 - _seatSlide).abs() < 1e-6)
        .firstOrNull;
    final cm = (_seatSlide * 100).round();
    if (short) return cm == 0 ? '2열 최후방' : '2열 +${cm}cm';
    return option?.$2 ?? '2열 +${cm}cm';
  }

  /// 폭 600 미만(폰)에서는 제목을 빼고 짧은 라벨을 써서 360dp 에도 두 컨트롤이 들어가게
  /// 한다. 600 이상은 기존 배치 그대로 (웹 E2E 가 고정 좌표를 누른다).
  Widget _buildAppBarTitle(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final hPad = narrow ? 8.0 : 10.0;

    final presetMenu = PopupMenuButton<TrunkPreset>(
      initialValue: _selectedPreset,
      color: const Color(0xFF333333),
      tooltip: '차종 선택',
      // 기본 최대 폭(280)에서는 둘째 줄 설명이 잘린다
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 340),
      onSelected: _onPresetChanged,
      itemBuilder: (_) => _buildVehicleMenuItems(),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _presetButtonLabel(short: narrow),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );

    final seatMenu = PopupMenuButton<double>(
      initialValue: _seatSlide,
      color: const Color(0xFF333333),
      tooltip: '2열 시트 슬라이드',
      onSelected: _onSeatSlideChanged,
      itemBuilder: (_) => [
        for (final o in _seatSlideOptions)
          PopupMenuItem<double>(
            value: o.$1,
            child: Text(o.$2,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF555555)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.airline_seat_recline_normal,
                color: Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(
              _seatSlideLabel(short: narrow),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );

    return Row(
      children: [
        if (!narrow) ...[
          const Text('TrimBox'),
          const SizedBox(width: 16),
        ],
        // 좁은 화면: 차종 버튼이 남는 폭만 쓰고 넘치면 말줄임
        if (narrow) Flexible(child: presetMenu) else presetMenu,
        if (_hasSeatSlide) ...[
          const SizedBox(width: 8),
          seatMenu,
        ],
      ],
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final camera = _ensureCamera(canvasSize);
        // 선택한 짐이 캔버스 아래쪽에 있으면 도구 띠를 위에 둔다 (짐을 덮지 않게)
        final toolbarAtTop = _selectionToolbarAtTop(camera, canvasSize);

        return Stack(
          children: [
            Listener(
              onPointerSignal: _onPointerSignal,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              // Focus 로 받아 처리한 키는 소비한다. KeyboardListener 는 소비하지 못해
              // Android·데스크톱에서 화살표가 포커스 이동으로 새어 나갔다.
              child: Focus(
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
                        tailgateBlockedIds: _tailgateBlockedIds,
                        draggingBoxId: _isDragging ? _selectedBoxId : null,
                        highlightLoadOrder: _stepViewActive ? _stepViewCurrentStep : null,
                        cache: _sceneCache,
                        // 폰: 라벨은 선택·문제·큰 짐 몇 개만, 캡션은 한 줄
                        labelPolicy: _layout.isPhoneLike
                            ? LabelPolicy.compact
                            : LabelPolicy.all,
                        captionStyle: _layout.isPhoneLike
                            ? CaptionStyle.compact
                            : CaptionStyle.full,
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
            // Utilization info overlay (top-right) — 폰은 한 줄 칩. 시트를 끝까지 올려
            // 캔버스가 아주 낮으면(200px 미만) 트렁크를 가리므로 뺀다 (같은 숫자가 시트에 있다)
            if (_boxes.isNotEmpty &&
                (!_layout.isPhoneLike || canvasSize.height >= 200))
              Positioned(
                top: _layout.isPhoneLike ? 8 : 12,
                right: _layout.isPhoneLike ? 8 : 12,
                child: _layout.isPhoneLike
                    ? _buildUtilizationChip()
                    : _buildUtilizationOverlay(),
              ),
            // 폰: 선택한 짐의 도구 띠 (회전·삭제·선택 해제). 목록을 스크롤해 찾지 않아도 된다.
            if (_layout.isPhoneLike &&
                canvasSize.height >= 200 &&
                _selectedBoxId != null &&
                !_isDragging &&
                !_stepViewActive &&
                _boxes.any((b) => b.id == _selectedBoxId))
              Positioned(
                left: 8,
                right: 8,
                top: toolbarAtTop ? (_boxes.isNotEmpty ? 48 : 8) : null,
                bottom: toolbarAtTop ? null : _selectionToolbarBottom,
                child: _buildSelectionToolbar(),
              ),
            // Step view controls
            // 왼쪽 아래는 캔버스 캡션·테일게이트 상태 표시 자리라서 위쪽에 둔다.
            // 넓으면 왼쪽 위(오른쪽 위 적재율 카드와 나란히), 좁으면 카드 아래 가운데.
            if (_stepViewActive)
              if (canvasSize.width >= _stepControlWidth + 180)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _buildStepViewControls(),
                )
              else
                Positioned(
                  top: 96,
                  left: 8,
                  right: 8,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildStepViewControls(),
                    ),
                  ),
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

  /// 통계는 LoadStats 하나로 (패널과 같은 기준: 트렁크 밖에 세워 둔 짐 제외)
  LoadStats get _stats => LoadStats.of(_boxes, _space);

  double _totalTrunkVolume() => _space.usableVolume;

  double _utilizationPercent() => _stats.volumePercent;

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
    final stats = _stats;
    final pct = stats.volumePercent;
    final color = _utilizationColor(pct);
    final remainingLiters = stats.remainingLiters;

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

  /// 폰용 한 줄 적재율 칩: `적재율 62% · 16개 · 남은 358L`
  Widget _buildUtilizationChip() {
    final stats = _stats;
    final pct = stats.volumePercent;
    final color = _utilizationColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC1C1C1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('적재율 ',
              style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          Text('${pct.round()}%',
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          Text(' · ${_boxes.length}개 · 남은 ${stats.remainingLiters}L',
              style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ],
      ),
    );
  }

  // ──── 폰: 선택 도구 띠 ────

  /// 캡션 한 줄(약 22px) + 상태 알약(약 28px) 위에 놓는다
  static const double _selectionToolbarBottom = 60;

  /// 선택한 짐이 도구 띠 자리(캔버스 아래 60~108px)까지 내려와 있으면 띠를 위쪽(칩 아래)에
  /// 놓는다 — 띠가 방금 선택한 짐을 덮지 않게. 기준은 짐의 앞쪽 아래 모서리(카메라 쪽).
  bool _selectionToolbarAtTop(OrbitCamera camera, Size canvasSize) {
    final box = _boxes.where((b) => b.id == _selectedBoxId).firstOrNull;
    if (box == null) return false;
    final p = camera
        .project(
            Vec3(box.x + box.effectiveW / 2, box.y, box.z + box.effectiveD),
            canvasSize)
        ?.screen;
    return p != null && p.dy > canvasSize.height - _selectionToolbarBottom - 52;
  }

  Widget _buildSelectionToolbar() {
    final box = _boxes.where((b) => b.id == _selectedBoxId).firstOrNull;
    if (box == null) return const SizedBox.shrink();
    final name = box.label.isNotEmpty ? box.label : box.id;
    final dims =
        '${(box.w * 100).round()}×${(box.d * 100).round()}×${(box.h * 100).round()}';

    Widget btn(IconData icon, String tooltip, VoidCallback onTap,
        {Color color = Colors.white}) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 22),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        color: const Color(0xEE1C1C1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4DA3FF), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: box.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text('$dims cm · R:${box.rotY}°',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
          btn(Icons.rotate_right, '선택한 짐 회전', () => _rotateBox(box.id)),
          btn(Icons.delete_outline, '선택한 짐 삭제', () => _deleteBox(box.id),
              color: const Color(0xFFFF6B6B)),
          btn(Icons.close, '선택 해제',
              () => setState(() => _selectedBoxId = null),
              color: Colors.white54),
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

  /// 스텝 뷰 컨트롤의 고정 폭: ✕(36) + 구분선(17) + ‹(40) + 라벨(160) + ›(40) + 여백·테두리(23)
  static const double _stepControlWidth = 316;

  /// 스텝 뷰 컨트롤. 라벨 폭을 고정해 단계가 바뀌어도 ‹ › ✕ 가 제자리에 있다
  /// (라벨 길이에 따라 버튼이 움직이면 같은 자리를 연달아 누르다 ✕ 를 누르게 된다).
  Widget _buildStepViewControls() {
    final maxStep = _maxLoadOrder;
    final currentBox = _boxes.where((b) => b.loadOrder == _stepViewCurrentStep).firstOrNull;
    final boxName = currentBox != null
        ? (currentBox.label.isNotEmpty ? currentBox.label : currentBox.id)
        : '';

    Widget navButton(IconData icon, String tooltip, VoidCallback? onPressed) {
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 28),
          disabledColor: const Color(0xFF555555),
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        ),
      );
    }

    return Container(
      width: _stepControlWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xEE1C1C1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E676), width: 1.5),
      ),
      child: Row(
        children: [
          // 닫기는 이전/다음과 떨어뜨려 구분선 너머에 둔다
          SizedBox(
            width: 36,
            height: 40,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              tooltip: '스텝뷰 닫기',
              onPressed: _exitStepView,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 40),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 28, color: const Color(0x5500E676)),
          const SizedBox(width: 8),
          navButton(
            Icons.chevron_left,
            '이전 단계',
            _stepViewCurrentStep > 1
                ? () => setState(() => _stepViewCurrentStep--)
                : null,
          ),
          SizedBox(
            width: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP $_stepViewCurrentStep / $maxStep',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  boxName.isEmpty ? ' ' : boxName,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          navButton(
            Icons.chevron_right,
            '다음 단계',
            _stepViewCurrentStep < maxStep
                ? () => setState(() => _stepViewCurrentStep++)
                : null,
          ),
        ],
      ),
    );
  }

  /// 터치로 쓰는 기기인가: 모바일 OS 이거나 (웹 포함) 화면 짧은 변이 600 미만.
  /// 실제로 터치 입력이 들어온 적이 있으면 그것도 따른다.
  bool _isTouchFormFactor(BuildContext context) {
    final platform = defaultTargetPlatform;
    return _lastPointerIsTouch ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS ||
        MediaQuery.sizeOf(context).shortestSide < 600;
  }

  Widget _buildOnboardingOverlay(Size canvasSize) {
    final screen = MediaQuery.sizeOf(context);
    final shortWide = screen.width > screen.height && screen.height < 500;
    // 패널이 아래(폰 세로의 시트)에 있는가, 오른쪽에 있는가
    final panelBelow = !shortWide && canvasSize.width < 600;
    final isTouch = _isTouchFormFactor(context);
    // 낮은 캔버스: 여백·아이콘을 줄이고, 폭이 되면(폰 가로) 두 단으로 눕혀
    // 카드 전체와 닫기 안내가 보이게 한다
    final dense = canvasSize.height < 450;
    final compact = dense && canvasSize.width >= 480;

    final controls = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('조작법', style: TextStyle(color: Color(0xFF4DA3FF), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (isTouch) ...[
            _controlRow('한 손가락 드래그', '회전'),
            _controlRow('두 손가락', '확대·이동'),
            _controlRow('짐을 탭', '도구 띠로 회전·삭제'),
            _controlRow('짐을 끌어서', '옮기기'),
            _controlRow('시트 도구 줄', '실행 취소 · 저장'),
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
    );
    final hint = Text('아무 곳이나 탭하여 닫기', style: TextStyle(color: Colors.grey[600], fontSize: 11));
    final arrow = Icon(panelBelow ? Icons.arrow_downward : Icons.arrow_forward, color: const Color(0xFF4DA3FF), size: 28);

    final Widget card = compact
        ? Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF4DA3FF), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Color(0xFF4DA3FF), size: 36),
                    const SizedBox(height: 8),
                    const Text(
                      '박스를 추가하여\n시뮬레이션을 시작하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    arrow,
                  ],
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [controls, const SizedBox(height: 8), hint],
                  ),
                ),
              ],
            ),
          )
        : Container(
              constraints: const BoxConstraints(maxWidth: 320),
              margin: EdgeInsets.all(dense ? 8 : 24),
              padding: EdgeInsets.all(dense ? 14 : 24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF4DA3FF), width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!dense) ...[
                    const Icon(Icons.inventory_2_outlined, color: Color(0xFF4DA3FF), size: 48),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    '박스를 추가하여\n시뮬레이션을 시작하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  arrow,
                  SizedBox(height: dense ? 8 : 16),
                  controls,
                  const SizedBox(height: 12),
                  hint,
                ],
              ),
            );

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() => _showOnboarding = false);
          storage.markOnboardingSeen();
        },
        child: Container(
          color: const Color(0x88000000),
          child: Center(
            // 그래도 캔버스가 카드보다 낮으면 넘치지 않고 스크롤된다
            child: SingleChildScrollView(child: card),
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


  Widget _buildPanel({bool compact = false}) {
    return BoxListPanel(
      compact: compact,
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
      // 이미지 저장은 파일 I/O 가 되는 플랫폼(1차 배포: 웹)에서만 보인다
      onScreenshot: file_io.fileActionsSupported ? _takeScreenshot : null,
      onAutoLayout: _boxes.isNotEmpty ? _showAutoLayoutDialog : null,
      onQuickCheck: _boxes.isNotEmpty ? _showQuickFitCheck : null,
      onStepView: _boxes.isNotEmpty ? _enterStepView : null,
      onShareCard: file_io.fileActionsSupported && _boxes.isNotEmpty
          ? _generateShareCard
          : null,
      onUndo: _undoStack.isNotEmpty ? _undo : null,
      onRedo: _redoStack.isNotEmpty ? _redo : null,
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
      // 이미지 저장은 파일 I/O 가 되는 플랫폼(1차 배포: 웹)에서만 보인다
      onScreenshot: file_io.fileActionsSupported ? _takeScreenshot : null,
      onAutoLayout: _boxes.isNotEmpty ? _showAutoLayoutDialog : null,
      onQuickCheck: _boxes.isNotEmpty ? _showQuickFitCheck : null,
      onStepView: _boxes.isNotEmpty ? _enterStepView : null,
      onShareCard: file_io.fileActionsSupported && _boxes.isNotEmpty
          ? _generateShareCard
          : null,
      onUndo: _undoStack.isNotEmpty ? _undo : null,
      onRedo: _redoStack.isNotEmpty ? _redo : null,
      scrollController: scrollCtrl,
      showDragHandle: true,
      bottomPadding: MediaQuery.viewPaddingOf(context).bottom,
    );
  }

  void _showHelp() {
    if (_layout.isPhoneLike) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF252525),
          title: const Text('조작법',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _controlRow('한 손가락 드래그', '회전'),
              _controlRow('두 손가락', '확대·이동'),
              _controlRow('짐을 탭', '선택 → 도구 띠로 회전·삭제'),
              _controlRow('짐을 끌어서', '옮기기 (다른 짐 위에 올리면 쌓임)'),
              if (_layout == _LayoutMode.phone) ...[
                _controlRow('시트 손잡이', '위로 끌면 목록 · 아래로 내리면 트렁크만'),
                _controlRow('실행 취소', '시트 도구 줄의 ↶'),
              ] else
                _controlRow('실행 취소', '오른쪽 패널 도구 줄의 ↶'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
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
        // 수동 이동은 자동배치 순서를 무효화 (처음 한 번은 알린다)
        _ordersClearedByDrag = _boxes.any((b) => b.loadOrder != null);
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
    _maybeNotifyOrdersCleared();
  }

  bool _ordersClearedByDrag = false;
  bool _orderNoticeShown = false;

  /// 손으로 옮겨 적재 순서(배지·순서 가이드)가 사라졌음을 세션에 한 번만 알린다
  void _maybeNotifyOrdersCleared() {
    if (!_ordersClearedByDrag) return;
    _ordersClearedByDrag = false;
    if (_orderNoticeShown || !mounted) return;
    _orderNoticeShown = true;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('손으로 옮겨 적재 순서를 지웠어요 · 자동 배치로 다시 만들 수 있어요'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: '자동 배치', onPressed: _showAutoLayoutDialog),
      ));
  }

  /// 캔버스 키 입력. 처리한 키는 [KeyEventResult.handled] 로 소비한다 — 그렇지 않으면
  /// Android·데스크톱의 기본 단축키(화살표 = 포커스 이동)가 캔버스에서 포커스를 빼앗는다.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    final isArrow = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    final isCameraTurn =
        key == LogicalKeyboardKey.keyQ || key == LogicalKeyboardKey.keyE;
    // 누르고 있을 때 반복되는 것은 이동(화살표)과 카메라 회전(Q/E)뿐
    if (isRepeat && !isArrow && !isCameraTurn) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      if (isShift) { _redo(); } else { _undo(); }
      return KeyEventResult.handled;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    if (isCtrl) return KeyEventResult.ignored; // 브라우저·시스템 단축키는 건드리지 않는다

    if (event.character == '?') {
      _showHelp();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetCamera();
      return KeyEventResult.handled;
    }
    if (isCameraTurn) {
      final cam = _camera;
      if (cam != null) {
        final dir = key == LogicalKeyboardKey.keyQ ? 1.0 : -1.0;
        setState(() => _setCamera(
            cam.copyWith(yaw: cam.yaw + dir * 10 * math.pi / 180)));
      }
      return KeyEventResult.handled;
    }

    final isRotate = key == LogicalKeyboardKey.keyR;
    final isDelete = key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace;
    // 박스를 다루는 키가 아니면 아무것도 바꾸지 않는다 (undo·"손으로 편집함" 표시 포함)
    if (!isArrow && !isRotate && !isDelete) return KeyEventResult.ignored;

    final boxIndex = _boxes.indexWhere((b) => b.id == _selectedBoxId);
    if (boxIndex == -1) return KeyEventResult.ignored; // 선택 없음 → 기본 동작에 맡긴다
    final box = _boxes[boxIndex];

    if (isDelete) {
      _deleteBox(box.id);
      return KeyEventResult.handled;
    }

    final before = _boxes.map((b) => b.copyWith()).toList();
    final unit = _space.gridUnit;
    final x0 = box.x, z0 = box.z, rot0 = box.rotY;
    if (key == LogicalKeyboardKey.arrowLeft) box.x -= unit;
    if (key == LogicalKeyboardKey.arrowRight) box.x += unit;
    if (key == LogicalKeyboardKey.arrowUp) box.z -= unit;
    if (key == LogicalKeyboardKey.arrowDown) box.z += unit;
    if (isRotate) box.rotate90();
    box.snapToGrid(_space.gridUnit);
    box.clampTo(_space.w, _space.d);

    final changed = (box.x - x0).abs() > 1e-9 ||
        (box.z - z0).abs() > 1e-9 ||
        box.rotY != rot0;
    if (!changed) {
      // 벽에 막힌 이동: 되돌릴 것이 없으니 undo 항목도, 편집 표시도 남기지 않는다
      box
        ..x = x0
        ..z = z0;
      return KeyEventResult.handled;
    }

    // 키를 누르고 있는 동안의 연속 이동은 undo 한 번으로 묶는다
    if (!isRepeat) _pushUndoSnapshot(before);
    setState(() {
      _manualEdited = true;
      _resolveGravity();
      _updateCollisions();
    });
    return KeyEventResult.handled;
  }

  // ──── 히트 테스트 (레이캐스트) ────

  /// 화면 좌표에서 카메라 반직선을 쏴 가장 가까운 박스를 고른다.
  TrimBox? _hitTest(Offset localPos) {
    final cam = _camera;
    if (cam == null || _lastCanvasSize == Size.zero) return null;
    final ray = cam.ray(localPos, _lastCanvasSize);
    // AABB 로 넉넉히 집되(터치), 여러 개가 걸리면 실제로 그려진 모양에 맞은 쪽을 고른다.
    // 스텝 뷰에서 숨겨진 박스는 제외.
    return pickBox(
      ray,
      _boxes.where((b) => !(_stepViewActive &&
          b.loadOrder != null &&
          b.loadOrder! > _stepViewCurrentStep)),
    );
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
      _compactLoadOrders();
      _updateCollisions();
    });
  }

  /// 짐이 빠진 뒤 적재 순서를 1..n 으로 다시 매기고 스텝 뷰를 맞춘다.
  /// (그대로 두면 스텝 뷰에 짐 없는 빈 단계나 "STEP 1 / 0" 이 남는다.)
  void _compactLoadOrders() {
    final ordered = _boxes.where((b) => b.loadOrder != null).toList()
      ..sort((a, b) => a.loadOrder!.compareTo(b.loadOrder!));
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].loadOrder = i + 1;
    }
    if (!_stepViewActive) return;
    if (ordered.isEmpty) {
      _stepViewActive = false;
    } else if (_stepViewCurrentStep > ordered.length) {
      _stepViewCurrentStep = ordered.length;
    }
  }

  Future<void> _showAddDialog() async {
    // 폰은 전체 화면 페이지 (키보드가 목록을 가리지 않고, 하단 "추가" 가 항상 보인다)
    final result =
        await showGearPicker(context, fullScreen: _layout.isPhoneLike);
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
          soft: item['soft'] == true,
          compressibility: (item['compress'] as num?)?.toDouble() ?? 0,
          weightKg: (item['weight'] as num?)?.toDouble() ?? 0,
          accessPriority: item['access'] == true,
          shape: gearShapeFromName(item['shape']),
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
    if (!_manualEdited) {
      _autoPackQuietly();
    } else if (_lastAddHadNoRoom && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('빈 자리가 없어 트렁크 밖에 두었습니다'),
          backgroundColor: const Color(0xFFFFAA33),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '자동 배치',
            textColor: Colors.black87,
            onPressed: _showAutoLayoutDialog,
          ),
        ));
    }
    _lastAddHadNoRoom = false;
    _raiseSheetForContent();
  }

  /// 모달 없이 자동 배치를 적용하고 스낵바로 판정만 알린다
  void _autoPackQuietly() {
    if (_boxes.isEmpty) return;
    final result = AutoLayoutEngine.computeLayout(_space, _boxes,
        restarts: _restartsFor(_boxes.length), budget: _packBudget);
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
    // 자리가 없다: 테일게이트를 막는 자리에 억지로 얹지 않고 트렁크 밖에 세워 둔다
    // (자동배치가 못 넣은 짐과 같은 자리·같은 뜻). 스낵바로 알린다.
    box.rotY = 0;
    var x = 0.0;
    for (final b in _boxes) {
      if (LoadStats.isParked(b, _space)) x = math.max(x, b.x + b.effectiveW + 0.05);
    }
    box.x = x;
    box.z = _space.d + 0.06;
    box.y = 0;
    box.loadOrder = null;
    _lastAddHadNoRoom = true;
  }

  /// 마지막 추가에서 트렁크 안에 자리를 못 찾은 짐이 있었는가 (스낵바용)
  bool _lastAddHadNoRoom = false;

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
      final (name, detail) = _presetMenuText(p);
      items.add(PopupMenuItem<TrunkPreset>(
        value: p,
        // 두 줄(약 34px)이어도 항목 높이는 기본 48px 그대로 — 메뉴 항목 위치가 바뀌지 않는다
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF999999), fontSize: 11)),
                ],
              ),
            ),
            if (vol != null) ...[
              const SizedBox(width: 12),
              Text('${vol}L', style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
            ],
          ],
        ),
      ));
    }
    return items;
  }

  /// 차종 메뉴 한 행의 (이름, 설명). 5인승과 7인승은 바닥 치수·부피가 같아서
  /// 숫자만으로는 구분이 안 된다 → 무엇이 다른지를 둘째 줄에 적는다.
  (String, String) _presetMenuText(TrunkPreset p) {
    final parts = p.label.split(' (');
    final name = parts.first;
    final dims = parts.length > 1 ? parts[1].replaceAll(')', '') : '';
    return switch (p) {
      TrunkPreset.sorento => (name, '$dims · 2열 뒤 적재 공간'),
      TrunkPreset.sorento7 => (name, '5인승과 같은 공간 · 바닥 아래 수납함만 다름'),
      TrunkPreset.custom => (name, '가로·세로·높이 직접 입력'),
      _ => (name, dims),
    };
  }

  Future<void> _onPresetChanged(TrunkPreset preset) async {
    TrunkSpace? newSpace;

    if (preset == TrunkPreset.custom) {
      newSpace = await showDialog<TrunkSpace>(context: context, builder: (_) => const TrunkSizeDialog());
      if (newSpace == null) return;
    } else {
      newSpace = preset.toTrunkSpace(seatSlide: _seatSlide);
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
    // 2열 슬라이드와 같은 규칙: 손으로 옮긴 적이 없으면 새 트렁크에 맞춰 다시 배치
    if (!_manualEdited && _boxes.isNotEmpty) _autoPackQuietly();
  }

  // ──── 저장/불러오기 ────

  String get _currentVehicleName {
    if (_selectedPreset == TrunkPreset.custom) return '커스텀';
    return _selectedPreset.label.split(' (').first;
  }

  Future<void> _saveScene() async {
    if (_boxes.isEmpty) {
      // "… 0개 적재" 를 저장하게 두지 않는다
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('저장할 짐이 없습니다. 먼저 장비를 추가하세요.'),
          duration: Duration(seconds: 3),
        ));
      return;
    }
    final defaultName = '$_currentVehicleName - ${_boxes.length}개 적재';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: defaultName);
        return AlertDialog(
          backgroundColor: const Color(0xFF333333),
          title: const Text('배치 저장', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
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
              // 폰에서는 버튼 세 개가 세로로 접히므로 내보내기는 입력란 아래 링크로
              if (file_io.fileActionsSupported && _layout.isPhoneLike)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _saveSceneToFile();
                    },
                    icon: const Icon(Icons.download, size: 16, color: Colors.white70),
                    label: const Text('파일로 내보내기',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            if (file_io.fileActionsSupported && !_layout.isPhoneLike)
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
      builder: (ctx) => _SavedScenesDialog(
          onLoadFile: file_io.fileActionsSupported
              ? () => _loadSceneFromFile(ctx)
              : null),
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

  /// 씬 JSON 을 화면에 적용한다. 성공하면 true.
  /// [silent]: 시작할 때의 자동 복원 — 성공·실패 모두 알리지 않는다.
  bool _applySceneJson(String jsonStr, {bool silent = false}) {
    try {
      final scene = JsonIO.importScene(jsonStr);
      // 구버전 저장본: 장비 DB 와 같은 짐에 무게·연질·모양을 채운다 (다시 배치하기 전에)
      backfillGearPhysics(scene, jsonStr);
      // 저장된 트렁크가 프리셋 차종이면 현재 프리셋 정의를 쓴다 (치수 갱신 반영).
      final preset = _presetForSpace(scene.space);
      final presetSpace =
          preset.toTrunkSpace(seatSlide: scene.space.seatSlide);
      final spaceChanged = presetSpace != null &&
          JsonIO.exportScene(Scene(space: presetSpace, boxes: const [])) !=
              JsonIO.exportScene(Scene(space: scene.space, boxes: const []));
      setState(() {
        _space = presetSpace ?? scene.space;
        _seatSlide = scene.space.seatSlide;
        _detector = CollisionDetector(_space);
        _refitCamera();
        _selectedPreset = preset;
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
      // 트렁크 치수가 바뀌었으면 저장된 자리는 무효일 수 있으니 다시 배치
      if (spaceChanged && _boxes.isNotEmpty) {
        _manualEdited = false;
        _autoPackQuietly();
      }
      _raiseSheetForContent();
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${scene.boxes.length}개 박스를 불러왔습니다'),
              backgroundColor: const Color(0xFF6BD06B)),
        );
      }
      return true;
    } catch (e) {
      if (mounted && !silent) {
        final msg = e is FormatException ? '잘못된 파일 형식: $e' : '불러오기 실패: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: const Color(0xFFFF4D4D)),
        );
      }
      return false;
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
      // 화면 오버레이·패널과 같은 수치
      final volPct = _utilizationPercent().round();

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
      final totalLiters = _stats.totalLiters;
      final usedLiters = _stats.usedLiters;
      final remainLiters = _stats.remainingLiters;

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
    final totalLiters = _stats.totalLiters;
    final usedLiters = _stats.usedLiters;

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
    final alternatives = AutoLayoutEngine.generateAlternatives(_space, _boxes,
        restarts: math.max(4, _restartsFor(_boxes.length) ~/ 2),
        budget: _packBudget);
    sw.stop();
    final computeMs = sw.elapsedMilliseconds;

    if (!mounted) return;

    // 같은 결과를 내는 전략은 카드에 "(= 균형 배치)" 로 표시한다 — 같은 걸 셋 중에 고르게 하지 않게
    final sameAs = <LayoutStrategy, String>{};
    for (var i = 0; i < alternatives.length; i++) {
      for (var j = 0; j < i; j++) {
        if (_sameLayout(alternatives[i], alternatives[j])) {
          sameAs[alternatives[i].strategy] = alternatives[j].strategy.label;
          break;
        }
      }
    }
    final dialog = _AutoLayoutDialog(
      alternatives: alternatives,
      computeTimeMs: computeMs,
      trunkVolumeLiters: (_totalTrunkVolume() * 1000).round(),
      sheet: _layout.isPhoneLike,
      sameAs: sameAs,
    );
    // 폰은 아래 시트 (카드·적용 버튼이 전체 폭), 그 외는 기존 다이얼로그
    final Future<AutoLayoutResult?> pending = _layout.isPhoneLike
        ? showModalBottomSheet<AutoLayoutResult>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: false,
            backgroundColor: const Color(0xFF2A2A2A),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (ctx) => dialog,
          )
        : showDialog<AutoLayoutResult>(
            context: context,
            builder: (ctx) => dialog,
          );
    final selected = await pending;

    if (selected != null) {
      _applyAutoLayout(selected);
    }
  }

  /// 두 배치가 같은가: 같은 짐이 같은 자리·같은 방향 (1mm 안)
  static bool _sameLayout(AutoLayoutResult a, AutoLayoutResult b) {
    if (a.placements.length != b.placements.length) return false;
    final byId = {for (final p in b.placements) p.box.id: p};
    for (final p in a.placements) {
      final q = byId[p.box.id];
      if (q == null) return false;
      const t = 0.001;
      if ((p.x - q.x).abs() > t ||
          (p.y - q.y).abs() > t ||
          (p.z - q.z).abs() > t ||
          (p.w - q.w).abs() > t ||
          (p.d - q.d).abs() > t ||
          (p.h - q.h).abs() > t) {
        return false;
      }
    }
    return true;
  }

  /// "들어갈까?" — 화면에 있는 **지금 배치**를 판정한다. 재배치 결과는 지금 배치에 문제가
  /// 있거나(겹침·테일게이트) 못 실은 짐이 있을 때 "다시 배치하면 …" 으로 함께 보여 주고
  /// 적용 버튼을 준다. (전에는 새로 짠 가상 배치의 판정만 보여 줘, 트렁크가 빨간데도
  /// "모두 적재 가능" 이라고 했다.)
  void _showQuickFitCheck() {
    if (_boxes.isEmpty) return;

    final sw = Stopwatch()..start();
    final result = AutoLayoutEngine.computeLayout(_space, _boxes,
        restarts: _restartsFor(_boxes.length), budget: _packBudget);
    sw.stop();
    if (!mounted) return;

    final problems = _currentLayoutProblems();
    final parked = _stats.parked;
    if (problems.isNotEmpty || (parked.isNotEmpty && result.allBoxesFit)) {
      _showCurrentProblemsVerdict(problems, result,
          computeTimeMs: sw.elapsedMilliseconds,
          slideSuggestion: result.allBoxesFit ? null : _suggestSeatSlide());
      return;
    }
    if (parked.isEmpty) {
      // 지금 배치가 그대로 유효 → 지금 배치 기준으로 판정 (적재율·순서도 화면의 것)
      _showVerdictDialog(
        _currentLayoutAsResult(),
        computeTimeMs: sw.elapsedMilliseconds,
        showLoadOrder: _boxes.any((b) => b.loadOrder != null),
      );
      return;
    }
    // 못 실은 짐이 있고 재배치로도 다 못 넣는다: 재배치 판정(일부/불가) + 2열 제안
    _showVerdictDialog(
      result,
      computeTimeMs: sw.elapsedMilliseconds,
      slideSuggestion: _suggestSeatSlide(),
    );
  }

  /// 지금 배치의 문제: 트렁크 안 짐 중 충돌·경계·테일게이트·개구부 위반 (사유 문장 포함).
  /// 트렁크 밖에 세워 둔(못 실은) 짐은 문제가 아니라 "못 실은 짐" 으로 따로 센다.
  List<(TrimBox, List<String>)> _currentLayoutProblems() {
    final out = <(TrimBox, List<String>)>[];
    for (final b in _boxes) {
      if (LoadStats.isParked(b, _space)) continue;
      final reasons = _detector.describe(b, _boxes);
      if (reasons.isNotEmpty) out.add((b, reasons));
    }
    return out;
  }

  /// 화면의 배치를 그대로 판정 결과 형태로 (전부 트렁크 안이고 문제가 없을 때만 부른다)
  AutoLayoutResult _currentLayoutAsResult() {
    final inside = List<TrimBox>.from(_stats.inside)
      ..sort((a, b) =>
          (a.loadOrder ?? 1 << 20).compareTo(b.loadOrder ?? 1 << 20));
    final placements = <BoxPlacement>[
      for (var i = 0; i < inside.length; i++)
        BoxPlacement(
          box: inside[i],
          x: inside[i].x,
          y: inside[i].y,
          z: inside[i].z,
          w: inside[i].effectiveW,
          d: inside[i].effectiveD,
          h: inside[i].effectiveH,
          loadOrder: inside[i].loadOrder ?? (i + 1),
          squash: inside[i].squash,
          squashW: inside[i].squashW,
          squashD: inside[i].squashD,
        ),
    ];
    return AutoLayoutResult(
      placements: placements,
      utilizationPercent: _stats.volumePercent,
      allBoxesFit: true,
      unfitBoxes: const [],
      strategy: LayoutStrategy.balanced,
    );
  }

  /// 지금 배치에 문제가 있거나 못 실은 짐이 있을 때의 판정: 문제 목록 + "다시 배치하면 …" + 적용 버튼
  void _showCurrentProblemsVerdict(
    List<(TrimBox, List<String>)> problems,
    AutoLayoutResult result, {
    int? computeTimeMs,
    ({double slide, AutoLayoutResult result})? slideSuggestion,
  }) {
    final parked = _stats.parked;
    final placed = result.placements.length;
    final total = placed + result.unfitBoxes.length;
    final pct = result.utilizationPercent.round();
    final hasProblems = problems.isNotEmpty;

    String name(TrimBox b) => b.label.isNotEmpty ? b.label : b.id;
    final repack = result.allBoxesFit
        ? '$total개 모두 들어갑니다 (적재율 $pct%)'
        : '$placed/$total개 들어갑니다 (적재율 $pct%)';

    _presentResult(
      dotColor: hasProblems ? const Color(0xFFFF4D4D) : const Color(0xFFFFAA33),
      title: hasProblems ? '지금 배치: 문제 ${problems.length}개' : '다시 배치하면 모두 들어갑니다',
      content: [
        if (hasProblems) ...[
          const Text('화면의 배치를 그대로 두면:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          for (final (b, reasons) in problems)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFF4D4D), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${name(b)}: ${reasons.join(', ')}',
                        style: const TextStyle(
                            color: Color(0xFFFF6B6B), fontSize: 13)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (parked.isNotEmpty) ...[
          _verdictInfoRow('못 실은 짐', '${parked.length}개 (트렁크 밖에 둠)'),
          const SizedBox(height: 8),
        ],
        const Divider(color: Color(0xFF444444), height: 1),
        const SizedBox(height: 8),
        _verdictInfoRow('다시 배치하면', repack),
        if (!result.allBoxesFit && result.unfitBoxes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '못 넣는 짐: ${_groupedUnfitLabels(result).join(', ')}',
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
          ),
        ],
        if (slideSuggestion != null) ...[
          const SizedBox(height: 8),
          _verdictInfoRow('2열 시트',
              '${(slideSuggestion.slide * 100).round()}cm 앞으로 당기면 $total개 모두 들어갑니다'),
        ],
      ],
      actions: [
        _ResultAction('확인', _ResultActionKind.dismiss, (ctx) => Navigator.pop(ctx)),
        if (slideSuggestion != null)
          _ResultAction(
            '2열 +${(slideSuggestion.slide * 100).round()}cm 적용',
            _ResultActionKind.secondary,
            (ctx) {
              Navigator.pop(ctx);
              _applySeatSlideSuggestion(slideSuggestion);
            },
          ),
        _ResultAction('이 배치 적용', _ResultActionKind.primary, (ctx) {
          Navigator.pop(ctx);
          _applyAutoLayout(result);
        }),
      ],
    );
  }

  /// 못 넣은 짐을 (이름, 사유) 로 묶어 "이름 ×N — 사유" 로 (14개가 같은 사유로 늘어서지 않게)
  List<String> _groupedUnfitLabels(AutoLayoutResult result) {
    final counts = <(String, String), int>{};
    for (final b in result.unfitBoxes) {
      final k = (b.label.isNotEmpty ? b.label : b.id, result.unfitReasons[b.id] ?? '');
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [
      for (final e in counts.entries)
        '${e.key.$1}${e.value > 1 ? ' ×${e.value}' : ''}'
            '${e.key.$2.isEmpty ? '' : ' — ${e.key.$2}'}',
    ];
  }

  /// 다 안 들어갈 때: 2열을 앞으로 당기면 전부 들어가는 첫 단계를 찾는다
  ({double slide, AutoLayoutResult result})? _suggestSeatSlide() {
    if (!_hasSeatSlide) return null;
    for (final (slide, _) in _seatSlideOptions) {
      if (slide <= _seatSlide + 1e-6) continue;
      final space = _selectedPreset.toTrunkSpace(seatSlide: slide);
      if (space == null) continue;
      final r = AutoLayoutEngine.computeLayout(space, _boxes,
          restarts: math.min(12, _restartsFor(_boxes.length)),
          budget: const Duration(milliseconds: 1500));
      if (r.allBoxesFit) return (slide: slide, result: r);
    }
    return null;
  }

  /// 제안된 2열 슬라이드를 적용하고 그 배치를 그대로 쓴다
  void _applySeatSlideSuggestion(({double slide, AutoLayoutResult result}) s) {
    final space = _selectedPreset.toTrunkSpace(seatSlide: s.slide);
    if (space == null) return;
    setState(() {
      _seatSlide = s.slide;
      _space = space;
      _detector = CollisionDetector(_space);
      _refitCamera();
    });
    _applyAutoLayout(s.result);
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

  void _showVerdictSnackBar(AutoLayoutResult result) {
    final pct = result.utilizationPercent.round();
    final placed = result.placements.length;
    final total = placed + result.unfitBoxes.length;
    final msg = result.allBoxesFit
        ? '${result.strategy.label}: $total개 배치 완료 (적재율 $pct%)'
        : '${result.strategy.label}: $placed/$total개 배치 (적재율 $pct%)';

    // 못 넣은 짐은 두 개까지만 사유와 함께, 나머지는 "외 N개" — 14개를 늘어놓으면 화면 절반을
    // 5초 동안 덮는다. 전체는 '자세히' 로 판정 시트에서.
    String snackMsg = msg;
    if (result.unfitBoxes.isNotEmpty) {
      final grouped = _groupedUnfitLabels(result);
      final shown = grouped.take(2).join(', ');
      final rest = result.unfitBoxes.length -
          result.unfitBoxes
              .where((b) => grouped.take(2).any((g) =>
                  g.startsWith(b.label.isNotEmpty ? b.label : b.id)))
              .length;
      snackMsg = '$msg\n적재 불가: $shown${rest > 0 ? ' 외 $rest개' : ''}';
    }

    // 지난 판정이 5초씩 줄 서서 나오지 않게, 남은 스낵바를 치우고 최신 판정만 보여준다
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
      SnackBar(
        content: Text(snackMsg, maxLines: 3, overflow: TextOverflow.ellipsis),
        backgroundColor:
            result.allBoxesFit ? const Color(0xFF6BD06B) : const Color(0xFFFFAA33),
        duration: const Duration(seconds: 5),
        dismissDirection: DismissDirection.horizontal,
        action: result.unfitBoxes.isEmpty
            ? null
            : SnackBarAction(
                label: '자세히',
                textColor: Colors.black87,
                onPressed: () => _showVerdictDialog(result,
                    slideSuggestion: _suggestSeatSlide()),
              ),
      ),
    );
  }

  void _showVerdictDialog(
    AutoLayoutResult result, {
    int? computeTimeMs,
    ({double slide, AutoLayoutResult result})? slideSuggestion,
    bool showLoadOrder = true,
  }) {
    final pct = result.utilizationPercent.round();
    final placed = result.placements.length;
    final total = placed + result.unfitBoxes.length;

    // 남은 공간 계산
    final totalSpaceVol = _totalTrunkVolume();
    final totalBoxVol = result.placements.fold<double>(
        0.0, (sum, p) => sum + p.box.w * p.box.d * p.box.h);
    final remainingLiters = ((totalSpaceVol - totalBoxVol) * 1000).round();
    final capacityLiters = (totalSpaceVol * 1000).round();

    // Shared utilization bar widget
    Widget utilizationVisual() {
      final ratio = (pct / 100).clamp(0.0, 1.0);
      // 막대 색은 판정 색을 따른다 (일부만 들어가는데 초록 막대가 뜨지 않게)
      final barColor = !result.allBoxesFit
          ? const Color(0xFFFFAA33)
          : pct < 70
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

    // 2열을 당기면 다 들어갈 때의 적용 동작 (일부만/하나도 안 들어간 판정 공용)
    _ResultAction slideAction() {
      final s = slideSuggestion!;
      return _ResultAction(
        '2열 +${(s.slide * 100).round()}cm 적용',
        _ResultActionKind.secondary,
        (ctx) {
          Navigator.pop(ctx);
          _applySeatSlideSuggestion(s);
        },
      );
    }

    Widget computeTimeBadge() {
      // 폰 시트에서는 개발용 계산 시간 배지를 빼서 한 줄이라도 덜 스크롤하게
      if (computeTimeMs == null || _layout.isPhoneLike) {
        return const SizedBox.shrink();
      }
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

    Widget tipBox(Color bg, String text) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline,
                color: Color(0xFFFFD700), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final dismiss = _ResultAction(
        '확인', _ResultActionKind.dismiss, (ctx) => Navigator.pop(ctx));

    if (result.placements.isEmpty && result.unfitBoxes.isNotEmpty) {
      // NO boxes fit
      _presentResult(
        dotColor: const Color(0xFFFF4D4D),
        title: '적재 불가',
        content: [
          const Text(
            '선택한 장비가 트렁크에 맞지 않습니다.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          utilizationVisual(),
          const SizedBox(height: 12),
          tipBox(
            const Color(0xFF2A1E1E),
            slideSuggestion != null
                ? '2열 시트를 ${(slideSuggestion.slide * 100).round()}cm 앞으로 당기면 '
                    '$total개 모두 들어갑니다.'
                : _hasSeatSlide
                    ? '2열을 당겨도 들어가지 않습니다.\n장비 크기를 확인하세요.'
                    : '장비 크기를 확인하세요.',
          ),
          computeTimeBadge(),
        ],
        actions: [
          if (slideSuggestion != null) slideAction(),
          _ResultAction('확인', _ResultActionKind.primary,
              (ctx) => Navigator.pop(ctx)),
        ],
      );
    } else if (result.allBoxesFit) {
      // ALL boxes fit
      _presentResult(
        dotColor: const Color(0xFF6BD06B),
        title: '모두 적재 가능!',
        content: [
          utilizationVisual(),
          const SizedBox(height: 12),
          _verdictInfoRow('적재 장비', '$total개 모두 트렁크에 들어갑니다'),
          if (_space.hasTailgateModel) ...[
            const SizedBox(height: 8),
            _verdictInfoRow('테일게이트', '닫힙니다 (닫힘 한계·개구부 반영)'),
          ],
          ..._verdictExtras(result),
          if (showLoadOrder && result.placements.isNotEmpty) ...[
            const SizedBox(height: 8),
            _verdictLoadOrderSummary(result),
          ],
          computeTimeBadge(),
        ],
        actions: [
          dismiss,
          if (_maxLoadOrder > 1)
            _ResultAction('순서 가이드', _ResultActionKind.secondary, (ctx) {
              Navigator.pop(ctx);
              _enterStepView();
            }),
          _ResultAction('배치 저장', _ResultActionKind.primary, (ctx) {
            Navigator.pop(ctx);
            _saveScene();
          }),
        ],
      );
    } else {
      // SOME boxes don't fit
      final unfitLabels = _groupedUnfitLabels(result);
      final extras = _verdictExtras(result);

      _presentResult(
        dotColor: const Color(0xFFFFAA33),
        title: '$placed/$total개 적재 가능',
        content: [
          utilizationVisual(),
          ...extras,
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
          tipBox(
            const Color(0xFF1E2A1E),
            slideSuggestion != null
                ? '2열 시트를 ${(slideSuggestion.slide * 100).round()}cm 앞으로 당기면 '
                    '$total개 모두 들어갑니다.'
                : _hasSeatSlide
                    ? '2열을 당겨도 다 들어가지 않습니다.\n장비를 줄이거나 작은 것으로 바꿔 보세요.'
                    : '더 작은 장비를 선택해 보세요.',
          ),
          computeTimeBadge(),
        ],
        actions: [
          dismiss,
          if (slideSuggestion != null) slideAction(),
          _ResultAction('다시 배치', _ResultActionKind.primary, (ctx) {
            Navigator.pop(ctx);
            _showAutoLayoutDialog();
          }),
        ],
      );
    }
  }

  /// 판정 결과를 데스크톱·태블릿은 다이얼로그(기존과 픽셀 동일), 폰은 아래 시트로 낸다.
  /// 시트에서는 버튼이 전체 폭 세로 스택(보조 → 주)이고 "확인" 은 제목 행의 ✕ 가 대신한다.
  void _presentResult({
    required Color dotColor,
    required String title,
    required List<Widget> content,
    required List<_ResultAction> actions,
  }) {
    Widget dot() => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        );

    if (!_layout.isPhoneLike) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          // 낮은 화면(태블릿 가로 등)에서는 넘치지 않고 스크롤된다
          scrollable: true,
          // 좁은 폭에서 버튼이 세로로 쌓일 때 서로 붙지 않게 (잘못 누름 방지)
          actionsOverflowButtonSpacing: 8,
          title: Row(
            children: [
              dot(),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
          actions: [for (final a in actions) a.dialogButton(ctx)],
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => resultSheetBody(
        ctx,
        title: Row(
          children: [
            dot(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content,
        ),
        buttons: [
          for (final a in actions)
            if (a.kind == _ResultActionKind.secondary) a.sheetButton(ctx),
          for (final a in actions)
            if (a.kind == _ResultActionKind.primary) a.sheetButton(ctx),
        ],
      ),
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

  /// 눌러 넣은 연질 짐과 적재 조언 (있을 때만)
  List<Widget> _verdictExtras(AutoLayoutResult result) {
    final out = <Widget>[];
    final squashed = result.squashedPlacements;
    if (squashed.isNotEmpty) {
      final names = squashed
          .map((p) => '${p.box.label.isNotEmpty ? p.box.label : p.box.id} ${(p.squashAmount * 100).round()}%')
          .join(', ');
      out.add(const SizedBox(height: 8));
      out.add(_verdictInfoRow('눌러 넣음', '${squashed.length}개 — $names'));
    }
    final applied = <TrimBox>[];
    for (final p in result.placements) {
      final b = p.box.copyWith();
      p.applyTo(b);
      applied.add(b);
    }
    final advice = PackingAdvisor.advise(applied, _space);
    if (advice.isNotEmpty) {
      out.add(const SizedBox(height: 8));
      out.add(_verdictInfoRow('조언', advice.map((a) => a.message).join('\n')));
    }
    return out;
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

  void _pushUndo() =>
      _pushUndoSnapshot(_boxes.map((b) => b.copyWith()).toList());

  /// 변경 전에 떠 둔 상태를 undo 에 넣는다 (실제로 바뀐 것을 확인한 뒤 호출)
  void _pushUndoSnapshot(List<TrimBox> snapshot) {
    _undoStack.add(snapshot);
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
    _tailgateBlockedIds = _detector.tailgateBlockers(_boxes);
    _scheduleAutosave();
  }
}

// ──── 자동 배치 대안 선택 다이얼로그 ────

enum _ResultActionKind {
  /// 다이얼로그: 회색 텍스트 버튼. 시트: 버튼 없음 (제목 행의 ✕·스크림·아래로 끌기가 대신)
  dismiss,

  /// 초록 외곽선 (2열 적용, 순서 가이드)
  secondary,

  /// 파란 채움 (배치 저장, 다시 배치, 확인)
  primary,
}

/// 판정 결과의 동작 하나. 다이얼로그·시트 양쪽에서 같은 문구·같은 콜백을 쓴다.
class _ResultAction {
  final String label;
  final _ResultActionKind kind;
  final void Function(BuildContext ctx) onTap;

  const _ResultAction(this.label, this.kind, this.onTap);

  /// 데스크톱 다이얼로그의 버튼 (기존 판정 다이얼로그와 같은 위젯·스타일)
  Widget dialogButton(BuildContext ctx) {
    switch (kind) {
      case _ResultActionKind.dismiss:
        return TextButton(
          onPressed: () => onTap(ctx),
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        );
      case _ResultActionKind.secondary:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00E676),
            side: const BorderSide(color: Color(0xFF00E676)),
          ),
          onPressed: () => onTap(ctx),
          child: Text(label),
        );
      case _ResultActionKind.primary:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4DA3FF),
          ),
          onPressed: () => onTap(ctx),
          child: Text(label),
        );
    }
  }

  /// 폰 시트의 전체 폭 버튼
  Widget sheetButton(BuildContext ctx) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const textStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    switch (kind) {
      case _ResultActionKind.dismiss:
        return TextButton(
          onPressed: () => onTap(ctx),
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        );
      case _ResultActionKind.secondary:
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00E676),
            side: const BorderSide(color: Color(0xFF00E676), width: 1.5),
            shape: shape,
          ),
          onPressed: () => onTap(ctx),
          child: Text(label, style: textStyle),
        );
      case _ResultActionKind.primary:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4DA3FF),
            foregroundColor: Colors.white,
            shape: shape,
          ),
          onPressed: () => onTap(ctx),
          child: Text(label, style: textStyle),
        );
    }
  }
}

/// 폰용 결과 시트 몸통: 손잡이 → 제목 행(✕ 닫기) → 스크롤되는 내용 → 전체 폭 버튼(48px, 세로 스택)
/// → 하단 시스템 인셋 여백. 높이는 화면의 90% 까지.
@visibleForTesting
Widget resultSheetBody(
  BuildContext ctx, {
  required Widget title,
  required Widget content,
  required List<Widget> buttons,
}) {
  final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
  final maxH = MediaQuery.sizeOf(ctx).height * 0.9;
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxH),
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF666666),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: title),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                tooltip: '닫기',
                onPressed: () => Navigator.pop(ctx),
                constraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: SingleChildScrollView(child: content)),
          if (buttons.isNotEmpty) const SizedBox(height: 12),
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SizedBox(height: 48, child: buttons[i]),
          ],
        ],
      ),
    ),
  );
}

class _AutoLayoutDialog extends StatefulWidget {
  final List<AutoLayoutResult> alternatives;
  final int computeTimeMs;
  final int trunkVolumeLiters;

  /// true 면 폰용 아래 시트 몸통으로 (showModalBottomSheet 안에서), false 면 AlertDialog
  final bool sheet;

  /// 앞 전략과 결과가 같은 전략 → 그 전략 이름 ("(= 균형 배치)" 로 표시)
  final Map<LayoutStrategy, String> sameAs;

  const _AutoLayoutDialog({
    required this.alternatives,
    required this.computeTimeMs,
    required this.trunkVolumeLiters,
    this.sheet = false,
    this.sameAs = const {},
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

    final title = Row(
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
    );

    final apply = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4DA3FF),
        foregroundColor: Colors.white,
        shape: widget.sheet
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            : null,
      ),
      // 하나도 못 넣는 배치는 적용할 것이 없다
      onPressed: widget.alternatives.isEmpty ||
              widget.alternatives[_selectedIndex].placements.isEmpty
          ? null
          : () => Navigator.pop(context, widget.alternatives[_selectedIndex]),
      child: Text('이 배치 적용',
          style: widget.sheet
              ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)
              : null),
    );

    final content = Column(
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
                                  // 좁은 폰(360dp)에서 "추천" 배지와 함께 넘치지 않게
                                  Flexible(
                                    child: Text(
                                      result.strategy.label,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (widget.sameAs[result.strategy] != null) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '(= ${widget.sameAs[result.strategy]})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 11),
                                      ),
                                    ),
                                  ],
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
        );

    if (widget.sheet) {
      return resultSheetBody(context,
          title: title, content: content, buttons: [apply]);
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      scrollable: true,
      actionsOverflowButtonSpacing: 8,
      title: title,
      content: SizedBox(
        width: math.min(400.0, MediaQuery.sizeOf(context).width - 48),
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('취소', style: TextStyle(color: Colors.grey)),
        ),
        apply,
      ],
    );
  }
}

// ──── 저장된 배치 목록 다이얼로그 ────

class _SavedScenesDialog extends StatefulWidget {
  /// 파일에서 불러오기 (지원하지 않는 플랫폼에서는 null → 버튼 숨김)
  final VoidCallback? onLoadFile;

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
        if (widget.onLoadFile != null)
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
