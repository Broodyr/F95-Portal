import 'package:flutter/material.dart';

import '../models/search_category.dart';
import '../models/thread_summary.dart';
import '../services/api_service.dart';
import 'thread_card.dart';
import 'thread_details_modal.dart';

typedef FetchThreadsCallback =
    Future<ApiResponse> Function({
      String cmd,
      SearchCategory category,
      int page,
      List<int> noprefixes,
      List<int> tags,
      List<int> notags,
      String sort,
      int rows,
      bool fallbackToMockOnError,
    });

class ThreadsList extends StatefulWidget {
  final ScrollController? scrollController;
  final FetchThreadsCallback fetchThreads;
  final SearchCategory category;

  const ThreadsList({
    super.key,
    this.scrollController,
    this.fetchThreads = ApiService.fetchThreads,
    this.category = SearchCategory.games,
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
    if (oldWidget.category != widget.category) {
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

      final apiResponse = await widget.fetchThreads(category: widget.category);

      if (!mounted) return;
      setState(() {
        _threads = apiResponse.data.threads;
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: MediaQuery.of(context).padding,
        itemCount: _threads.length,
        itemBuilder: (context, index) {
          final thread = _threads[index];
          return ThreadCard(thread: thread, onTap: () => _onThreadTap(thread));
        },
      ),
    );
  }
}
