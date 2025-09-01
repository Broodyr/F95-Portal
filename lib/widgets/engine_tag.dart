import 'package:flutter/material.dart';
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

    if (displayEngines.length == 1) {
      // Single engine - original behavior
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: EngineColors.getEngineColor(displayEngines.first),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          displayEngines.first,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      // Multiple engines - segmented pill
      return Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _buildSegmentedEngines(displayEngines),
        ),
      );
    }
  }

  List<Widget> _buildSegmentedEngines(List<String> displayEngines) {
    List<Widget> widgets = [];

    for (int i = 0; i < displayEngines.length; i++) {
      final engine = displayEngines[i];
      final isFirst = i == 0;
      final isLast = i == displayEngines.length - 1;

      // Determine border radius based on position
      BorderRadius borderRadius;
      if (isFirst && isLast) {
        borderRadius = BorderRadius.circular(12);
      } else if (isFirst) {
        borderRadius = const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        );
      } else if (isLast) {
        borderRadius = const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        );
      } else {
        borderRadius = BorderRadius.zero;
      }

      widgets.add(
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: EngineColors.getEngineColor(engine),
            borderRadius: borderRadius,
          ),
          child: Text(
            engine,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}
