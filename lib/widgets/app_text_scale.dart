import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Applies the font-size setting on top of the ambient (OS) text scale.
/// Installed once as the MaterialApp builder, above the navigator, so
/// screens and sheets alike inherit it.
class AppTextScale extends StatelessWidget {
  final Widget child;

  const AppTextScale({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final double scale = SettingsService.instance.settings.fontSize.scale;
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(media.textScaler.scale(scale))),
          child: child,
        );
      },
    );
  }
}
