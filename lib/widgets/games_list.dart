import 'package:flutter/material.dart';
import '../models/game_thread.dart';
import '../services/api_service.dart';
import 'game_card.dart';
import 'game_details_modal.dart';

typedef FetchGamesCallback = Future<ApiResponse> Function({
  String cmd,
  String cat,
  int page,
  List<int> noprefixes,
  List<int> tags,
  List<int> notags,
  String sort,
  int rows,
  bool fallbackToMockOnError,
});

class GamesList extends StatefulWidget {
  final ScrollController? scrollController;
  final FetchGamesCallback fetchGames;

  const GamesList({
    super.key,
    this.scrollController,
    this.fetchGames = ApiService.fetchGames,
  });

  @override
  State<GamesList> createState() => _GamesListState();
}

class _GamesListState extends State<GamesList> {
  List<GameThread> _games = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final apiResponse = await widget.fetchGames();

      if (!mounted) return;
      setState(() {
        _games = apiResponse.data.games;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadGames();
  }

  void _onGameTap(GameThread game) {
    GameDetailsModal.show(context, game);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load games',
              style: TextStyle(color: Colors.grey[400], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGames,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).snackBarTheme.backgroundColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: MediaQuery.of(context).padding,
        itemCount: _games.length,
        itemBuilder: (context, index) {
          final game = _games[index];
          return GameCard(game: game, onTap: () => _onGameTap(game));
        },
      ),
    );
  }
}
