import 'package:flutter/material.dart';
import 'screens/games_screen.dart';
import 'widgets/bottom_navigation.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _currentIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _bottomNavVisible = ValueNotifier(true);

  @override
  void dispose() {
    _scrollController.dispose();
    _bottomNavVisible.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == 0) {
      // Games tab - already implemented
      setState(() {
        _currentIndex = index;
      });
    } else {
      // Other tabs - show coming soon message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_getTabName(index)} coming soon!'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    }
  }

  String _getTabName(int index) {
    switch (index) {
      case 0:
        return 'Games';
      case 1:
        return 'Forum';
      case 2:
        return 'Search';
      case 3:
        return 'Settings';
      case 4:
        return 'Profile';
      default:
        return 'Unknown';
    }
  }

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return GamesScreen(
          scrollController: _scrollController,
          bottomNavVisible: _bottomNavVisible,
        );
      default:
        // Placeholder for other tabs
        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.construction, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  '${_getTabName(_currentIndex)} coming soon!',
                  style: TextStyle(color: Colors.grey[400], fontSize: 18),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          _getCurrentScreen(),
          ValueListenableBuilder<bool>(
            valueListenable: _bottomNavVisible,
            builder: (context, isVisible, child) {
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                bottom: isVisible ? 0 : -120,
                left: 0,
                right: 0,
                child: child!,
              );
            },
            child: CustomBottomNavigation(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              scrollController: _scrollController,
            ),
          ),
        ],
      ),
    );
  }
}
