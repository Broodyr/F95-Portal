import 'dart:ui';

import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../utils/formatters.dart';

class EngineTag extends StatelessWidget {
  final List<String> engines;
  final double? fontSize;
  final EdgeInsets? padding;

  const EngineTag({
    super.key,
    required this.engines,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    List<String> displayEngines = List.from(engines);
    if (displayEngines.contains('Others') && displayEngines.length > 1) {
      displayEngines.remove('Others');
    }

    if (displayEngines.isEmpty) {
      return const SizedBox.shrink();
    }

    // Glass pill: a single backdrop blur behind all segments, translucent
    // colored fills, and saturated borders per segment. With glass effects
    // disabled (low-end phones), solid fills skip the costly blur.
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final bool glass = SettingsService.instance.settings.glassEffects;
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < displayEngines.length; i++)
              _buildSegment(
                displayEngines[i],
                isFirst: i == 0,
                isLast: i == displayEngines.length - 1,
                fillAlpha: glass ? 0.45 : 0.92,
              ),
          ],
        );
        if (!glass) return row;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: row),
        );
      },
    );
  }

  Widget _buildSegment(String engine, {required bool isFirst, required bool isLast, required double fillAlpha}) {
    final Color color = EngineColors.getEngineColor(engine);
    final BorderRadius borderRadius = BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
      bottomLeft: isFirst ? const Radius.circular(12) : Radius.zero,
      topRight: isLast ? const Radius.circular(12) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: fillAlpha),
        borderRadius: borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.95)),
      ),
      child: Text(
        engine,
        style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
  }
}
