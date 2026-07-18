import 'dart:async';

import 'package:f95_portal/models/search_query.dart';
import 'package:f95_portal/models/browse_thread.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/widgets/browse_card.dart';
import 'package:f95_portal/widgets/browse_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/metadata_test_utils.dart';
import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

/// Builds a page of [count] distinct threads, titled "P(page) #(n)".
List<BrowseThread> pageOf(int page, int count, {int idOffset = 0}) => [
  for (int i = 0; i < count; i++) createBrowseThread(threadId: page * 1000 + idOffset + i, title: 'P$page #$i'),
];

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

    await pumpTestApp(tester, BrowseList(fetchThreads: delayedFetch));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(createApiResponse());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders thread cards when fetch succeeds', (tester) async {
    final apiResponse = createApiResponse(threads: [createBrowseThread(title: 'TDD Adventure')]);

    successfulFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return apiResponse;
    }

    await pumpTestApp(tester, BrowseList(fetchThreads: successfulFetch));

    await tester.pumpAndSettle();

    expect(find.text('TDD Adventure'), findsOneWidget);
    expect(find.byType(BrowseCard), findsOneWidget);
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

    await pumpTestApp(tester, BrowseList(fetchThreads: failingFetch));

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

    Widget buildList(SearchQuery query) => MaterialApp(
      home: Scaffold(
        body: BrowseList(fetchThreads: recordingFetch, query: query),
      ),
    );

    await tester.pumpWidget(buildList(const SearchQuery()));
    await tester.pumpAndSettle();

    const updated = SearchQuery(search: 'goblin', tags: [225]);
    await tester.pumpWidget(buildList(updated));
    await tester.pumpAndSettle();

    expect(receivedQueries, hasLength(2));
    expect(receivedQueries.last, updated);
  });

  testWidgets('reports the result count after a successful fetch', (tester) async {
    int? reportedCount;

    countFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return createApiResponse(count: 321);
    }

    await pumpTestApp(tester, BrowseList(fetchThreads: countFetch, onCountChanged: (count) => reportedCount = count));
    await tester.pumpAndSettle();

    expect(reportedCount, 321);
  });

  testWidgets('loads the next page when scrolled near the end', (tester) async {
    final requestedPages = <int>[];

    pagedFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      requestedPages.add(page);
      return createApiResponse(threads: pageOf(page, 8), page: page, total: 3, count: 24);
    }

    await pumpTestApp(tester, BrowseList(fetchThreads: pagedFetch));
    await tester.pumpAndSettle();

    // The cache extent may prefetch page 2 with these small test pages, but
    // loading always starts from page 1.
    expect(requestedPages.first, 1);
    expect(find.text('P1 #0'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('P2 #0'), 400);
    await tester.pumpAndSettle();

    // Keep going: the third (final) page loads and its tail is reachable.
    await tester.scrollUntilVisible(find.text('P3 #7'), 400);
    await tester.pumpAndSettle();

    // Pages requested sequentially, exactly once each, never beyond the last.
    expect(requestedPages, [1, 2, 3]);
    expect(find.text('P3 #7'), findsOneWidget);
  });

  testWidgets('does not request beyond the last page', (tester) async {
    final requestedPages = <int>[];

    singlePageFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      requestedPages.add(page);
      return createApiResponse(threads: pageOf(page, 8), page: page, total: 1, count: 8);
    }

    await pumpTestApp(tester, BrowseList(fetchThreads: singlePageFetch));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -30000));
    await tester.pumpAndSettle();

    expect(requestedPages, [1]);
  });

  testWidgets('deduplicates threads that shift between pages', (tester) async {
    overlappingFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      // Page 2 re-serves the last page-1 thread (id 1007) plus new ones.
      final threads = page == 1 ? pageOf(1, 8) : [createBrowseThread(threadId: 1007, title: 'P1 #7'), ...pageOf(2, 4)];
      return createApiResponse(threads: threads, page: page, total: 2, count: 12);
    }

    await pumpTestApp(tester, BrowseList(fetchThreads: overlappingFetch));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -30000));
    await tester.pumpAndSettle();

    // 8 from page 1 + 5 from page 2 minus the 1 duplicate = 12 list items
    // (no load-more footer once the last page is reached).
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.semanticChildCount, 12);
  });

  testWidgets('query change resets back to page one', (tester) async {
    final requests = <(SearchQuery, int)>[];

    recordingFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      requests.add((query, page));
      return createApiResponse(threads: pageOf(page, 8), page: page, total: 3, count: 24);
    }

    Widget buildList(SearchQuery query) => MaterialApp(
      home: Scaffold(
        body: BrowseList(fetchThreads: recordingFetch, query: query),
      ),
    );

    await tester.pumpWidget(buildList(const SearchQuery()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -30000));
    await tester.pumpAndSettle();

    const updated = SearchQuery(search: 'goblin');
    final requestsBeforeChange = requests.length;
    await tester.pumpWidget(buildList(updated));
    await tester.pumpAndSettle();

    // The first request for the new query starts back at page one.
    expect(requests[requestsBeforeChange], (updated, 1));
    expect(find.text('P1 #0'), findsOneWidget);
  });

  testWidgets('renders the header above the first thread and scrolls it away', (tester) async {
    pagedFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return createApiResponse(threads: pageOf(page, 8), page: page, total: 2, count: 16);
    }

    const headerKey = Key('list-header');
    await pumpTestApp(
      tester,
      BrowseList(
        fetchThreads: pagedFetch,
        header: const SizedBox(key: headerKey, height: 44),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(headerKey), findsOneWidget);
    expect(tester.getBottomLeft(find.byKey(headerKey)).dy, lessThanOrEqualTo(tester.getTopLeft(find.text('P1 #0')).dy));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();

    expect(find.byKey(headerKey), findsNothing);
  });

  testWidgets('keeps the header visible when no threads match', (tester) async {
    emptyFetch({
      SearchQuery query = const SearchQuery(),
      int page = 1,
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return createApiResponse(threads: [], count: 0);
    }

    const headerKey = Key('list-header');
    await pumpTestApp(
      tester,
      BrowseList(
        fetchThreads: emptyFetch,
        header: const SizedBox(key: headerKey, height: 44),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(headerKey), findsOneWidget);
    expect(find.text('No threads match this search'), findsOneWidget);
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

    Widget buildList() => MaterialApp(
      home: Scaffold(
        body: BrowseList(
          fetchThreads: countingFetch,
          query: const SearchQuery(search: 'same'),
        ),
      ),
    );

    await tester.pumpWidget(buildList());
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildList());
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
