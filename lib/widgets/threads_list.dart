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

  /// Extra space reserved at the top of the list (e.g. for an overlay bar).
  final double topInset;

  const ThreadsList({
    super.key,
    this.scrollController,
    this.fetchThreads = ApiService.fetchThreads,
    this.query = const SearchQuery(),
    this.onCountChanged,
    this.topInset = 0,
  });

  @override
  State<ThreadsList> createState() => _ThreadsListState();
}

class _ThreadsListState extends State<ThreadsList> {
  List<ThreadSummary> _threads = [];
  bool _isLoading = true;
  String? _error;

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
      });

      final apiResponse = await widget.fetchThreads(query: widget.query);

      if (!mounted) return;
      setState(() {
        _threads = apiResponse.data.threads;
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

  Future<void> _onRefresh() async {
    await _loadThreads();
  }

  void _onThreadTap(ThreadSummary thread) {
    ThreadDetailsModal.show(context, thread);
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: MediaQuery.of(context).padding.add(EdgeInsets.only(top: widget.topInset)),
        itemCount: _threads.length,
        itemBuilder: (context, index) {
          final thread = _threads[index];
          return ThreadCard(
            thread: thread,
            category: widget.query.category,
            onTap: () => _onThreadTap(thread),
          );
        },
      ),
    );
  }
}
