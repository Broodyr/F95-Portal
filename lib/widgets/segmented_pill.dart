import 'package:flutter/material.dart';

import '../constants.dart';

/// One segment of a [SegmentedPill] — a description, not a widget. Corners
/// are deliberately absent: [SegmentedPill] derives them from the segment's
/// position in the run, so no caller ever states its own rounding.
@immutable
class PillSegment {
  /// Fill alpha, shared by every segment. Also passed as [borderAlpha] by
  /// segments that want no visible edge at all.
  static const double fillAlpha = 0.9;

  /// Default border alpha: a hair brighter than [fillAlpha], so neighbouring
  /// segments of different colors stay distinct where they meet.
  static const double edgedBorderAlpha = 0.95;

  /// Label style for a text segment. Every pill on the cover art uses it;
  /// the size still scales with the app's font-size setting.
  static const TextStyle labelStyle = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600);

  /// Padding around a text segment. Icon segments override it — a glyph needs
  /// less breathing room than a word.
  ///
  /// State the padding the segment would use standing alone; [SegmentedPill]
  /// thins the edges that end up abutting a neighbour.
  static const EdgeInsets labelPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  final Color color;
  final EdgeInsets padding;
  final double borderAlpha;
  final Widget child;

  const PillSegment({
    required this.color,
    required this.child,
    this.padding = labelPadding,
    this.borderAlpha = edgedBorderAlpha,
  });
}

/// A row of [segments] painted as a single pill: only the run's outer corners
/// round, inner seams stay square where segments meet.
///
/// Solid fills with a hint of transparency: per-segment backdrop blur was a
/// measured frame-time killer (re-blurs every frame over animated covers).
class SegmentedPill extends StatelessWidget {
  final List<PillSegment> segments;

  /// Give every segment the height of the tallest, and center each child in
  /// it. Needed when segments hold different content (an icon beside a word),
  /// which would otherwise leave a notch in the pill's edge. A run of
  /// same-size labels already lines up, and would only pay for the extra
  /// intrinsics pass.
  final bool stretch;

  const SegmentedPill({super.key, required this.segments, this.stretch = false});

  @override
  Widget build(BuildContext context) {
    final Row row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
      children: [
        for (int i = 0; i < segments.length; i++)
          _segmentBox(segments[i], isFirst: i == 0, isLast: i == segments.length - 1),
      ],
    );

    return stretch ? IntrinsicHeight(child: row) : row;
  }

  Widget _segmentBox(PillSegment segment, {required bool isFirst, required bool isLast}) {
    const Radius outer = Radius.circular(AppRadii.pillSegment);

    // A seam collects padding from the segments on both sides of it, which
    // doubles the gap there and reads as clunky. Halve each abutting edge, so
    // a seam spans about what a single outer edge does.
    final EdgeInsets padding = segment.padding.copyWith(
      left: isFirst ? segment.padding.left : segment.padding.left / 2,
      right: isLast ? segment.padding.right : segment.padding.right / 2,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: segment.color.withValues(alpha: PillSegment.fillAlpha),
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? outer : Radius.zero,
          bottomLeft: isFirst ? outer : Radius.zero,
          topRight: isLast ? outer : Radius.zero,
          bottomRight: isLast ? outer : Radius.zero,
        ),
        border: Border.all(color: segment.color.withValues(alpha: segment.borderAlpha)),
      ),
      // Only a stretched segment has spare height to center a child in. An
      // unstretched one sizes to its child, where a Center would instead
      // expand to fill whatever constraints the parent handed down.
      child: stretch ? Center(child: segment.child) : segment.child,
    );
  }
}
