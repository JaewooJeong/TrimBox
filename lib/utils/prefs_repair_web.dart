import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 웹의 shared_preferences 는 localStorage 의 `flutter.<key>` 값을 JSON 으로 저장하고,
/// 읽을 때 `flutter.` 로 시작하는 값을 전부 json.decode 한다. JSON 이 아닌 값(예: `{{{`)은
/// 2.4.x 에서 조용히 건너뛰어(옛 버전은 `getInstance()` 가 실패) 키가 없는 것처럼 보이고,
/// prefs 를 통해서는 지울 수도 없다 — 그래서 localStorage 에서 직접 지운다.
///
/// TrimBox 키(`flutter.trimbox_*`)만 건드린다. 반환값: 지운 키 수.
int removeUnreadablePrefs() {
  const prefix = 'flutter.trimbox_';
  final storage = html.window.localStorage;
  final bad = <String>[];
  for (final key in storage.keys) {
    if (!key.startsWith(prefix)) continue;
    try {
      json.decode(storage[key]!);
    } catch (_) {
      bad.add(key);
    }
  }
  for (final key in bad) {
    storage.remove(key);
  }
  return bad.length;
}
