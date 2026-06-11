import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Wraps imagery that should be obscured while SFW mode is on. Reacts live
/// to the setting, so toggling it re-renders every cover on screen.
class SfwBlur extends StatelessWidget {
  final Widget child;

  const SfwBlur({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        if (!SettingsService.instance.settings.sfwBlur) {
          return child;
        }
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
          child: child,
        );
      },
    );
  }
}
