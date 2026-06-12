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

    // Solid pills with a hint of transparency: per-pill backdrop blur was a
    // measured frame-time killer (re-blurs every frame over animated covers).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < displayEngines.length; i++)
          _buildSegment(displayEngines[i], isFirst: i == 0, isLast: i == displayEngines.length - 1),
      ],
    );
  }

  Widget _buildSegment(String engine, {required bool isFirst, required bool isLast}) {
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
        color: color.withValues(alpha: 0.9),
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
