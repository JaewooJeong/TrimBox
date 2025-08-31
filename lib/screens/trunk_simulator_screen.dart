import 'package:flutter/material.dart';
import '../models/trunk_space.dart';
import '../models/box.dart';
import '../models/scene.dart';
import '../painters/trunk_painter.dart';
import '../utils/collision_utils.dart';
import '../utils/isometric_utils.dart';
import '../utils/file_utils.dart';

class TrunkSimulatorScreen extends StatefulWidget {
  const TrunkSimulatorScreen({super.key});

  @override
  State<TrunkSimulatorScreen> createState() => _TrunkSimulatorScreenState();
}

class _TrunkSimulatorScreenState extends State<TrunkSimulatorScreen> {
  TrunkSpace currentTrunkSpace = TrunkSpace.medium;
  List<Box> boxes = [];
  double scale = 80.0;
  Offset centerOffset = Offset.zero;
  String? selectedBoxId;
  Box? draggedBox;
  Offset? dragStartOffset;
  GlobalKey canvasKey = GlobalKey();
  
  @override
  void initState() {
    super.initState();
    _addSampleBoxes();
  }
  
  void _addSampleBoxes() {
    // Add some sample boxes for testing
    boxes = [
      Box(
        id: 'box1',
        width: 0.5,
        depth: 0.3,
        height: 0.4,
        x: 0.5,
        z: 0.5,
      ),
      Box(
        id: 'box2',
        width: 0.4,
        depth: 0.4,
        height: 0.3,
        x: 1.2,
        z: 0.8,
        rotationY: 90,
      ),
      Box(
        id: 'box3',
        width: 0.6,
        depth: 0.4,
        height: 0.2,
        x: 0.3,
        z: 1.5,
      ),
    ];
  }
  
  void _changeTrunkSize(TrunkSpace newSpace) {
    setState(() {
      currentTrunkSpace = newSpace;
      // Clear boxes that are out of bounds
      boxes = boxes.where((box) {
        return box.x + box.width <= newSpace.width &&
               box.z + box.depth <= newSpace.depth;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1C),
      appBar: AppBar(
        title: const Text('TrimBox Simulator'),
        backgroundColor: const Color(0xFF2E2E2E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveScene,
            tooltip: 'Save Scene',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _loadScene,
            tooltip: 'Load Scene',
          ),
          PopupMenuButton<TrunkSpace>(
            icon: const Icon(Icons.settings),
            onSelected: _changeTrunkSize,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: TrunkSpace.small,
                child: Text('Small Trunk (2×2m)'),
              ),
              const PopupMenuItem(
                value: TrunkSpace.medium,
                child: Text('Medium Trunk (3×3m)'),
              ),
              const PopupMenuItem(
                value: TrunkSpace.large,
                child: Text('Large Trunk (4×4m)'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2E2E2E),
              border: Border(
                bottom: BorderSide(color: Colors.white12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trunk: ${currentTrunkSpace.width}×${currentTrunkSpace.depth}m | '
                  'Boxes: ${boxes.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out),
                      onPressed: () => setState(() => scale = (scale - 10).clamp(30, 150)),
                      color: Colors.white70,
                    ),
                    Text(
                      '${scale.toInt()}%',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_in),
                      onPressed: () => setState(() => scale = (scale + 10).clamp(30, 150)),
                      color: Colors.white70,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Main visualization area
          Expanded(
            child: GestureDetector(
              onTapDown: _onTapDown,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                key: canvasKey,
                painter: TrunkPainter(
                  trunkSpace: currentTrunkSpace,
                  boxes: boxes,
                  scale: scale,
                  centerOffset: centerOffset,
                  selectedBoxId: selectedBoxId,
                  draggedBox: draggedBox,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          
          // Bottom control panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2E2E2E),
              border: Border(
                top: BorderSide(color: Colors.white12),
              ),
            ),
            child: Column(
              children: [
                // Selected box info
                if (selectedBoxId != null)
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Selected: ${selectedBoxId}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                
                // Control buttons
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _addSampleBox,
                      icon: const Icon(Icons.add_box),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4DA3FF),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: selectedBoxId != null ? _rotateSelectedBox : null,
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('Rotate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedBoxId != null ? const Color(0xFF4DA3FF) : const Color(0xFF333333),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: selectedBoxId != null ? _deleteSelectedBox : null,
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedBoxId != null ? const Color(0xFFFF4D4D) : const Color(0xFF333333),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _clearBoxes,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF666666),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _showSceneStats,
                      icon: const Icon(Icons.analytics),
                      label: const Text('Stats'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF666666),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _centerView,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Center'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _addSampleBox() {
    setState(() {
      boxes.add(Box(
        id: 'box${boxes.length + 1}',
        width: 0.3 + (boxes.length % 3) * 0.1,
        depth: 0.3 + (boxes.length % 3) * 0.1,
        height: 0.2 + (boxes.length % 4) * 0.1,
        x: 0.5 + (boxes.length % 3) * 0.4,
        z: 0.5 + (boxes.length % 3) * 0.4,
        rotationY: (boxes.length % 2) * 90,
      ));
    });
  }
  
  void _clearBoxes() {
    setState(() {
      boxes.clear();
    });
  }
  
  void _centerView() {
    setState(() {
      centerOffset = Offset.zero;
      scale = 80.0;
    });
  }
  
  void _onTapDown(TapDownDetails details) {
    final renderBox = canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final size = renderBox.size;
    final painter = TrunkPainter(
      trunkSpace: currentTrunkSpace,
      boxes: boxes,
      scale: scale,
      centerOffset: centerOffset,
    );
    
    final tappedBox = painter.getBoxAtPosition(details.localPosition, size);
    
    setState(() {
      selectedBoxId = tappedBox?.id;
    });
  }
  
  void _onPanStart(DragStartDetails details) {
    final renderBox = canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final size = renderBox.size;
    final painter = TrunkPainter(
      trunkSpace: currentTrunkSpace,
      boxes: boxes,
      scale: scale,
      centerOffset: centerOffset,
    );
    
    final tappedBox = painter.getBoxAtPosition(details.localPosition, size);
    
    if (tappedBox != null) {
      // Start dragging a box
      dragStartOffset = details.localPosition;
      draggedBox = Box(
        id: tappedBox.id,
        width: tappedBox.width,
        depth: tappedBox.depth,
        height: tappedBox.height,
        x: tappedBox.x,
        y: tappedBox.y,
        z: tappedBox.z,
        rotationY: tappedBox.rotationY,
      );
      selectedBoxId = tappedBox.id;
    }
  }
  
  void _onPanUpdate(DragUpdateDetails details) {
    if (draggedBox != null && dragStartOffset != null) {
      // Update box position based on drag
      final delta = details.localPosition - dragStartOffset!;
      final center = Offset(
        (canvasKey.currentContext?.findRenderObject() as RenderBox?)?.size.width / 2 ?? 0,
        (canvasKey.currentContext?.findRenderObject() as RenderBox?)?.size.height / 2 ?? 0,
      ) + centerOffset;
      
      final worldDelta = IsometricUtils.screenToWorld(delta, scale: scale);
      
      setState(() {
        draggedBox = Box(
          id: draggedBox!.id,
          width: draggedBox!.width,
          depth: draggedBox!.depth,
          height: draggedBox!.height,
          x: draggedBox!.x + worldDelta.dx * 0.1, // Scale down for smoother movement
          y: draggedBox!.y,
          z: draggedBox!.z + worldDelta.dy * 0.1,
          rotationY: draggedBox!.rotationY,
        );
      });
    } else {
      // Pan the view
      setState(() {
        centerOffset += details.delta;
      });
    }
  }
  
  void _onPanEnd(DragEndDetails details) {
    if (draggedBox != null) {
      // Snap to grid and check for valid placement
      final snappedX = IsometricUtils.snapToGrid(draggedBox!.x, currentTrunkSpace.gridSize);
      final snappedZ = IsometricUtils.snapToGrid(draggedBox!.z, currentTrunkSpace.gridSize);
      
      final finalBox = Box(
        id: draggedBox!.id,
        width: draggedBox!.width,
        depth: draggedBox!.depth,
        height: draggedBox!.height,
        x: snappedX,
        y: draggedBox!.y,
        z: snappedZ,
        rotationY: draggedBox!.rotationY,
      );
      
      // Check if placement is valid
      final otherBoxes = boxes.where((b) => b.id != finalBox.id).toList();
      if (CollisionUtils.hasAnyCollision(finalBox, otherBoxes, currentTrunkSpace)) {
        // Find nearest valid position
        final validPos = CollisionUtils.findNearestValidPosition(
          finalBox, 
          otherBoxes, 
          currentTrunkSpace, 
          currentTrunkSpace.gridSize,
        );
        finalBox.x = validPos.x;
        finalBox.z = validPos.z;
      }
      
      // Update the actual box in the list
      setState(() {
        final index = boxes.indexWhere((b) => b.id == finalBox.id);
        if (index != -1) {
          boxes[index] = finalBox;
        }
        draggedBox = null;
        dragStartOffset = null;
      });
    }
  }
  
  void _rotateSelectedBox() {
    if (selectedBoxId != null) {
      final boxIndex = boxes.indexWhere((b) => b.id == selectedBoxId);
      if (boxIndex != -1) {
        setState(() {
          final box = boxes[boxIndex];
          final newRotation = (box.rotationY + 90) % 360;
          boxes[boxIndex] = Box(
            id: box.id,
            width: box.width,
            depth: box.depth,
            height: box.height,
            x: box.x,
            y: box.y,
            z: box.z,
            rotationY: newRotation,
          );
        });
      }
    }
  }
  
  void _deleteSelectedBox() {
    if (selectedBoxId != null) {
      setState(() {
        boxes.removeWhere((b) => b.id == selectedBoxId);
        selectedBoxId = null;
      });
    }
  }
  
  void _saveScene() {
    final scene = Scene(
      trunkSpace: currentTrunkSpace,
      boxes: boxes,
    );
    
    final fileName = FileUtils.generateFileName();
    FileUtils.saveSceneToFile(scene, fileName);
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scene saved as $fileName.json'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _loadScene() async {
    try {
      final scene = await FileUtils.loadSceneFromFile();
      if (scene == null) return; // User cancelled
      
      if (!FileUtils.validateScene(scene)) {
        _showErrorDialog('Invalid Scene', 'The selected file contains invalid scene data.');
        return;
      }
      
      setState(() {
        currentTrunkSpace = scene.trunkSpace;
        boxes = scene.boxes;
        selectedBoxId = null;
        draggedBox = null;
        dragStartOffset = null;
      });
      
      // Show success message with statistics
      final stats = FileUtils.getSceneStats(scene);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scene loaded! ${stats['boxCount']} boxes, '
            '${(stats['volumeUtilization'] * 100).toStringAsFixed(1)}% volume used'
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      
    } catch (e) {
      _showErrorDialog('Load Error', 'Failed to load scene: ${e.toString()}');
    }
  }
  
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  
  void _showSceneStats() {
    final scene = Scene(trunkSpace: currentTrunkSpace, boxes: boxes);
    final stats = FileUtils.getSceneStats(scene);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scene Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boxes: ${stats['boxCount']}'),
            const SizedBox(height: 8),
            Text('Volume Utilization: ${(stats['volumeUtilization'] * 100).toStringAsFixed(1)}%'),
            Text('Floor Utilization: ${(stats['floorUtilization'] * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            Text('Total Volume: ${(stats['totalVolume']).toStringAsFixed(2)} m³'),
            Text('Trunk Volume: ${(stats['trunkVolume']).toStringAsFixed(2)} m³'),
            const SizedBox(height: 8),
            Text('Floor Area Used: ${(stats['floorArea']).toStringAsFixed(2)} m²'),
            Text('Total Floor Area: ${(stats['trunkFloorArea']).toStringAsFixed(2)} m²'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}