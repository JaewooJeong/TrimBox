/// 비-웹 플랫폼 스텁 (모바일/데스크톱용 미구현)
void downloadJson(String content, String filename) {
  throw UnsupportedError('File download not supported on this platform');
}

void downloadBytes(List<int> bytes, String filename, String mimeType) {
  throw UnsupportedError('File download not supported on this platform');
}

Future<String?> pickJsonFile() async {
  throw UnsupportedError('File picker not supported on this platform');
}
