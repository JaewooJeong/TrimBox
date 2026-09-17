import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 씬 저장소 — 모든 플랫폼 공통 (웹은 localStorage, Android/iOS 는 SharedPreferences).
///
/// 키 구조
/// - `trimbox_scene_<name>` : 씬 JSON
/// - `trimbox_meta_<name>`  : {name, date, vehicle, boxCount}
/// - `trimbox_autosave`     : 마지막 작업 상태 (자동 복원용)
/// - `trimbox_onboarded`    : 온보딩을 본 적이 있는지
const _prefix = 'trimbox_scene_';
const _metaPrefix = 'trimbox_meta_';
const _autosaveKey = 'trimbox_autosave';
const _onboardedKey = 'trimbox_onboarded';

/// 저장된 씬 메타데이터
class SavedSceneMeta {
  final String key;
  final String name;
  final String date;
  final String vehicle;
  final int boxCount;

  SavedSceneMeta({
    required this.key,
    required this.name,
    required this.date,
    required this.vehicle,
    required this.boxCount,
  });
}

String _safeKey(String name) => name.replaceAll(RegExp(r'[^\w가-힣\s-]'), '_');

/// 이름으로 씬 JSON 저장
Future<void> saveSceneToStorage(
    String name, String jsonStr, String vehicle, int boxCount) async {
  final prefs = await SharedPreferences.getInstance();
  final safe = _safeKey(name);
  await prefs.setString('$_prefix$safe', jsonStr);
  await prefs.setString(
    '$_metaPrefix$safe',
    json.encode({
      'name': name,
      'date': DateTime.now().toIso8601String(),
      'vehicle': vehicle,
      'boxCount': boxCount,
    }),
  );
}

/// 저장된 씬 목록 (최신 먼저)
Future<List<SavedSceneMeta>> listSavedScenes() async {
  final prefs = await SharedPreferences.getInstance();
  final results = <SavedSceneMeta>[];
  for (final key in prefs.getKeys()) {
    if (!key.startsWith(_metaPrefix)) continue;
    final metaJson = prefs.getString(key);
    if (metaJson == null) continue;
    try {
      final meta = json.decode(metaJson) as Map<String, dynamic>;
      final sceneKey = '$_prefix${key.substring(_metaPrefix.length)}';
      if (!prefs.containsKey(sceneKey)) continue;
      results.add(SavedSceneMeta(
        key: sceneKey,
        name: meta['name'] as String? ?? '(이름 없음)',
        date: meta['date'] as String? ?? '',
        vehicle: meta['vehicle'] as String? ?? '',
        boxCount: meta['boxCount'] as int? ?? 0,
      ));
    } catch (_) {
      // 손상된 메타 무시
    }
  }
  results.sort((a, b) => b.date.compareTo(a.date));
  return results;
}

/// 저장된 씬 JSON 불러오기
Future<String?> loadSceneFromStorage(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}

/// 저장된 씬 삭제
Future<void> deleteSceneFromStorage(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(key);
  await prefs.remove('$_metaPrefix${key.substring(_prefix.length)}');
}

/// 현재 작업 상태 자동 저장 / 복원
Future<void> saveAutosave(String jsonStr) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_autosaveKey, jsonStr);
}

Future<String?> loadAutosave() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_autosaveKey);
}

/// 온보딩 표시 여부
Future<bool> hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardedKey) ?? false;
}

Future<void> markOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardedKey, true);
}
