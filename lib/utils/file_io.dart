// 플랫폼별 파일 I/O 조건부 임포트
export 'file_io_stub.dart'
    if (dart.library.html) 'file_io_web.dart';
