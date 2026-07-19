import 'package:f95_portal/constants.dart';
import 'package:f95_portal/widgets/segmented_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Radius outer = Radius.circular(AppRadii.pillSegment);
  const Color fill = Color(0xFF404040);

  Future<void> pumpLabels(WidgetTester tester, int count) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SegmentedPill(
            segments: [for (int i = 0; i < count; i++) PillSegment(color: fill, child: Text('s$i'))],
          ),
        ),
      ),
    );
  }

  /// The rounding actually painted for the segment at [index].
  BorderRadius segmentRadius(WidgetTester tester, int index) {
    final container = tester
        .widgetList<Container>(find.descendant(of: find.byType(SegmentedPill), matching: find.byType(Container)))
        .elementAt(index);
    return (container.decoration! as BoxDecoration).borderRadius! as BorderRadius;
  }

  testWidgets('a lone segment is fully rounded', (tester) async {
    await pumpLabels(tester, 1);

    expect(segmentRadius(tester, 0), const BorderRadius.all(outer));
  });

  testWidgets('a run rounds only its outer corners', (tester) async {
    await pumpLabels(tester, 3);

    expect(segmentRadius(tester, 0), const BorderRadius.only(topLeft: outer, bottomLeft: outer));
    expect(segmentRadius(tester, 1), BorderRadius.zero);
    expect(segmentRadius(tester, 2), const BorderRadius.only(topRight: outer, bottomRight: outer));
  });

  /// The padding actually applied to each segment, in order.
  List<EdgeInsets> segmentPadding(WidgetTester tester) {
    return tester
        .widgetList<Container>(find.descendant(of: find.byType(SegmentedPill), matching: find.byType(Container)))
        .map((c) => c.padding! as EdgeInsets)
        .toList();
  }

  testWidgets('a lone segment keeps its full padding on both edges', (tester) async {
    await pumpLabels(tester, 1);

    expect(segmentPadding(tester).single, PillSegment.labelPadding);
  });

  testWidgets('abutting edges are halved, so a seam spans one outer edge', (tester) async {
    await pumpLabels(tester, 3);

    final List<EdgeInsets> padding = segmentPadding(tester);
    final double edge = PillSegment.labelPadding.left;

    expect(padding[0].left, edge, reason: 'outer');
    expect(padding[0].right, edge / 2, reason: 'abuts segment 1');
    expect(padding[1].left, edge / 2, reason: 'abuts segment 0');
    expect(padding[1].right, edge / 2, reason: 'abuts segment 2');
    expect(padding[2].left, edge / 2, reason: 'abuts segment 1');
    expect(padding[2].right, edge, reason: 'outer');

    // The point of the halving: a seam is no wider than a single outer edge.
    expect(padding[0].right + padding[1].left, edge);
  });

  testWidgets('halving leaves vertical padding alone', (tester) async {
    await pumpLabels(tester, 2);

    for (final EdgeInsets padding in segmentPadding(tester)) {
      expect(padding.top, PillSegment.labelPadding.top);
      expect(padding.bottom, PillSegment.labelPadding.bottom);
    }
  });

  testWidgets('a segment paints an edge a hair brighter than its fill by default', (tester) async {
    await pumpLabels(tester, 1);

    final container = tester.widget<Container>(
      find.descendant(of: find.byType(SegmentedPill), matching: find.byType(Container)),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, fill.withValues(alpha: PillSegment.fillAlpha));
    expect((decoration.border! as Border).top.color, fill.withValues(alpha: PillSegment.edgedBorderAlpha));
  });

  testWidgets('stretching levels a short segment up to the tallest, not to the parent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: Align(
              alignment: Alignment.topLeft,
              child: SegmentedPill(
                stretch: true,
                segments: [
                  PillSegment(color: fill, padding: EdgeInsets.zero, child: Icon(Icons.task_alt, size: 16)),
                  PillSegment(
                    color: fill,
                    child: Text('v1.0', style: PillSegment.labelStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final Finder boxes = find.descendant(of: find.byType(SegmentedPill), matching: find.byType(Container));
    final double iconHeight = tester.getSize(boxes.at(0)).height;
    final double labelHeight = tester.getSize(boxes.at(1)).height;

    // Equal, so the pill's edge has no notch where the segments meet...
    expect(iconHeight, labelHeight);
    // ...and equal to the taller child, not to the parent's 400pt. Stretch
    // without the intrinsics pass would level them at the incoming bound.
    expect(labelHeight, lessThan(40));
  });

  testWidgets('an unstretched pill sizes to its content under a bounded parent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: Align(
              alignment: Alignment.topLeft,
              child: SegmentedPill(
                segments: [
                  PillSegment(
                    color: fill,
                    child: Text('Godot', style: PillSegment.labelStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The parent hands down a bounded 400pt of height, so centering an
    // unstretched segment's child would swallow all of it. (Under the
    // unbounded constraints a Positioned gives, Center shrink-wraps instead
    // and this would not catch the regression.)
    expect(tester.getSize(find.byType(SegmentedPill)).height, lessThan(40));
  });
}
