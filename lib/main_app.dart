import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'screens/forum_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/threads_screen.dart';
import 'services/api_service.dart';
import 'widgets/app_toast.dart';
import 'widgets/bottom_navigation.dart';
import 'widgets/threads_list.dart';

class MainApp extends StatefulWidget {
  final FetchThreadsCallback fetchThreads;

  const MainApp({super.key, this.fetchThreads = ApiService.fetchThreads});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _currentIndex = 0;

  // One controller per tab: every tab's scroll drives the nav bar's
  // hide/show, and the bar's pass-through drags reach the active tab's list.
  final List<ScrollController> _tabControllers = List.generate(4, (_) => ScrollController());
  final ValueNotifier<bool> _bottomNavVisible = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    for (final controller in _tabControllers) {
      controller.addListener(() => _onTabScroll(controller));
    }
  }

  @override
  void dispose() {
    for (final controller in _tabControllers) {
      controller.dispose();
    }
    _bottomNavVisible.dispose();
    super.dispose();
  }

  /// Scrolling down hides the nav bar, scrolling up shows it. A page that
  /// fits on screen never hides it — there's no reading space to reclaim,
  /// and a hidden bar would strand the user (matters on bouncing physics,
  /// where overscroll still moves the offset).
  void _onTabScroll(ScrollController controller) {
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.userScrollDirection == ScrollDirection.reverse && position.maxScrollExtent > 0) {
      _bottomNavVisible.value = false;
    } else if (position.userScrollDirection == ScrollDirection.forward) {
      _bottomNavVisible.value = true;
    }
  }

  void _onTabTapped(int index) {
    // Re-tapping the active tab scrolls its list back to the top.
    if (index == _currentIndex) {
      final controller = _tabControllers[index];
      if (controller.hasClients && controller.offset > 0) {
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
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
              ThreadsScreen(
                scrollController: _tabControllers[0],
                bottomNavVisible: _bottomNavVisible,
                fetchThreads: widget.fetchThreads,
              ),
              ForumScreen(scrollController: _tabControllers[1]),
              SettingsScreen(scrollController: _tabControllers[2]),
              ProfileScreen(scrollController: _tabControllers[3]),
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
              scrollController: _tabControllers[_currentIndex],
            ),
          ),
        ],
      ),
    );
  }
}
