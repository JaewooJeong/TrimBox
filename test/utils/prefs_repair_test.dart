import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimbox/utils/prefs_repair.dart';
import 'package:trimbox/utils/scene_storage.dart' as storage;

void main() {
  test('웹이 아닌 플랫폼에서는 복구할 것이 없다 (웹 구현은 prefs_repair_web_test.dart)', () {
    expect(removeUnreadablePrefs(), 0);
  });

  test('ensureReadable: 읽을 수 있으면 true, clearAutosave 는 자동 저장만 지운다', () async {
    SharedPreferences.setMockInitialValues(
        {'trimbox_autosave': '{{{', 'trimbox_onboarded': true});
    expect(await storage.ensureReadable(), isTrue);
    await storage.clearAutosave();
    expect(await storage.loadAutosave(), isNull);
    expect(await storage.hasSeenOnboarding(), isTrue);
  });
}
