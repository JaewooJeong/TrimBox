import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

const _prefix = 'trimbox_scene_';
const _metaPrefix = 'trimbox_meta_';

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

/// 이름으로 씬 JSON 저장
void saveSceneToStorage(String name, String jsonStr, String vehicle, int boxCount) {
  final safeKey = name.replaceAll(RegExp(r'[^\w가-힣\s-]'), '_');
  final key = '$_prefix$safeKey';
  final metaKey = '$_metaPrefix$safeKey';

  html.window.localStorage[key] = jsonStr;

  final meta = {
    'name': name,
    'date': DateTime.now().toIso8601String(),
    'vehicle': vehicle,
    'boxCount': boxCount,
  };
  html.window.localStorage[metaKey] = json.encode(meta);
}

/// 저장된 씬 목록 가져오기
List<SavedSceneMeta> listSavedScenes() {
  final results = <SavedSceneMeta>[];
  final storage = html.window.localStorage;

  for (final key in storage.keys) {
    if (key.startsWith(_metaPrefix)) {
      final metaJson = storage[key];
      if (metaJson == null) continue;
      try {
        final meta = json.decode(metaJson) as Map<String, dynamic>;
        final sceneKey = '$_prefix${key.substring(_metaPrefix.length)}';
        // 실제 씬 데이터가 있는 경우만 포함
        if (storage.containsKey(sceneKey)) {
          results.add(SavedSceneMeta(
            key: sceneKey,
            name: meta['name'] as String? ?? '(이름 없음)',
            date: meta['date'] as String? ?? '',
            vehicle: meta['vehicle'] as String? ?? '',
            boxCount: meta['boxCount'] as int? ?? 0,
          ));
        }
      } catch (_) {
        // 손상된 메타 무시
      }
    }
  }

  // 날짜 내림차순 정렬 (최신 먼저)
  results.sort((a, b) => b.date.compareTo(a.date));
  return results;
}

/// 저장된 씬 JSON 불러오기
String? loadSceneFromStorage(String key) {
  return html.window.localStorage[key];
}

/// 저장된 씬 삭제
void deleteSceneFromStorage(String key) {
  html.window.localStorage.remove(key);
  // 메타도 삭제
  final suffix = key.substring(_prefix.length);
  html.window.localStorage.remove('$_metaPrefix$suffix');
}
