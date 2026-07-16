import 'package:f95_portal/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> printed;
  late FlutterExceptionHandler? originalOnError;

  setUp(() {
    printed = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
    originalOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = originalOnError);
  });

  test('image load failures collapse to a single console line', () {
    installConsoleNoiseFilter();

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: Exception('Invalid statusCode: 404, uri: https://attachments.f95zone.to/x.png'),
        library: 'image resource service',
      ),
    );

    expect(printed, hasLength(1));
    expect(printed.single, contains('404'));
    expect(printed.single, contains('attachments.f95zone.to/x.png'));
  });

  test('other errors pass through to the previous handler', () {
    FlutterErrorDetails? forwarded;
    FlutterError.onError = (details) => forwarded = details;

    installConsoleNoiseFilter();

    final details = FlutterErrorDetails(exception: Exception('boom'), library: 'widgets library');
    FlutterError.onError!(details);

    expect(forwarded, same(details));
    expect(printed, isEmpty);
  });
}
