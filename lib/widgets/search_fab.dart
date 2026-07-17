import 'package:flutter/material.dart';

import 'glass_fab.dart';

class SearchFab extends StatelessWidget {
  final ScrollController scrollController;
  final VoidCallback? onSearchPressed;
  final ValueNotifier<bool> bottomNavVisible;

  const SearchFab({super.key, required this.scrollController, this.onSearchPressed, required this.bottomNavVisible});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: bottomNavVisible,
      builder: (context, isVisible, child) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final double baseOffset = isVisible ? 88 : 24;
        final double targetBottom = bottomInset + baseOffset;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          bottom: targetBottom,
          right: 32,
          child: child!,
        );
      },
      child: GlassFab(
        icon: Icons.search,
        tooltip: 'Search Options',
        scrollController: scrollController,
        onPressed: onSearchPressed,
      ),
    );
  }
}
