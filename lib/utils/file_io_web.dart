import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js_util' as js_util;

/// 이 플랫폼에서 파일 내보내기·가져오기·이미지 저장을 쓸 수 있는가.
const bool fileActionsSupported = true;

/// JSON 문자열을 파일로 다운로드
void downloadJson(String content, String filename) {
  final blob = html.Blob([content], 'application/json');
  _downloadBlob(blob, filename);
}

/// 바이너리 데이터를 파일로 다운로드 (PNG 등)
void downloadBytes(List<int> bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  _downloadBlob(blob, filename);
}

void _downloadBlob(html.Blob blob, String filename) {
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// 파일 선택 다이얼로그를 열어 JSON 파일 내용을 읽어옴
Future<String?> pickJsonFile() async {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.json';
  input.click();

  // 사용자가 파일을 선택하지 않고 취소할 경우를 대비
  var picked = false;
  input.onChange.listen((_) {
    picked = true;
    final file = input.files?.first;
    if (file == null) {
      completer.complete(null);
      return;
    }
    final reader = html.FileReader()..readAsText(file);
    reader.onLoadEnd.listen((_) {
      completer.complete(reader.result as String?);
    });
    reader.onError.listen((_) {
      completer.complete(null);
    });
  });

  // 포커스 복귀 시 취소 감지 (파일 선택 안 한 경우)
  html.window.onFocus.first.then((_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!picked && !completer.isCompleted) {
        completer.complete(null);
      }
    });
  });

  return completer.future;
}

/// 이미지를 Web Share API로 공유 시도, 미지원 시 다운로드 폴백
Future<bool> shareOrDownloadImage(
    List<int> bytes, String filename, String mimeType) async {
  try {
    final navigator = html.window.navigator;
    // canShare 지원 확인
    if (js_util.hasProperty(navigator, 'canShare')) {
      final file = html.File([bytes], filename, {'type': mimeType});
      final shareData = js_util.jsify({'files': [file]});
      final canShare =
          js_util.callMethod<bool>(navigator, 'canShare', [shareData]);
      if (canShare) {
        await js_util.promiseToFuture(
            js_util.callMethod(navigator, 'share', [shareData]));
        return true;
      }
    }
  } catch (_) {
    // Share failed or cancelled — fall through to download
  }
  downloadBytes(bytes, filename, mimeType);
  return false;
}
