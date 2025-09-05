import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'engine/isometric_engine.dart';
import 'math/vector2d.dart';
import 'math/vector3d.dart';
import 'math/isometric_transform.dart';
import 'objects/isometric_box.dart';

void main() {
  print('🚀 아이소메트릭 엔진 데모 시작...');
  runApp(const IsometricEngineApp());
}

class IsometricEngineApp extends StatelessWidget {
  const IsometricEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '아이소메트릭 엔진 데모',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const IsometricEngineDemo(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class IsometricEngineDemo extends StatefulWidget {
  const IsometricEngineDemo({super.key});

  @override
  State<IsometricEngineDemo> createState() => _IsometricEngineDemoState();
}

class _IsometricEngineDemoState extends State<IsometricEngineDemo>
    with TickerProviderStateMixin {
  late IsometricEngine engine;
  late AnimationController _animationController;
  double _scale = 50.0;
  Vector2D _offset = Vector2D.zero;
  
  @override
  void initState() {
    super.initState();
    print('🎮 아이소메트릭 엔진 초기화 중...');
    
    // 엔진 초기화
    engine = IsometricEngine(
      backgroundColor: Colors.grey.shade100,
    );
    
    // 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    // 데모 객체들 생성
    _createDemoObjects();
    
    print('✅ 아이소메트릭 엔진 초기화 완료!');
  }

  /// 데모용 3D 객체들 생성
  void _createDemoObjects() {
    // 바닥 평면 (큰 회색 박스)
    final floor = IsometricBox(
      id: 'floor',
      position: const Vector3D(-5, -0.5, -5),
      dimensions: const Vector3D(10, 0.5, 10),
      color: Colors.grey.shade300,
    );
    engine.addObject(floor);
    
    // 컬러풀한 큐브들
    final colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];
    
    for (int i = 0; i < 6; i++) {
      final angle = i * 60.0 * (3.14159 / 180.0); // 60도씩
      final x = 2.0 * math.cos(angle);
      final z = 2.0 * math.sin(angle);
      final height = 0.5 + (i * 0.3);
      
      final cube = IsometricBox(
        id: 'cube_$i',
        position: Vector3D(x, 0, z),
        dimensions: Vector3D(0.8, height, 0.8),
        color: colors[i],
      );
      engine.addObject(cube);
    }
    
    // 중앙 타워
    final tower = IsometricBox(
      id: 'tower',
      position: const Vector3D(-0.3, 0, -0.3),
      dimensions: const Vector3D(0.6, 3, 0.6),
      color: Colors.amber,
    );
    engine.addObject(tower);
    
    print('📦 ${engine.objects.length}개 데모 객체 생성 완료');
  }

  /// 뷰포트 중앙으로 카메라 이동
  void _centerView(Size screenSize) {
    setState(() {
      _offset = Vector2D(screenSize.width / 2, screenSize.height / 2);
      engine.setTransform(IsometricTransform(
        scale: _scale,
        offset: _offset,
      ));
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('아이소메트릭 엔진 데모'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showEngineInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          // 컨트롤 패널
          _buildControlPanel(),
          
          // 3D 뷰어
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: IsometricEnginePainter(engine),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
          
          // 상태 바
          _buildStatusBar(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "center",
            onPressed: () {
              final screenSize = MediaQuery.of(context).size;
              _centerView(screenSize);
            },
            child: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "add",
            onPressed: _addRandomBox,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('스케일: '),
              Expanded(
                child: Slider(
                  value: _scale,
                  min: 10.0,
                  max: 100.0,
                  divisions: 45,
                  label: _scale.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _scale = value;
                      engine.setScale(_scale);
                    });
                  },
                ),
              ),
              Text('${_scale.round()}'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => engine.zoom(1.2),
                child: const Text('확대'),
              ),
              ElevatedButton(
                onPressed: () => engine.zoom(0.8),
                child: const Text('축소'),
              ),
              ElevatedButton(
                onPressed: () {
                  final screenSize = MediaQuery.of(context).size;
                  engine.fitToAllObjects(screenSize);
                  setState(() {});
                },
                child: const Text('전체 보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          Text('객체: ${engine.objects.length}'),
          const SizedBox(width: 16),
          Text('FPS: ${engine.performance.averageFps.toStringAsFixed(1)}'),
          const Spacer(),
          Text('스케일: ${engine.transform.scale.toStringAsFixed(1)}'),
        ],
      ),
    );
  }

  void _addRandomBox() {
    final random = math.Random();
    final colors = [Colors.red, Colors.green, Colors.blue, Colors.orange, Colors.purple];
    
    final newBox = IsometricBox(
      id: 'random_${DateTime.now().millisecondsSinceEpoch}',
      position: Vector3D(
        (random.nextDouble() - 0.5) * 6,
        0,
        (random.nextDouble() - 0.5) * 6,
      ),
      dimensions: Vector3D(
        0.5 + random.nextDouble(),
        0.5 + random.nextDouble() * 2,
        0.5 + random.nextDouble(),
      ),
      color: colors[random.nextInt(colors.length)],
    );
    
    engine.addObject(newBox);
    setState(() {});
  }

  void _showEngineInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('엔진 정보'),
        content: Text(engine.getDebugInfo()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

/// 아이소메트릭 엔진을 위한 CustomPainter
class IsometricEnginePainter extends CustomPainter {
  final IsometricEngine engine;

  IsometricEnginePainter(this.engine);

  @override
  void paint(Canvas canvas, Size size) {
    // 엔진을 통해 장면 렌더링
    engine.render(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 항상 다시 그리기 (애니메이션을 위해)
  }
}