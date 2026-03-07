// 비-웹 플랫폼 스텁 — localStorage 미지원

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
  throw UnsupportedError('Scene storage not supported on this platform');
}

/// 저장된 씬 목록 가져오기
List<SavedSceneMeta> listSavedScenes() {
  throw UnsupportedError('Scene storage not supported on this platform');
}

/// 저장된 씬 JSON 불러오기
String? loadSceneFromStorage(String key) {
  throw UnsupportedError('Scene storage not supported on this platform');
}

/// 저장된 씬 삭제
void deleteSceneFromStorage(String key) {
  throw UnsupportedError('Scene storage not supported on this platform');
}
