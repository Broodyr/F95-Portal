import 'package:f95_portal/utils/image_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toHdImageUrl', () {
    test('converts preview host to attachments host', () {
      expect(
        toHdImageUrl('https://preview.f95zone.to/2023/02/2416942_main_menu.png'),
        'https://attachments.f95zone.to/2023/02/2416942_main_menu.png',
      );
    });

    test('strips the /thumb/ segment from attachment thumbnails', () {
      expect(
        toHdImageUrl('https://attachments.f95zone.to/2023/02/thumb/2416942_main_menu.png'),
        'https://attachments.f95zone.to/2023/02/2416942_main_menu.png',
      );
    });

    test('returns null for a full attachments URL (already HD)', () {
      expect(toHdImageUrl('https://attachments.f95zone.to/2023/02/2416942_main_menu.png'), isNull);
    });

    test('returns null for non-f95 hosts', () {
      expect(toHdImageUrl('https://i.imgur.com/abc123.png'), isNull);
      expect(toHdImageUrl('https://example.com/preview.f95zone.to/fake.png'), isNull);
    });

    test('returns null for empty and non-http input', () {
      expect(toHdImageUrl(''), isNull);
      expect(toHdImageUrl('data:image/png;base64,xyz'), isNull);
    });
  });

  group('toPreviewImageUrl', () {
    test('converts a full attachments URL to the preview host', () {
      expect(
        toPreviewImageUrl('https://attachments.f95zone.to/2023/02/2416942_main_menu.png'),
        'https://preview.f95zone.to/2023/02/2416942_main_menu.png',
      );
    });

    test('returns null for attachment thumbnails (already low quality)', () {
      expect(toPreviewImageUrl('https://attachments.f95zone.to/2023/02/thumb/2416942_main_menu.png'), isNull);
    });

    test('returns null for preview URLs (already low quality)', () {
      expect(toPreviewImageUrl('https://preview.f95zone.to/2023/02/2416942_main_menu.png'), isNull);
    });

    test('returns null for non-f95 hosts', () {
      expect(toPreviewImageUrl('https://i.imgur.com/abc123.png'), isNull);
    });
  });
}
