import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpTestApp(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

/// Rendered font size of the paragraph matched by [finder], after all text
/// scaling has been applied.
double effectiveFontSize(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject(finder) as RenderParagraph;
  return paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
}
