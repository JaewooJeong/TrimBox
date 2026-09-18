// 웹 전용: Windows 터미널에서 `flutter test --platform chrome test/utils/prefs_repair_web_test.dart`
// (VM 에서는 @TestOn 때문에 건너뛴다. WSL 에서 cmd.exe 를 거쳐 띄우면 Chrome 이 붙지 않아
// "loading" 에서 멈추므로 거기서는 돌리지 않는다.) 실제 웹 빌드에서의 동작은 Playwright
// e2e/persistence.spec.ts 의 "손상된 자동 저장 값 5종" 이 시작 직후 지워졌는지로 단언한다.
@TestOn('browser')
library;

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimbox/utils/prefs_repair.dart';
import 'package:trimbox/utils/scene_storage.dart' as storage;

void main() {
  setUp(() => html.window.localStorage.clear());

  test('JSON 이 아닌 원시 값은 플러그인이 조용히 건너뛰어 남는다 → 시작 시 TrimBox 키만 지운다',
      () async {
    final ls = html.window.localStorage;
    ls['flutter.trimbox_autosave'] = '{{{not-json';
    ls['flutter.trimbox_onboarded'] = 'true';
    ls['flutter.trimbox_scene_trip'] = '"{}"';
    ls['other.key'] = '{{{';

    expect(await storage.ensureReadable(), isTrue);
    expect(ls.containsKey('flutter.trimbox_autosave'), isFalse);
    expect(ls['flutter.trimbox_onboarded'], 'true', reason: '멀쩡한 값은 그대로');
    expect(ls['flutter.trimbox_scene_trip'], '"{}"');
    expect(ls['other.key'], '{{{', reason: '남의 키는 건드리지 않는다');

    expect(await storage.hasSeenOnboarding(), isTrue);
    expect(await storage.loadAutosave(), isNull);
    await storage.saveAutosave('{"ok":1}');
    expect((await SharedPreferences.getInstance()).getString('trimbox_autosave'),
        '{"ok":1}');
  });

  test('깨진 값이 없으면 아무것도 지우지 않는다', () {
    html.window.localStorage['flutter.trimbox_autosave'] = '"{}"';
    expect(removeUnreadablePrefs(), 0);
    expect(html.window.localStorage.containsKey('flutter.trimbox_autosave'), isTrue);
  });
}
