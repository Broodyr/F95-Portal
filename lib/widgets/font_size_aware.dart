import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Rebuilds with the current font-size preference, for the few texts that
/// pin their rendered size with [FontSizeOption.anchored] instead of
/// following the app-wide scaler. A scaler change alone re-lays-out a Text
/// but does not re-run the parent build that computed the anchored size, so
/// pinned styles go stale without this listener.
class FontSizeAware extends StatelessWidget {
  final Widget Function(BuildContext context, FontSizeOption fontSize) builder;

  const FontSizeAware({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) => builder(context, SettingsService.instance.settings.fontSize),
    );
  }
}
