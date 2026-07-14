import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_app.dart';
import 'models/f95_metadata.dart';
import 'services/auth_service.dart';
import 'services/forum_service.dart';
import 'services/settings_service.dart';
import 'services/thread_page_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await F95Metadata.load();
  await AuthService.instance.load();
  await SettingsService.instance.load();
  ThreadPageService.bindToAuthChanges();
  ForumService.bindToAuthChanges();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  runApp(const F95Portal());
}

class F95Portal extends StatelessWidget {
  const F95Portal({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, child) => MaterialApp(
        title: 'F95 Portal',
        debugShowCheckedModeBanner: false,
        showPerformanceOverlay: SettingsService.instance.settings.showPerfOverlay && !kReleaseMode,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFDC144D),
            secondary: Color(0xFF2189FF),
            surface: Color(0xFF1E1E1E),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F0F0F),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF1E1E1E),
            modalBackgroundColor: Color(0xFF1E1E1E),
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: Color(0xFF4A90E2),
            contentTextStyle: TextStyle(color: Colors.white),
          ),
        ),
        home: const MainApp(),
      ),
    );
  }
}
