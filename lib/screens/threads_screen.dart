import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/search_query.dart';
import '../services/settings_service.dart';
import '../widgets/active_filters_bar.dart';
import '../widgets/search_fab.dart';
import '../widgets/thread_details_modal.dart';
import '../widgets/search_options_modal.dart';
import '../widgets/threads_list.dart';
//import '../widgets/noisy_background.dart';

class ThreadsScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final ValueNotifier<bool> bottomNavVisible;

  const ThreadsScreen({super.key, this.scrollController, required this.bottomNavVisible});

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  // Use external ScrollController if provided, otherwise create internal one
  static const double _filtersBarHeight = 56;

  late final ScrollController _scrollController;
  late SearchQuery _activeQuery;
  int? _resultCount;

  @override
  void initState() {
    super.initState();
    _activeQuery = SettingsService.instance.settings.defaultQuery;
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    // Only dispose if we created the controller internally
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _scrollListener() {
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse) {
      if (widget.bottomNavVisible.value) {
        widget.bottomNavVisible.value = false;
      }
    } else if (direction == ScrollDirection.forward) {
      if (!widget.bottomNavVisible.value) {
        widget.bottomNavVisible.value = true;
      }
    }
  }

  void _onSearchPressed() async {
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: 0.65)),
              child: SearchOptionsModal(initialQuery: _activeQuery),
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    _onQueryChanged(result);
  }

  void _onQueryChanged(SearchQuery query) {
    setState(() {
      if (query != _activeQuery) {
        _resultCount = null;
      }
      _activeQuery = query;
    });
    // Feed the recently-used-tags suggestion source; fire and forget.
    SettingsService.instance.recordTagUse(query.tags);
  }

  void _onTagSelected(ThreadTagSelection selection) {
    final updated = selection.replace
        ? _activeQuery.replacedWithTag(selection.tagId)
        : _activeQuery.withTagAdded(selection.tagId);

    if (!selection.replace && !updated.tags.contains(selection.tagId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tag limit reached (${SearchQuery.maxTagsPerDirection}).')));
      return;
    }

    _onQueryChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final bool showFiltersBar = _activeQuery.hasActiveFilters;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          //PreRenderedNoisyBackground(child: Container()),
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.5), // Center slightly above the middle
                radius: 1.5, // A large radius to make the gradient very soft
                colors: [Color.fromARGB(255, 24, 24, 24), Color.fromARGB(255, 8, 8, 8)],
              ),
            ),
          ),
          ThreadsList(
            scrollController: _scrollController,
            query: _activeQuery,
            topInset: showFiltersBar ? _filtersBarHeight : 0,
            onCountChanged: (count) => setState(() => _resultCount = count),
            onTagSelected: _onTagSelected,
          ),
          if (showFiltersBar)
            Positioned(
              top: 0,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ActiveFiltersBar(
                    query: _activeQuery,
                    resultCount: _resultCount,
                    onQueryChanged: _onQueryChanged,
                    onClearAll: () => _onQueryChanged(SettingsService.instance.settings.defaultQuery),
                  ),
                ),
              ),
            ),
          SearchFab(
            scrollController: _scrollController,
            onSearchPressed: _onSearchPressed,
            bottomNavVisible: widget.bottomNavVisible,
          ),
        ],
      ),
    );
  }
}
