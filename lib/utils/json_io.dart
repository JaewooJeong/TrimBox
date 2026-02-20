import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/scene.dart';

/// JSON 저장/불러오기 유틸리티
class JsonIO {
  /// Scene을 JSON 문자열로 직렬화
  static String exportScene(Scene scene) => scene.toJsonString();

  /// JSON 문자열에서 Scene 역직렬화
  static Scene importScene(String jsonStr) {
    try {
      return Scene.fromJsonString(jsonStr);
    } catch (e) {
      throw FormatException('잘못된 JSON 형식입니다: $e');
    }
  }

  /// 파일로 저장 (모바일/데스크톱)
  static Future<void> saveToFile(Scene scene, String path) async {
    if (kIsWeb) return; // 웹에서는 파일 저장 불가
    final file = File(path);
    await file.writeAsString(scene.toJsonString());
  }

  /// 파일에서 불러오기 (모바일/데스크톱)
  static Future<Scene> loadFromFile(String path) async {
    final file = File(path);
    final str = await file.readAsString();
    return importScene(str);
  }

  /// JSON 문자열 유효성 검증
  static bool isValidSceneJson(String jsonStr) {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return data.containsKey('space') && data.containsKey('boxes');
    } catch (_) {
      return false;
    }
  }
}
