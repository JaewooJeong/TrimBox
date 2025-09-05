import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trimbox/main.dart' as app;
import 'dart:math' as math;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('웹 환경에서 아이소메트릭 엔진 통합 테스트', () {
    testWidgets('엔진 초기화 및 렌더링 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 앱이 정상적으로 시작되었는지 확인
      expect(find.text('아이소메트릭 엔진 데모'), findsOneWidget);
      
      // 컨트롤 패널이 표시되는지 확인
      expect(find.text('스케일:'), findsOneWidget);
      expect(find.text('확대'), findsOneWidget);
      expect(find.text('축소'), findsOneWidget);
      expect(find.text('전체 보기'), findsOneWidget);

      // 상태 바가 표시되는지 확인
      expect(find.textContaining('객체:'), findsOneWidget);
      expect(find.textContaining('FPS:'), findsOneWidget);
      expect(find.textContaining('스케일:'), findsOneWidget);
    });

    testWidgets('상호작용 테스트 - 스케일 슬라이더', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 슬라이더 찾기
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      // 슬라이더 값 변경
      await tester.drag(sliderFinder, const Offset(100, 0));
      await tester.pumpAndSettle();

      // 스케일이 변경되었는지 상태바에서 확인
      expect(find.textContaining('스케일:'), findsOneWidget);
    });

    testWidgets('상호작용 테스트 - 확대/축소 버튼', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 확대 버튼 테스트
      final zoomInButton = find.text('확대');
      expect(zoomInButton, findsOneWidget);
      await tester.tap(zoomInButton);
      await tester.pumpAndSettle();

      // 축소 버튼 테스트
      final zoomOutButton = find.text('축소');
      expect(zoomOutButton, findsOneWidget);
      await tester.tap(zoomOutButton);
      await tester.pumpAndSettle();

      // 전체 보기 버튼 테스트
      final fitAllButton = find.text('전체 보기');
      expect(fitAllButton, findsOneWidget);
      await tester.tap(fitAllButton);
      await tester.pumpAndSettle();
    });

    testWidgets('플로팅 액션 버튼 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 중앙 정렬 버튼
      final centerButton = find.byIcon(Icons.center_focus_strong);
      expect(centerButton, findsOneWidget);
      await tester.tap(centerButton);
      await tester.pumpAndSettle();

      // 객체 추가 버튼
      final addButton = find.byIcon(Icons.add);
      expect(addButton, findsOneWidget);
      
      // 초기 객체 수 확인
      final initialObjectText = tester.widget<Text>(
        find.textContaining('객체:').first
      );
      final initialCount = _extractObjectCount(initialObjectText.data!);
      
      // 객체 추가
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      
      // 객체 수가 증가했는지 확인
      final updatedObjectText = tester.widget<Text>(
        find.textContaining('객체:').first
      );
      final updatedCount = _extractObjectCount(updatedObjectText.data!);
      
      expect(updatedCount, equals(initialCount + 1));
    });

    testWidgets('엔진 정보 다이얼로그 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 정보 버튼 찾기
      final infoButton = find.byIcon(Icons.info_outline);
      expect(infoButton, findsOneWidget);

      // 정보 다이얼로그 열기
      await tester.tap(infoButton);
      await tester.pumpAndSettle();

      // 다이얼로그 내용 확인
      expect(find.text('엔진 정보'), findsOneWidget);
      expect(find.textContaining('IsometricEngine Debug Info:'), findsOneWidget);
      expect(find.textContaining('Objects:'), findsOneWidget);
      expect(find.textContaining('Scale:'), findsOneWidget);
      expect(find.textContaining('Performance:'), findsOneWidget);

      // 다이얼로그 닫기
      final okButton = find.text('확인');
      expect(okButton, findsOneWidget);
      await tester.tap(okButton);
      await tester.pumpAndSettle();

      // 다이얼로그가 닫혔는지 확인
      expect(find.text('엔진 정보'), findsNothing);
    });

    testWidgets('성능 모니터링 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // FPS 모니터링을 위해 여러 프레임 대기
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16)); // ~60 FPS
      }

      // FPS 값이 표시되는지 확인
      final fpsText = find.textContaining('FPS:');
      expect(fpsText, findsOneWidget);

      final fpsWidget = tester.widget<Text>(fpsText.first);
      final fpsValue = _extractFpsValue(fpsWidget.data!);
      
      // FPS가 합리적인 범위에 있는지 확인 (0-120)
      expect(fpsValue, greaterThanOrEqualTo(0));
      expect(fpsValue, lessThanOrEqualTo(120));
    });

    testWidgets('렌더링 성능 스트레스 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 여러 객체 추가
      final addButton = find.byIcon(Icons.add);
      for (int i = 0; i < 20; i++) {
        await tester.tap(addButton);
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pumpAndSettle();

      // 객체가 추가되었는지 확인
      final objectText = tester.widget<Text>(
        find.textContaining('객체:').first
      );
      final objectCount = _extractObjectCount(objectText.data!);
      expect(objectCount, greaterThan(20)); // 기본 객체 + 추가된 객체들

      // 성능 확인을 위한 연속 렌더링
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 60; i++) { // 60프레임
        await tester.pump(const Duration(milliseconds: 16));
      }
      stopwatch.stop();

      // 1초 내에 렌더링이 완료되어야 함
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));

      // FPS가 여전히 합리적인 수준인지 확인
      final fpsWidget = tester.widget<Text>(
        find.textContaining('FPS:').first
      );
      final fpsValue = _extractFpsValue(fpsWidget.data!);
      expect(fpsValue, greaterThan(10)); // 최소 10 FPS 유지
    });

    testWidgets('메모리 사용량 테스트', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 대량의 객체 추가 및 제거를 통한 메모리 테스트
      final addButton = find.byIcon(Icons.add);
      
      // 50개 객체 추가
      for (int i = 0; i < 50; i++) {
        await tester.tap(addButton);
        if (i % 10 == 0) {
          await tester.pumpAndSettle();
        }
      }

      await tester.pumpAndSettle();

      // 객체 수 확인
      final objectText = tester.widget<Text>(
        find.textContaining('객체:').first
      );
      final objectCount = _extractObjectCount(objectText.data!);
      expect(objectCount, greaterThan(50));

      // 몇 초간 렌더링 지속
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 앱이 여전히 응답하는지 확인
      expect(find.text('아이소메트릭 엔진 데모'), findsOneWidget);
    });
  });
}

int _extractObjectCount(String text) {
  final regex = RegExp(r'객체:\s*(\d+)');
  final match = regex.firstMatch(text);
  return match != null ? int.parse(match.group(1)!) : 0;
}

double _extractFpsValue(String text) {
  final regex = RegExp(r'FPS:\s*([\d.]+)');
  final match = regex.firstMatch(text);
  return match != null ? double.parse(match.group(1)!) : 0.0;
}