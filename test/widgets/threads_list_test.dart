import 'dart:async';

import 'package:f95_portal/models/search_category.dart';
import 'package:f95_portal/models/thread_summary.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/widgets/thread_card.dart';
import 'package:f95_portal/widgets/threads_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows loading indicator while fetching', (tester) async {
    final completer = Completer<ApiResponse>();
    delayedFetch({
      String cmd = 'list',
      SearchCategory category = SearchCategory.games,
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) {
      return completer.future;
    }

    await pumpTestApp(tester, ThreadsList(fetchThreads: delayedFetch));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(createApiResponse());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders thread cards when fetch succeeds', (tester) async {
    final apiResponse = createApiResponse(threads: [createThreadSummary(title: 'TDD Adventure')]);

    successfulFetch({
      String cmd = 'list',
      SearchCategory category = SearchCategory.games,
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return apiResponse;
    }

    await pumpTestApp(tester, ThreadsList(fetchThreads: successfulFetch));

    await tester.pumpAndSettle();

    expect(find.text('TDD Adventure'), findsOneWidget);
    expect(find.byType(ThreadCard), findsOneWidget);
  });

  testWidgets('shows error state when fetch fails', (tester) async {
    failingFetch({
      String cmd = 'list',
      SearchCategory category = SearchCategory.games,
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      throw ApiException('boom');
    }

    await pumpTestApp(tester, ThreadsList(fetchThreads: failingFetch));

    await tester.pumpAndSettle();

    expect(find.text('Failed to load threads'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}
