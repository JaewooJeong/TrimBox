// 비-웹 플랫폼 스텁 (모바일/데스크톱용 미구현)

/// 이 플랫폼에서 파일 내보내기·가져오기·이미지 저장을 쓸 수 있는가.
/// false 면 화면이 해당 버튼을 숨긴다 (1차 배포: 웹만 지원).
const bool fileActionsSupported = false;

void downloadJson(String content, String filename) {
  throw UnsupportedError('File download not supported on this platform');
}

void downloadBytes(List<int> bytes, String filename, String mimeType) {
  throw UnsupportedError('File download not supported on this platform');
}

Future<String?> pickJsonFile() async {
  throw UnsupportedError('File picker not supported on this platform');
}

Future<bool> shareOrDownloadImage(
    List<int> bytes, String filename, String mimeType) async {
  downloadBytes(bytes, filename, mimeType);
  return false;
}
