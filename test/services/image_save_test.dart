import 'dart:typed_data';

import 'package:f95_portal/services/image_save_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// An ISOBMFF header carrying [brand], the shape every AVIF file opens
/// with: a box length, the 'ftyp' box type, then the brand.
Uint8List header(String brand, {int trailing = 0}) {
  return Uint8List.fromList([
    0, 0, 0, 32, // box length
    ...'ftyp'.codeUnits,
    ...brand.codeUnits,
    ...List.filled(trailing, 0),
  ]);
}

void main() {
  group('isAvif', () {
    test('recognises a still AVIF', () {
      expect(isAvif(header('avif')), isTrue);
    });

    test('recognises an animated AVIF', () {
      expect(isAvif(header('avis')), isTrue);
    });

    // The whole reason this sniffs bytes: f95 re-encodes attachments to
    // AVIF and leaves the .png/.jpg name on them, so a save that trusted
    // the extension would file AVIF data as a PNG and the gallery would
    // store an entry it cannot decode.
    test('sees AVIF regardless of what the file is named', () {
      final avifServedAsPng = header('avif', trailing: 4096);
      expect(isAvif(avifServedAsPng), isTrue);
    });

    test('leaves a real PNG alone', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 0)]);
      expect(isAvif(png), isFalse);
    });

    test('leaves a real JPEG alone', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);
      expect(isAvif(jpeg), isFalse);
    });

    // A truncated download must answer "not AVIF", not throw out of the
    // save and turn into a generic failure.
    test('survives bytes shorter than the header it looks at', () {
      expect(isAvif(Uint8List(0)), isFalse);
      expect(isAvif(Uint8List.fromList([0, 0, 0])), isFalse);
    });
  });

  group('saveFileName', () {
    test('uses the name from the URL, without its extension', () {
      expect(saveFileName('https://attachments.f95zone.to/2024/01/screenshot_01.png'), 'screenshot_01');
    });

    test('keeps dots inside the name', () {
      expect(saveFileName('https://example.com/scene.v2.final.jpg'), 'scene.v2.final');
    });

    test('handles a name with no extension', () {
      expect(saveFileName('https://example.com/12345'), '12345');
    });

    test('falls back when the URL carries no name', () {
      expect(saveFileName('https://example.com/'), 'image');
      expect(saveFileName('https://example.com'), 'image');
    });

    test('does not return a bare extension as the name', () {
      expect(saveFileName('https://example.com/.png'), 'image');
    });

    // The name becomes a real file on the device, so a segment carrying
    // something a file system won't take must not fail the save.
    test('replaces characters that are not safe in a file name', () {
      expect(saveFileName('https://example.com/a:b*c|d.png'), 'a_b_c_d');
      expect(saveFileName('https://example.com/%2Fetc%2Fpasswd'), '_etc_passwd');
    });

    test('falls back when nothing survives sanitising', () {
      expect(saveFileName('https://example.com/%2F%2F.png'), 'image');
    });
  });
}
