import 'package:flutter/material.dart';

import '../models/search_query.dart';
import '../models/thread_summary.dart';
import '../services/api_service.dart';
import 'thread_card.dart';
import 'thread_details_modal.dart';

typedef FetchThreadsCallback =
    Future<ApiResponse> Function({SearchQuery query, int page, int rows, bool fallbackToMockOnError});

class ThreadsList extends StatefulWidget {
  final ScrollController? scrollController;
  final FetchThreadsCallback fetchThreads;
  final SearchQuery query;

  /// Reports the server-side total result count after each successful load.
  final ValueChanged<int>? onCountChanged;

  /// Called when the user picks a tag inside the details modal.
  final ValueChanged<ThreadTagSelection>? onTagSelected;

  /// Extra space reserved at the top of the list (e.g. for an overlay bar).
  final double topInset;

  const ThreadsList({
    super.key,
    this.scrollController,
    this.fetchThreads = ApiService.fetchThreads,
    this.query = const SearchQuery(),
    this.onCountChanged,
    this.onTagSelected,
    this.topInset = 0,
  });

  @override
  State<ThreadsList> createState() => _ThreadsListState();
}

class _ThreadsListState extends State<ThreadsList> {
  /// Start fetching the next page when an item this close to the end builds.
  static const int _loadMoreThreshold = 5;

  List<ThreadSummary> _threads = [];
  bool _isLoading = true;
  String? _error;

  int _page = 1;
  int _totalPages = 1;
  bool _isLoadingMore = false;
  String? _loadMoreError;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  @override
  void didUpdateWidget(ThreadsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _loadThreads();
    }
  }

  Future<void> _loadThreads() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
        _loadMoreError = null;
        _page = 1;
        _totalPages = 1;
      });

      final apiResponse = await widget.fetchThreads(query: widget.query, page: 1);

      if (!mounted) return;
      setState(() {
        _threads = apiResponse.data.threads;
        _totalPages = apiResponse.data.pagination.total;
        _isLoading = false;
      });
      widget.onCountChanged?.call(apiResponse.data.count);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final nextPage = _page + 1;
      final apiResponse = await widget.fetchThreads(query: widget.query, page: nextPage);

      if (!mounted) return;
      setState(() {
        // New threads posted between requests shift pages, so the next page
        // can re-serve threads we already have.
        final knownIds = {for (final t in _threads) t.threadId};
        _threads = [..._threads, ...apiResponse.data.threads.where((t) => !knownIds.contains(t.threadId))];
        _page = nextPage;
        _totalPages = apiResponse.data.pagination.total;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = e.toString();
      });
    }
  }

  void _scheduleLoadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _onRefresh() async {
    await _loadThreads();
  }

  Future<void> _onThreadTap(ThreadSummary thread) async {
    final selection = await ThreadDetailsModal.show(context, thread, category: widget.query.category);
    if (selection != null) {
      widget.onTagSelected?.call(selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Failed to load threads', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadThreads,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).snackBarTheme.backgroundColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No threads match this search', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
          ],
        ),
      );
    }

    final bool showFooter = _hasMore || _loadMoreError != null;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: MediaQuery.of(context).padding.add(EdgeInsets.only(top: widget.topInset)),
        itemCount: _threads.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _threads.length) {
            return _buildFooter(context);
          }

          if (index >= _threads.length - _loadMoreThreshold && _hasMore && !_isLoadingMore && _loadMoreError == null) {
            _scheduleLoadMore();
          }

          final thread = _threads[index];
          return ThreadCard(thread: thread, category: widget.query.category, onTap: () => _onThreadTap(thread));
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text('Failed to load more', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadMore, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
