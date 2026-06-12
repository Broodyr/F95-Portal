import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Rebuilds with the current glass-effects preference. Surfaces use real
/// backdrop blur when enabled and a more opaque solid fill when disabled
/// (cheap enough for low-end phones and animated covers).
class GlassAware extends StatelessWidget {
  final Widget Function(BuildContext context, bool glass) builder;

  const GlassAware({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) => builder(context, SettingsService.instance.settings.glassEffects),
    );
  }
}
