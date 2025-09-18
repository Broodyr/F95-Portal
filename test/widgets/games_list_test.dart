import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:f95_portal/models/game_thread.dart';
import 'package:f95_portal/services/api_service.dart';
import 'package:f95_portal/widgets/game_card.dart';
import 'package:f95_portal/widgets/games_list.dart';

import '../helpers/test_data.dart';
import '../helpers/widget_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows loading indicator while fetching', (tester) async {
    final completer = Completer<ApiResponse>();
    final FetchGamesCallback delayedFetch = ({
      String cmd = 'list',
      String cat = 'games',
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) {
      return completer.future;
    };

    await pumpTestApp(
      tester,
      GamesList(fetchGames: delayedFetch),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(createApiResponse());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders game cards when fetch succeeds', (tester) async {
    final apiResponse = createApiResponse(
      games: [
        createGameThread(title: 'TDD Adventure'),
      ],
    );

    final FetchGamesCallback successfulFetch = ({
      String cmd = 'list',
      String cat = 'games',
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      return apiResponse;
    };

    await pumpTestApp(
      tester,
      GamesList(fetchGames: successfulFetch),
    );

    await tester.pumpAndSettle();

    expect(find.text('TDD Adventure'), findsOneWidget);
    expect(find.byType(GameCard), findsOneWidget);
  });

  testWidgets('shows error state when fetch fails', (tester) async {
    final FetchGamesCallback failingFetch = ({
      String cmd = 'list',
      String cat = 'games',
      int page = 1,
      List<int> noprefixes = const [2, 7, 13],
      List<int> tags = const [191],
      List<int> notags = const [173, 174, 324, 522],
      String sort = 'date',
      int rows = 90,
      bool fallbackToMockOnError = false,
    }) async {
      throw ApiException('boom');
    };

    await pumpTestApp(
      tester,
      GamesList(fetchGames: failingFetch),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to load games'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}