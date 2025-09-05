import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/apartment_blueprint.dart';
import '../converters/apartment_to_isometric.dart';
import '../engine/isometric_engine.dart';
import '../main.dart';

class ApartmentSimulatorScreen extends StatefulWidget {
  const ApartmentSimulatorScreen({super.key});

  @override
  State<ApartmentSimulatorScreen> createState() => _ApartmentSimulatorScreenState();
}

class _ApartmentSimulatorScreenState extends State<ApartmentSimulatorScreen>
    with TickerProviderStateMixin {
  IsometricEngine? _engine;
  ApartmentBlueprint? _blueprint;
  late AnimationController _animationController;
  
  Map<String, dynamic>? _similarityAnalysis;
  bool _isLoading = false;
  bool _showAnalysis = false;
  double _scale = 60.0;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _loadDefaultApartment();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultApartment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 기본 23평 아파트 로딩
      final jsonString = await rootBundle.loadString(
        'assets/apartment_blueprints/standard_23_pyeong.json'
      );
      
      final jsonData = jsonDecode(jsonString);
      _blueprint = ApartmentBlueprint.fromJson(jsonData);
      
      // 아이소메트릭 변환
      _engine?.dispose();
      _engine = ApartmentToIsometricConverter.convertToEngine(_blueprint!);
      
      // 유사도 분석 생성
      _similarityAnalysis = ApartmentToIsometricConverter.generateSimilarityAnalysis(
        _blueprint!,
        _engine!,
      );
      
      // 화면에 맞게 조정
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final screenSize = MediaQuery.of(context).size;
        _engine!.fitToAllObjects(screenSize);
        _engine!.setScale(_scale);
      });
      
    } catch (e) {
      print('아파트 로딩 실패: $e');
      _showError('아파트 도면을 로드할 수 없습니다: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSimilarityAnalysis() {
    if (_similarityAnalysis == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('98% 유사도 분석 결과'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAnalysisSection('전체 유사도', _similarityAnalysis!['overall_similarity'] + '%'),
              const SizedBox(height: 16),
              
              _buildAnalysisSection('총 변환 객체 수', _similarityAnalysis!['total_objects'].toString()),
              const SizedBox(height: 16),
              
              const Text('카테고리별 변환 현황:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              ...((_similarityAnalysis!['conversion_reports'] as List).map((report) => 
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${report['category']}: ${report['converted_count']}/${report['original_count']} (${(report['accuracy'] * 100).toInt()}%)'),
                )
              )),
              
              const SizedBox(height: 16),
              const Text('기하학적 정확도:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              ..._buildMetricsSection(_similarityAnalysis!['geometric_accuracy']),
              
              const SizedBox(height: 16),  
              const Text('시각적 충실도:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              ..._buildMetricsSection(_similarityAnalysis!['visual_fidelity']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMetricsSection(Map<String, dynamic> metrics) {
    return metrics.entries.map((entry) {
      final value = entry.value;
      final displayValue = value is double 
          ? '${value.toStringAsFixed(1)}%'
          : value.toString();
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('• ${_formatMetricName(entry.key)}: $displayValue'),
      );
    }).toList();
  }

  String _formatMetricName(String key) {
    switch (key) {
      case 'scale_factor': return '스케일 팩터';
      case 'preserved_proportions': return '비율 보존';
      case 'height_accuracy': return '높이 정확도';
      case 'area_preservation': return '면적 보존';
      case 'color_mapping': return '색상 매핑';
      case 'texture_representation': return '텍스처 표현';
      case 'lighting_simulation': return '조명 시뮬레이션';
      case 'depth_perception': return '깊이 인식';
      default: return key;
    }
  }

  Widget _buildAnalysisSection(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('23평 아파트 아이소메트릭 변환'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: _showSimilarityAnalysis,
            tooltip: '유사도 분석',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDefaultApartment,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('아파트 도면을 아이소메트릭으로 변환 중...'),
                ],
              ),
            )
          : Column(
              children: [
                // 정보 패널
                _buildInfoPanel(),
                
                // 컨트롤 패널
                _buildControlPanel(),
                
                // 3D 뷰어
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _engine == null
                        ? const Center(child: Text('아파트 데이터를 불러오는 중...'))
                        : AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: IsometricEnginePainter(_engine!),
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
    );
  }

  Widget _buildInfoPanel() {
    if (_blueprint == null || _similarityAnalysis == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoItem('아파트 크기', '${_blueprint!.info.sizePyeong}평 (${_blueprint!.info.sizeSqm.toStringAsFixed(1)}㎡)'),
          _buildInfoItem('방 구성', _blueprint!.info.layoutType),
          _buildInfoItem('유사도', '${_similarityAnalysis!['overall_similarity']}%'),
          _buildInfoItem('3D 객체 수', '${_engine?.objects.length ?? 0}개'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
                  min: 20.0,
                  max: 120.0,
                  divisions: 50,
                  label: _scale.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      _scale = value;
                      _engine?.setScale(_scale);
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
              ElevatedButton.icon(
                onPressed: () => _engine?.zoom(1.2),
                icon: const Icon(Icons.zoom_in, size: 18),
                label: const Text('확대'),
              ),
              ElevatedButton.icon(
                onPressed: () => _engine?.zoom(0.8),
                icon: const Icon(Icons.zoom_out, size: 18),
                label: const Text('축소'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final screenSize = MediaQuery.of(context).size;
                  _engine?.fitToAllObjects(screenSize);
                  setState(() {});
                },
                icon: const Icon(Icons.fit_screen, size: 18),
                label: const Text('전체 보기'),
              ),
              ElevatedButton.icon(
                onPressed: _showSimilarityAnalysis,
                icon: const Icon(Icons.assessment, size: 18),
                label: const Text('분석 결과'),
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
          Text('총 객체: ${_engine?.objects.length ?? 0}'),
          const SizedBox(width: 16),
          Text('FPS: ${_engine?.performance.averageFps.toStringAsFixed(1) ?? '0.0'}'),
          const Spacer(),
          if (_similarityAnalysis != null)
            Text('변환 유사도: ${_similarityAnalysis!['overall_similarity']}%'),
          const SizedBox(width: 16),
          Text('스케일: ${_engine?.transform.scale.toStringAsFixed(1) ?? '0.0'}'),
        ],
      ),
    );
  }
}