import 'dart:convert';
import 'dart:html' as html;
import '../models/scene.dart';
import '../models/trunk_space.dart';
import '../models/box.dart';

class FileUtils {
  /// Save scene to JSON file (Web implementation)
  static void saveSceneToFile(Scene scene, String fileName) {
    final jsonString = jsonEncode(scene.toJson());
    final bytes = utf8.encode(jsonString);
    final blob = html.Blob([bytes], 'application/json');
    
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', '$fileName.json')
      ..click();
    
    html.Url.revokeObjectUrl(url);
  }
  
  /// Load scene from JSON file (Web implementation)
  static Future<Scene?> loadSceneFromFile() async {
    final input = html.FileUploadInputElement()..accept = '.json';
    input.click();
    
    await input.onChange.first;
    final file = input.files?.first;
    if (file == null) return null;
    
    try {
      final reader = html.FileReader();
      reader.readAsText(file);
      await reader.onLoad.first;
      
      final jsonString = reader.result as String;
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      return Scene.fromJson(jsonData);
    } catch (e) {
      print('Error loading scene: $e');
      return null;
    }
  }
  
  /// Validate scene data
  static bool validateScene(Scene scene) {
    // Check version compatibility
    if (scene.version != '1.0.0') {
      print('Unsupported scene version: ${scene.version}');
      return false;
    }
    
    // Validate trunk space
    if (scene.trunkSpace.width <= 0 || 
        scene.trunkSpace.depth <= 0 || 
        scene.trunkSpace.height <= 0) {
      print('Invalid trunk space dimensions');
      return false;
    }
    
    // Validate boxes
    for (final box in scene.boxes) {
      if (box.width <= 0 || box.depth <= 0 || box.height <= 0) {
        print('Invalid box dimensions: ${box.id}');
        return false;
      }
      
      if (box.x < 0 || box.z < 0 || box.y < 0) {
        print('Invalid box position: ${box.id}');
        return false;
      }
      
      if (![0, 90, 180, 270].contains(box.rotationY)) {
        print('Invalid box rotation: ${box.id}');
        return false;
      }
    }
    
    return true;
  }
  
  /// Generate default scene file name
  static String generateFileName() {
    final now = DateTime.now();
    return 'trimbox_scene_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }
  
  /// Create sample scene for testing
  static Scene createSampleScene() {
    return Scene(
      trunkSpace: TrunkSpace.medium,
      boxes: [
        Box(
          id: 'sample1',
          width: 0.5,
          depth: 0.3,
          height: 0.4,
          x: 0.5,
          z: 0.5,
        ),
        Box(
          id: 'sample2',
          width: 0.4,
          depth: 0.4,
          height: 0.3,
          x: 1.2,
          z: 0.8,
          rotationY: 90,
        ),
      ],
    );
  }
  
  /// Export scene statistics
  static Map<String, dynamic> getSceneStats(Scene scene) {
    double totalVolume = 0;
    double floorArea = 0;
    
    for (final box in scene.boxes) {
      totalVolume += box.width * box.depth * box.height;
      
      // Calculate floor area (considering rotation)
      if (box.rotationY == 90 || box.rotationY == 270) {
        floorArea += box.depth * box.width;
      } else {
        floorArea += box.width * box.depth;
      }
    }
    
    final trunkVolume = scene.trunkSpace.width * 
                       scene.trunkSpace.depth * 
                       scene.trunkSpace.height;
    
    final trunkFloorArea = scene.trunkSpace.width * scene.trunkSpace.depth;
    
    return {
      'boxCount': scene.boxes.length,
      'totalVolume': totalVolume,
      'trunkVolume': trunkVolume,
      'volumeUtilization': totalVolume / trunkVolume,
      'floorArea': floorArea,
      'trunkFloorArea': trunkFloorArea,
      'floorUtilization': floorArea / trunkFloorArea,
    };
  }
}