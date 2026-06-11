import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';

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
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required int index,
    required bool isActive,
  }) {
    return _PassThroughNavItem(
      scrollController: scrollController,
      icon: icon,
      activeIcon: activeIcon,
      isActive: isActive,
      onTap: () => onTap(index),
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

class _PassThroughNavItemState extends State<_PassThroughNavItem>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PassThroughNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _pulseController.dispose();
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
        animation: Listenable.merge([_scaleAnimation, _pulseAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isActive
                    ? Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.2 + (_pulseAnimation.value * 0.1),
                      )
                    : Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isActive ? widget.activeIcon : widget.icon,
                  key: ValueKey(widget.isActive),
                  color: widget.isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[500],
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
