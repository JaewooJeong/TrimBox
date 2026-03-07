// 플랫폼별 씬 저장소 조건부 임포트
export 'scene_storage_stub.dart'
    if (dart.library.html) 'scene_storage_web.dart';
