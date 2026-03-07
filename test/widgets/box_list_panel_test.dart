import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/box_list_panel.dart';

TrimBox _box(String id, double w, double d, double h,
    {int? loadOrder, String label = ''}) {
  final b = TrimBox(
    id: id,
    label: label.isEmpty ? id : label,
    w: w,
    d: d,
    h: h,
    color: const Color(0xFFFF0000),
  );
  b.loadOrder = loadOrder;
  return b;
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  final space = TrunkSpace.sorento();

  group('BoxListPanel — empty state', () {
    testWidgets('shows empty message when no boxes', (tester) async {
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: const [],
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      expect(find.text('캠핑 장비를 선택하고\n트렁크에 들어가는지 확인하세요'), findsOneWidget);
      expect(find.text('캠핑 장비 선택하기'), findsOneWidget);
    });

    testWidgets('empty state add button calls onAddBox', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: const [],
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () => called = true,
        onSave: () {},
        onLoad: () {},
      )));
      await tester.tap(find.text('캠핑 장비 선택하기'));
      expect(called, isTrue);
    });
  });

  group('BoxListPanel — with boxes', () {
    testWidgets('shows box tiles with labels and dimensions', (tester) async {
      final boxes = [
        _box('b1', 0.40, 0.30, 0.30, label: '쿨러'),
        _box('b2', 0.60, 0.20, 0.20, label: '텐트'),
      ];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      expect(find.text('쿨러'), findsOneWidget);
      expect(find.text('텐트'), findsOneWidget);
      expect(find.textContaining('40 × 30 × 30cm'), findsOneWidget);
      expect(find.textContaining('60 × 20 × 20cm'), findsOneWidget);
    });

    testWidgets('stats bar shows box count and volume', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30)];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      expect(find.textContaining('박스: 1개'), findsOneWidget);
    });

    testWidgets('onSelect callback fires on tile tap', (tester) async {
      String? selected;
      final boxes = [_box('b1', 0.40, 0.30, 0.30, label: '쿨러')];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (id) => selected = id,
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      await tester.tap(find.text('쿨러'));
      expect(selected, 'b1');
    });

    testWidgets('onDelete callback fires on delete button tap', (tester) async {
      String? deleted;
      final boxes = [_box('b1', 0.40, 0.30, 0.30, label: '쿨러')];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (id) => deleted = id,
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      await tester.tap(find.byTooltip('삭제'));
      expect(deleted, 'b1');
    });

    testWidgets('onRotate callback fires on rotate button tap', (tester) async {
      String? rotated;
      final boxes = [_box('b1', 0.40, 0.30, 0.30, label: '쿨러')];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (id) => rotated = id,
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      await tester.tap(find.byTooltip('90° 회전'));
      expect(rotated, 'b1');
    });
  });

  group('BoxListPanel — load order badges', () {
    testWidgets('shows load order number when loadOrder set', (tester) async {
      final boxes = [
        _box('b1', 0.40, 0.30, 0.30, label: '쿨러', loadOrder: 1),
        _box('b2', 0.60, 0.20, 0.20, label: '텐트', loadOrder: 2),
      ];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('BoxListPanel — auto layout & step view buttons', () {
    testWidgets('auto layout button visible when callback provided', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30)];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
        onAutoLayout: () {},
      )));
      expect(find.text('자동 배치'), findsWidgets);
    });

    testWidgets('quick check button visible when callback provided', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30)];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
        onAutoLayout: () {},
        onQuickCheck: () {},
      )));
      expect(find.text('들어갈까?'), findsOneWidget);
    });

    testWidgets('step view button hidden when no load orders', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30)]; // no loadOrder
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
        onStepView: () {},
      )));
      expect(find.text('적재 순서 가이드'), findsNothing);
    });

    testWidgets('step view button visible when load orders exist', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30, loadOrder: 1)];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
        onStepView: () {},
      )));
      expect(find.text('적재 순서 가이드'), findsOneWidget);
    });

    testWidgets('step view callback fires on tap', (tester) async {
      bool called = false;
      final boxes = [_box('b1', 0.40, 0.30, 0.30, loadOrder: 1)];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
        onStepView: () => called = true,
      )));
      await tester.tap(find.text('적재 순서 가이드'));
      expect(called, isTrue);
    });
  });

  group('BoxListPanel — collision indicators', () {
    testWidgets('colliding box shows warning icon', (tester) async {
      final boxes = [_box('b1', 0.40, 0.30, 0.30, label: '쿨러')];
      await tester.pumpWidget(_wrap(BoxListPanel(
        boxes: boxes,
        space: space,
        selectedBoxId: null,
        collidingBoxIds: {'b1'},
        onSelect: (_) {},
        onRotate: (_) {},
        onDelete: (_) {},
        onAddBox: () {},
        onSave: () {},
        onLoad: () {},
      )));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
