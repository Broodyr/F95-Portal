import 'dart:async';

import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/models/thread_summary.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/widgets/thread_card.dart';
import 'package:f95_portal/widgets/threads_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    loadAndInstallMetadata();
  });

  testWidgets('shows loading indicator while fetching', (tester) async {
    final completer = Completer<ApiResponse>();
    delayedFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
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
      SearchQuery query = const SearchQuery(),
      int page = 1,
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
      SearchQuery query = const SearchQuery(),
      int page = 1,
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

  testWidgets('refetches with the new query when it changes', (tester) async {
    final receivedQueries = <SearchQuery>[];

    recordingFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      receivedQueries.add(query);
      return createApiResponse();
    }

    Widget buildList(SearchQuery query) =>
        MaterialApp(home: Scaffold(body: ThreadsList(fetchThreads: recordingFetch, query: query)));

    await tester.pumpWidget(buildList(const SearchQuery()));
    await tester.pumpAndSettle();

    const updated = SearchQuery(search: 'goblin', tags: [225]);
    await tester.pumpWidget(buildList(updated));
    await tester.pumpAndSettle();

    expect(receivedQueries, hasLength(2));
    expect(receivedQueries.last, updated);
  });

  testWidgets('does not refetch when rebuilt with an equal query', (tester) async {
    int calls = 0;

    countingFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      calls++;
      return createApiResponse();
    }

    Widget buildList() =>
        MaterialApp(home: Scaffold(body: ThreadsList(fetchThreads: countingFetch, query: const SearchQuery(search: 'same'))));

    await tester.pumpWidget(buildList());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildList());
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
