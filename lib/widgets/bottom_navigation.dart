import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';

import '../constants.dart';
import 'glass_aware.dart';
import 'sliding_reveal.dart';

class CustomBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final ScrollController scrollController;

  const CustomBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return GlassAware(
      builder: (context, glass) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _maybeBlur(
              glass,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // Handle vertical scrolling on the nav bar background
                onVerticalDragUpdate: (details) {
                  if (scrollController.hasClients) {
                    double newOffset = scrollController.offset - details.delta.dy;
                    newOffset = newOffset.clamp(
                      scrollController.position.minScrollExtent,
                      scrollController.position.maxScrollExtent,
                    );
                    scrollController.jumpTo(newOffset);
                  }
                },
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: glass ? 0.4 : 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4)),
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 32, offset: const Offset(0, 8)),
                    ],
                  ),
                  // The web build's first frame can lay out at a sliver of
                  // the real window width before it settles; skip the items
                  // for such frames instead of overflowing (the four 40px
                  // items need 160px).
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 160) return const SizedBox();
                      const itemCount = 4;
                      return Stack(
                        children: [
                          // One shared highlight circle that slides between
                          // equal-width segments, mirroring SegmentedSelector,
                          // instead of each item fading its own background.
                          Positioned.fill(
                            child: AnimatedAlign(
                              key: const Key('nav-highlight'),
                              duration: Motion.duration,
                              curve: Motion.curve,
                              alignment: Alignment(-1 + 2 * currentIndex / (itemCount - 1), 0),
                              child: const FractionallySizedBox(
                                widthFactor: 1 / itemCount,
                                heightFactor: 1,
                                child: Center(child: _PulsingHighlight()),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              // Browse covers games/comics/animations/assets, so a
                              // category-neutral compass beats the old gamepad; the
                              // search FAB keeps the magnifier.
                              _buildNavItem(
                                icon: Icons.explore_outlined,
                                activeIcon: Icons.explore,
                                index: 0,
                                isActive: currentIndex == 0,
                              ),
                              _buildNavItem(
                                icon: Icons.forum_outlined,
                                activeIcon: Icons.forum,
                                index: 1,
                                isActive: currentIndex == 1,
                              ),
                              _buildNavItem(
                                icon: Icons.settings_outlined,
                                activeIcon: Icons.settings,
                                index: 2,
                                isActive: currentIndex == 2,
                              ),
                              _buildNavItem(
                                icon: Icons.person_outline,
                                activeIcon: Icons.person,
                                index: 3,
                                isActive: currentIndex == 3,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps [child] in a backdrop blur only when glass effects are enabled.
  Widget _maybeBlur(bool glass, {required Widget child}) {
    if (!glass) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: AppBlur.bar, sigmaY: AppBlur.bar),
      child: child,
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required int index,
    required bool isActive,
  }) {
    return Expanded(
      child: _PassThroughNavItem(
        scrollController: scrollController,
        icon: icon,
        activeIcon: activeIcon,
        isActive: isActive,
        onTap: () => onTap(index),
      ),
    );
  }
}

/// The 40px circle behind the active destination. It slides between segments
/// via the shared [AnimatedAlign] above and breathes with a slow alpha pulse.
class _PulsingHighlight extends StatefulWidget {
  const _PulsingHighlight();

  @override
  State<_PulsingHighlight> createState() => _PulsingHighlightState();
}

class _PulsingHighlightState extends State<_PulsingHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)
      ..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2 + (_pulseAnimation.value * 0.1)),
        ),
      ),
    );
  }
}

// Pass-through navigation item with gesture handling
class _PassThroughNavItem extends StatefulWidget {
  final ScrollController scrollController;
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _PassThroughNavItem({
    required this.scrollController,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_PassThroughNavItem> createState() => _PassThroughNavItemState();
}

class _PassThroughNavItemState extends State<_PassThroughNavItem> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(duration: const Duration(milliseconds: 150), vsync: this);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      onTap: widget.onTap,
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) => _scaleController.reverse(),
      onTapCancel: () {
        _scaleController.reverse();
        _drag?.cancel();
      },

      onVerticalDragStart: (details) {
        if (widget.scrollController.hasClients) {
          _drag = widget.scrollController.position.drag(details, () {
            _drag = null;
          });
        }
      },
      onVerticalDragUpdate: (details) {
        _drag?.update(details);
      },
      onVerticalDragEnd: (details) {
        _drag?.end(details);
      },

      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            // The active background lives in the shared sliding highlight,
            // so the item itself only carries the icon.
            child: SizedBox(
              width: 40,
              height: 40,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isActive ? widget.activeIcon : widget.icon,
                  key: ValueKey(widget.isActive),
                  color: widget.isActive ? Theme.of(context).colorScheme.primary : Colors.grey[500],
                  size: 22,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
