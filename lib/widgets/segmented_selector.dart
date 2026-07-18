import 'package:flutter/material.dart';

import 'sliding_reveal.dart';

/// The app's standard radio group: a borderless dark pill track holding one
/// bordered highlight pill that slides between equal-width segments. Every
/// exclusive-choice control (sort orders, kind filters, tabs) should use
/// this; size may vary via [dense]/[shrinkWrap] but the style should not.
class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.values,
    required this.isSelected,
    required this.label,
    required this.onSelect,
    this.dense = false,
    this.shrinkWrap = false,
  });

  final List<T> values;
  final bool Function(T) isSelected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  /// Tighter padding and smaller text for inline filter rows.
  final bool dense;

  /// Size segments to the widest label instead of stretching to the parent.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final int selectedIndex = values.indexWhere(isSelected);

    final track = Container(
      // Borderless dark track: the selected segment carries the only border,
      // so it does not clash with an outer outline.
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(999)),
      child: Stack(
        children: [
          // One shared highlight pill that slides between segments rather
          // than each segment cross-fading its own background.
          if (selectedIndex >= 0)
            Positioned.fill(
              child: AnimatedAlign(
                key: const Key('segment-highlight'),
                duration: Motion.duration,
                curve: Motion.curve,
                alignment: Alignment(values.length == 1 ? 0 : -1 + 2 * selectedIndex / (values.length - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / values.length,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colorScheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(value),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 6 : 10),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: Motion.duration,
                          style: TextStyle(
                            fontSize: dense ? 11.5 : 12,
                            color: isSelected(value) ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            fontWeight: isSelected(value) ? FontWeight.w600 : FontWeight.w400,
                          ),
                          child: Text(label(value)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return shrinkWrap ? IntrinsicWidth(child: track) : track;
  }
}
