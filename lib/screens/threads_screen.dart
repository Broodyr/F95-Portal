import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/search_query.dart';
import '../widgets/search_fab.dart';
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
  late final ScrollController _scrollController;
  SearchQuery _activeQuery = const SearchQuery();

  @override
  void initState() {
    super.initState();
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
              decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: 0.32)),
              child: SearchOptionsModal(initialQuery: _activeQuery),
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _activeQuery = result;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          ThreadsList(scrollController: _scrollController, query: _activeQuery),
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
