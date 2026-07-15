import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'screens/forum_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/threads_screen.dart';
import 'widgets/app_toast.dart';
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
    setState(() {
      _currentIndex = index;
    });
  }

  /// When the last back press happened on the Browse tab; a second press
  /// inside the toast's lifetime exits the app.
  DateTime? _lastExitPress;

  void _onBackPressed() {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastExitPress != null && now.difference(_lastExitPress!) < AppDurations.toastDuration) {
      SystemNavigator.pop();
      return;
    }
    _lastExitPress = now;
    AppToast.show(context, 'Press back again to exit');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Stack(
        children: [
          // IndexedStack keeps every tab's state alive (active search,
          // scroll position) across switches; state resets on app restart.
          IndexedStack(
            index: _currentIndex,
            children: [
              ThreadsScreen(scrollController: _scrollController, bottomNavVisible: _bottomNavVisible),
              const ForumScreen(),
              const SettingsScreen(),
              const ProfileScreen(),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _bottomNavVisible,
            builder: (context, isVisible, child) {
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                bottom: isVisible ? 0 : -(72 + MediaQuery.of(context).padding.bottom),
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
