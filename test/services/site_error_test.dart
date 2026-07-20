import 'dart:io';

import 'package:f95_portal/services/site_error.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('parseSiteErrorMessage', () {
    // Two content types, two status codes, one template — which is why this
    // lives outside either parser rather than in the profile one.
    test('reads the wording off a profile the member limited (403)', () {
      expect(
        parseSiteErrorMessage(fixture('profile_limited_403.htm')),
        'This member limits who may view their full profile.',
      );
    });

    test('reads the wording off a forum that does not exist (404)', () {
      expect(parseSiteErrorMessage(fixture('forum_404.htm')), 'The requested forum could not be found.');
    });

    // Every page carries these in its header, and a loaded profile has one
    // per lazy tab pane. Matching any of them would put "JavaScript is
    // disabled" on screen as though it were the error.
    test('steps over the notices every page carries', () {
      expect(parseSiteErrorMessage(fixture('profile_gugatron.htm')), isNull);
      expect(parseSiteErrorMessage(fixture('forum_home.htm')), isNull);
    });

    test('finds nothing in markup it does not recognize', () {
      expect(parseSiteErrorMessage('<html><body><p>502 Bad Gateway</p></body></html>'), isNull);
    });
  });
}
