import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
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

/// A switch part's colour for the state it's in. Spelling out thumb and track
/// costs the framework's own disabled styling, so fade it back in here — the
/// alerts tile switches off while it loads and saves, and without this it
/// would look live the whole time.
Color _switchColor(Set<WidgetState> states, {required Color on, required Color off}) {
  final base = states.contains(WidgetState.selected) ? on : off;
  return states.contains(WidgetState.disabled) ? base.withValues(alpha: 0.4) : base;
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
            primary: AppPalette.primary,
            secondary: AppPalette.secondary,
            surface: AppPalette.surface,
            // ColorScheme.dark() derives no container ladder — it hands back
            // `surface` for every surfaceContainer* role — so any role the
            // app reads has to be pinned here or it silently paints as
            // surface. Chip fills did exactly that, and since the sheets
            // they sit on are also surface, they came out invisible.
            surfaceContainerHighest: AppPalette.raisedSurface,
            // Same trap, different role: onSurfaceVariant means the muted
            // counterpart to onSurface, but unpinned it comes back as the
            // same pure white, so the secondary labels and icons written
            // against it lost the contrast step they were asking for.
            onSurfaceVariant: AppPalette.subtleText,
          ),
          scaffoldBackgroundColor: AppPalette.background,
          appBarTheme: AppBarTheme(
            backgroundColor: AppPalette.appBar,
            // Titles here are the same rank as a root screen's heading, which
            // reads brightText — so pushed screens match rather than being the
            // only pure white left. Carries the back arrow and action icons
            // with it, which is the point: they were the brightest chrome.
            foregroundColor: AppColors.dark.brightText,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: AppPalette.surface,
            modalBackgroundColor: AppPalette.surface,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => _switchColor(states, on: AppPalette.secondary, off: AppPalette.primary),
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => _switchColor(
                states,
                on: AppPalette.primary,
                off: Colors.black.withValues(alpha: AppAlphas.chipFill),
              ),
            ),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? Colors.transparent : AppPalette.secondary,
            ),
          ),
          // `GlassDialog` reads these rather than inheriting them, since it
          // can't build on [Dialog] (see its doc comment) — so this stays the
          // one place dialog chrome is defined, for it and for any plain
          // AlertDialog that picks the theme up for free.
          dialogTheme: DialogThemeData(
            backgroundColor: AppPalette.surface,
            barrierColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            titleTextStyle: TextStyle(color: AppColors.dark.brightText, fontSize: 16, fontWeight: FontWeight.w600),
            contentTextStyle: TextStyle(color: AppColors.dark.bodyText, fontSize: 13),
          ),
          extensions: const [AppColors.dark],
        ),
        home: const MainApp(),
      ),
    );
  }
}
