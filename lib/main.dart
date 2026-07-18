import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_app.dart';
import 'models/f95_metadata.dart';
import 'services/auth_service.dart';
import 'services/forum_service.dart';
import 'services/image_cache_wipe.dart';
import 'services/settings_service.dart';
import 'services/thread_page_service.dart';
import 'theme/app_colors.dart';
import 'widgets/app_text_scale.dart';

/// Failed image loads (dead links, missing HD variants) each dump a
/// ~100-line framework error block in debug consoles, drowning out useful
/// output; collapse them to one line each. Other errors pass through.
void installConsoleNoiseFilter() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'image resource service') {
      debugPrint('Image failed: ${details.exception}');
      return;
    }
    defaultOnError?.call(details);
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) installConsoleNoiseFilter();
  await F95Metadata.load();
  await AuthService.instance.load();
  await SettingsService.instance.load();
  ThreadPageService.bindToAuthChanges();
  ForumService.bindToAuthChanges();
  // The app's own image-cache eviction (the package's never deletes files);
  // runs in the background so startup doesn't wait on directory listing.
  unawaited(trimImageCacheDir());
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
        builder: (context, child) => AppTextScale(child: child!),
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFDC144D),
            // Single-accent app: secondary is a neutral grey. Its only
            // visible surface is M3 fallbacks (secondaryContainer ->
            // secondary), e.g. the login progress bar's track.
            secondary: Color(0xFF3A3A3A),
            surface: AppPalette.surface,
          ),
          scaffoldBackgroundColor: AppPalette.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppPalette.appBar,
            foregroundColor: Colors.white,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: AppPalette.surface,
            modalBackgroundColor: AppPalette.surface,
          ),
          extensions: const [AppColors.dark],
        ),
        home: const MainApp(),
      ),
    );
  }
}
