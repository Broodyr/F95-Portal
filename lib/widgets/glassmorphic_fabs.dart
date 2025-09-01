import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';

class GlassmorphicFabs extends StatelessWidget {
  final ScrollController scrollController;
  final VoidCallback? onFilterPressed;
  final VoidCallback? onSearchPressed;
  final ValueNotifier<bool> bottomNavVisible;

  const GlassmorphicFabs({
    super.key,
    required this.scrollController,
    this.onFilterPressed,
    this.onSearchPressed,
    required this.bottomNavVisible,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: bottomNavVisible,
      builder: (context, isVisible, child) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          bottom: isVisible ? 120 : 56,
          right: 32,
          child: child!,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PassThroughFab(
            scrollController: scrollController,
            icon: Icons.filter_alt_outlined,
            backgroundColor: const Color(0xFF404040).withValues(alpha: 0.5),
            hoverBackgroundColor: const Color(
              0xFF404040,
            ).withValues(alpha: 0.7),
            tooltip: 'Filters',
            onPressed: onFilterPressed,
          ),

          const SizedBox(height: 12),

          _PassThroughFab(
            scrollController: scrollController,
            icon: Icons.tune,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.5),
            hoverBackgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.7),
            tooltip: 'Search options',
            onPressed: onSearchPressed,
          ),
        ],
      ),
    );
  }
}

class _PassThroughFab extends StatefulWidget {
  final ScrollController scrollController;
  final IconData icon;
  final Color backgroundColor;
  final Color hoverBackgroundColor;
  final String tooltip;
  final VoidCallback? onPressed;

  const _PassThroughFab({
    required this.scrollController,
    required this.icon,
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

  @override
  Widget build(BuildContext context) {
    Color currentBackgroundColor = _isHovered || _isPressed
        ? widget.hoverBackgroundColor
        : widget.backgroundColor;

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
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: currentBackgroundColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.2),
                    width: 1,
                  ),
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
