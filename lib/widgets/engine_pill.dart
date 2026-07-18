import 'package:flutter/material.dart';

import '../utils/formatters.dart';
import 'segmented_pill.dart';

class EnginePill extends StatelessWidget {
  final List<String> engines;

  const EnginePill({super.key, required this.engines});

  @override
  Widget build(BuildContext context) {
    List<String> displayEngines = List.from(engines);
    if (displayEngines.contains('Others') && displayEngines.length > 1) {
      displayEngines.remove('Others');
    }

    if (displayEngines.isEmpty) {
      return const SizedBox.shrink();
    }

    return SegmentedPill(
      segments: [
        for (final engine in displayEngines)
          PillSegment(
            color: EngineColors.getEngineColor(engine),
            child: Text(engine, style: PillSegment.labelStyle),
          ),
      ],
    );
  }
}
