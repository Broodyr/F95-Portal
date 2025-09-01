import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../widgets/games_list.dart';
import '../widgets/glassmorphic_fabs.dart';
//import '../widgets/noisy_background.dart';

class GamesScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final ValueNotifier<bool> bottomNavVisible;

  const GamesScreen({
    super.key,
    this.scrollController,
    required this.bottomNavVisible,
  });

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  // Use external ScrollController if provided, otherwise create internal one
  late final ScrollController _scrollController;

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

  void _onFilterPressed() {
    // TODO: Show filter modal
  }

  void _onSearchPressed() {
    // TODO: Show search options modal
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      body: Stack(
        children: [
          //PreRenderedNoisyBackground(child: Container()),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.5), // Center slightly above the middle
                radius: 1.5, // A large radius to make the gradient very soft
                colors: [
                  Color.fromARGB(255, 24, 24, 24),
                  Color.fromARGB(255, 8, 8, 8),
                ],
              ),
            ),
          ),

          GamesList(scrollController: _scrollController),

          GlassmorphicFabs(
            scrollController: _scrollController,
            onFilterPressed: _onFilterPressed,
            onSearchPressed: _onSearchPressed,
            bottomNavVisible: widget.bottomNavVisible,
          ),
        ],
      ),
    );
  }
}
