import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/search_query.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/active_filters_bar.dart';
import '../widgets/app_toast.dart';
import '../widgets/search_fab.dart';
import '../widgets/thread_details_modal.dart';
import '../widgets/search_options_modal.dart';
import '../widgets/threads_list.dart';
//import '../widgets/noisy_background.dart';

class ThreadsScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final ValueNotifier<bool> bottomNavVisible;
  final FetchThreadsCallback fetchThreads;

  const ThreadsScreen({
    super.key,
    this.scrollController,
    required this.bottomNavVisible,
    this.fetchThreads = ApiService.fetchThreads,
  });

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  // Use external ScrollController if provided, otherwise create internal one
  late final ScrollController _scrollController;
  late SearchQuery _activeQuery;
  int? _resultCount;

  // Captured so add/removeListener target the same service even if the
  // singleton is swapped (tests do this).
  late final SettingsService _settingsService;
  late SearchQuery _appliedDefault;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService.instance;
    _appliedDefault = _settingsService.settings.defaultQuery;
    _activeQuery = _appliedDefault;
    _settingsService.addListener(_onSettingsChanged);
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    _scrollController.removeListener(_scrollListener);
    // Only dispose if we created the controller internally
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  /// The screen lives in an IndexedStack, so defaults edited on the Settings
  /// tab must be picked up here rather than in a fresh initState. Adopt the
  /// new baseline only while the search still matches the old one; a search
  /// the user customized is left alone.
  void _onSettingsChanged() {
    final newDefault = _settingsService.settings.defaultQuery;
    if (newDefault == _appliedDefault) return;
    if (_activeQuery == _appliedDefault) {
      setState(() {
        _resultCount = null;
        _activeQuery = newDefault;
      });
    }
    _appliedDefault = newDefault;
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
        final bool glass = SettingsService.instance.settings.glassEffects;
        final content = DecoratedBox(
          decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
          child: SearchOptionsModal(initialQuery: _activeQuery),
        );
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: content) : content,
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
      AppToast.show(context, 'Tag limit reached (${SearchQuery.maxTagsPerDirection}).');
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
            fetchThreads: widget.fetchThreads,
            query: _activeQuery,
            header: showFiltersBar
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ActiveFiltersBar(
                      query: _activeQuery,
                      resultCount: _resultCount,
                      onQueryChanged: _onQueryChanged,
                      onClearAll: () => _onQueryChanged(SettingsService.instance.settings.defaultQuery),
                    ),
                  )
                : null,
            onCountChanged: (count) => setState(() => _resultCount = count),
            onTagSelected: _onTagSelected,
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
