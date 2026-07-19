import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../models/search_query.dart';
import '../models/browse_thread.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'browse_card.dart';
import 'browse_details_sheet.dart';

typedef FetchThreadsCallback =
    Future<ApiResponse> Function({SearchQuery query, int page, int rows, bool fallbackToMockOnError});

class BrowseList extends StatefulWidget {
  final ScrollController? scrollController;
  final FetchThreadsCallback fetchThreads;
  final SearchQuery query;

  /// Reports the server-side total result count after each successful load.
  final ValueChanged<int>? onCountChanged;

  /// Called when the user picks a tag inside the details sheet.
  final ValueChanged<BrowseTagSelection>? onTagSelected;

  /// Rendered as the first list item, scrolling with the content (also kept
  /// visible above the loading/error/empty states).
  final Widget? header;

  const BrowseList({
    super.key,
    this.scrollController,
    this.fetchThreads = ApiService.fetchThreads,
    this.query = const SearchQuery(),
    this.onCountChanged,
    this.onTagSelected,
    this.header,
  });

  @override
  State<BrowseList> createState() => _BrowseListState();
}

class _BrowseListState extends State<BrowseList> {
  /// Start fetching the next page when an item this close to the end builds.
  static const int _loadMoreThreshold = 5;

  List<BrowseThread> _threads = [];
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
  void didUpdateWidget(BrowseList oldWidget) {
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

  Future<void> _onThreadTap(BrowseThread thread) async {
    final selection = await BrowseDetailsSheet.show(context, thread, category: widget.query.category);
    if (selection != null) {
      widget.onTagSelected?.call(selection);
    }
  }

  /// Keeps the header (e.g. the active-filters bar) reachable while a
  /// non-list state fills the body, so filters can still be cleared when a
  /// search matches nothing or fails.
  Widget _withHeader(BuildContext context, Widget body) {
    final header = widget.header;
    if (header == null) return body;
    return Padding(
      padding: MediaQuery.of(context).padding,
      child: Column(
        children: [
          header,
          Expanded(child: body),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _withHeader(
        context,
        Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }

    if (_error != null) {
      return _withHeader(
        context,
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.of(context).mutedForeground),
              const SizedBox(height: 16),
              Text('Failed to load threads', style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: AppColors.of(context).hintText, fontSize: 14),
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
        ),
      );
    }

    if (_threads.isEmpty) {
      return _withHeader(
        context,
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: AppColors.of(context).mutedForeground),
              const SizedBox(height: 16),
              Text(
                'No threads match this search',
                style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final bool showFooter = _hasMore || _loadMoreError != null;
    final int headerCount = widget.header != null ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        // Build about a screen's worth of offscreen cards so their cover
        // images (low-res + HD upgrade) start loading before they scroll in.
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
        padding: MediaQuery.of(context).padding,
        itemCount: headerCount + _threads.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < headerCount) {
            return widget.header;
          }
          final threadIndex = index - headerCount;
          if (threadIndex >= _threads.length) {
            return _buildFooter(context);
          }

          if (threadIndex >= _threads.length - _loadMoreThreshold &&
              _hasMore &&
              !_isLoadingMore &&
              _loadMoreError == null) {
            _scheduleLoadMore();
          }

          final thread = _threads[threadIndex];
          return BrowseCard(thread: thread, category: widget.query.category, onTap: () => _onThreadTap(thread));
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
            Text('Failed to load more', style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 14)),
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
