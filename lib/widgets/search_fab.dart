import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'glass_aware.dart';

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
      child: GlassAware(
        builder: (context, glass) => _PassThroughFab(
          scrollController: scrollController,
          icon: Icons.search,
          glass: glass,
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: glass ? 0.5 : 0.95),
          hoverBackgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: glass ? 0.7 : 1.0),
          tooltip: 'Search Options',
          onPressed: onSearchPressed,
        ),
      ),
    );
  }
}

class _PassThroughFab extends StatefulWidget {
  final ScrollController scrollController;
  final IconData icon;
  final bool glass;
  final Color backgroundColor;
  final Color hoverBackgroundColor;
  final String tooltip;
  final VoidCallback? onPressed;

  const _PassThroughFab({
    required this.scrollController,
    required this.icon,
    required this.glass,
    required this.backgroundColor,
    required this.hoverBackgroundColor,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_PassThroughFab> createState() => _PassThroughFabState();
}

class _PassThroughFabState extends State<_PassThroughFab> {
  bool _isHovered = false;
  bool _isPressed = false;

  Drag? _drag;

  Widget _maybeBlur({required Widget child}) {
    if (!widget.glass) return child;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: child);
  }

  @override
  Widget build(BuildContext context) {
    Color currentBackgroundColor = _isHovered || _isPressed ? widget.hoverBackgroundColor : widget.backgroundColor;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        // We need opaque to ensure this widget receives all gestures.
        behavior: HitTestBehavior.opaque,

        // Handle button tap functionality
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () {
          setState(() => _isPressed = false);
          _drag?.cancel(); // Also cancel the drag if the tap is cancelled.
        },

        onVerticalDragStart: (DragStartDetails details) {
          if (widget.scrollController.hasClients) {
            _drag = widget.scrollController.position.drag(details, () {
              _drag = null;
            });
          }
        },
        onVerticalDragUpdate: (DragUpdateDetails details) {
          _drag?.update(details);
        },
        onVerticalDragEnd: (DragEndDetails details) {
          _drag?.end(details);
        },

        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: _maybeBlur(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: currentBackgroundColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 1),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
