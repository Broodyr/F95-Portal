import 'dart:typed_data';

import 'package:f95_portal/widgets/remote_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smallest valid transparent 1x1 PNG.
final Uint8List kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int loads;

  setUp(() {
    loads = 0;
    final original = RemoteImage.loadProvider;
    RemoteImage.loadProvider = (url, decodeWidth, decodeHeight) async {
      loads++;
      return MemoryImage(kTransparentPng);
    };
    addTearDown(() => RemoteImage.loadProvider = original);
  });

  testWidgets('a resolved provider reaches the Image widget (the resolve future completes)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteImage(
          url: 'https://example.com/${DateTime.now().microsecondsSinceEpoch}-a.png',
          placeholder: (context) => const ColoredBox(color: Colors.grey, key: Key('loading')),
        ),
      ),
    );
    // No Image while the loader is pending — just the placeholder.
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const Key('loading')), findsOneWidget);

    await tester.pumpAndSettle();

    // The resolve future completed and the Image took over (pixel decode
    // itself doesn't finish under fake async; widget presence is the
    // regression signal for a hung resolve).
    expect(find.byType(Image), findsOneWidget);
    expect(loads, 1);
  });

  testWidgets('widgets showing the same url concurrently share one load', (tester) async {
    final url = 'https://example.com/${DateTime.now().microsecondsSinceEpoch}-b.png';
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(height: 50, child: RemoteImage(url: url)),
            SizedBox(height: 50, child: RemoteImage(url: url)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNWidgets(2));
    expect(loads, 1);
  });
}
