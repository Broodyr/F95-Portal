import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'glass_aware.dart';

/// The app's floating action button: a primary-tinted 56pt glass circle
/// (real backdrop blur when glass effects are on, near-opaque fill when
/// off). Vertical drags pass through to [scrollController] so the list
/// keeps scrolling under the button.
class GlassFab extends StatefulWidget {
  static const double size = 56;

  final IconData icon;
  final String tooltip;
  final ScrollController scrollController;
  final VoidCallback? onPressed;

  const GlassFab({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.scrollController,
    this.onPressed,
  });

  @override
  State<GlassFab> createState() => _GlassFabState();
}

class _GlassFabState extends State<GlassFab> {
  bool _isHovered = false;
  bool _isPressed = false;

  Drag? _drag;

  Widget _maybeBlur({required bool glass, required Widget child}) {
    if (!glass) return child;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: child);
  }

  @override
  Widget build(BuildContext context) {
    return GlassAware(
      builder: (context, glass) {
        final primary = Theme.of(context).colorScheme.primary;
        final backgroundColor = primary.withValues(alpha: glass ? 0.5 : 0.95);
        final hoverBackgroundColor = primary.withValues(alpha: glass ? 0.7 : 1.0);
        final currentBackgroundColor = _isHovered || _isPressed ? hoverBackgroundColor : backgroundColor;

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
                borderRadius: BorderRadius.circular(GlassFab.size / 2),
                child: _maybeBlur(
                  glass: glass,
                  child: Container(
                    width: GlassFab.size,
                    height: GlassFab.size,
                    decoration: BoxDecoration(
                      color: currentBackgroundColor,
                      borderRadius: BorderRadius.circular(GlassFab.size / 2),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 1),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
