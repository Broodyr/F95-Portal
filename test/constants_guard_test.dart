import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Values that define the app's look or its cross-file behavior live in
/// lib/constants.dart, not inlined at each call site (see AGENTS.md). These
/// guards cover the ones that were duplicated widely enough that drift would
/// be invisible: the two glass blur tiers and the pill radius.
///
/// Deliberate exceptions carry their own named constant instead, because the
/// value means something different there and must not move when the shared
/// one is tuned.
const _blurAllowed = {
  'lib/constants.dart',
  // Censoring blur, not chrome: tuning the glass must not un-censor covers.
  'lib/widgets/sfw_blur.dart',
};

const _pillAllowed = {'lib/constants.dart'};

Iterable<File> _libDartFiles() =>
    Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void _expectNoMatch({required RegExp pattern, required Set<String> allowed, required String reason}) {
  final offenders = <String>[];
  for (final file in _libDartFiles()) {
    final path = file.path.replaceAll('\\', '/');
    if (allowed.contains(path)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        offenders.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  expect(offenders, isEmpty, reason: '$reason Offenders:\n${offenders.join('\n')}');
}

void main() {
  test('glass blur sigmas come from AppBlur', () {
    _expectNoMatch(
      pattern: RegExp(r'sigma[XY]: *(24|15)\b'),
      allowed: _blurAllowed,
      reason:
          'Inline glass blur sigma found. Use AppBlur.panel (sheets and '
          'panels) or AppBlur.bar (bars and toasts) from lib/constants.dart.',
    );
  });

  test('pill radius comes from AppRadii', () {
    _expectNoMatch(
      pattern: RegExp(r'circular\(999\b'),
      allowed: _pillAllowed,
      reason:
          'Inline pill radius found. Use AppRadii.pill from '
          'lib/constants.dart.',
    );
  });
}
