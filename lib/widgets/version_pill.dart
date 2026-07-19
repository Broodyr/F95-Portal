import 'package:flutter/material.dart';

import 'segmented_pill.dart';

enum ThreadStatus { normal, completed, abandoned, onhold }

class VersionPill extends StatelessWidget {
  static const Color _versionColor = Color(0xFF404040);

  final String version;
  final bool isCompleted;
  final bool isAbandoned;
  final bool isOnhold;

  const VersionPill({
    super.key,
    required this.version,
    required this.isCompleted,
    this.isAbandoned = false,
    this.isOnhold = false,
  });

  ThreadStatus get _status {
    if (isCompleted) return ThreadStatus.completed;
    if (isAbandoned) return ThreadStatus.abandoned;
    if (isOnhold) return ThreadStatus.onhold;
    return ThreadStatus.normal;
  }

  // These colors diverge from the official site, for better distinction against engine colors
  (Color, IconData)? get _statusBadge {
    switch (_status) {
      case ThreadStatus.normal:
        return null;
      case ThreadStatus.completed:
        return (const Color(0xFF2189ff), Icons.task_alt);
      case ThreadStatus.abandoned:
        return (const Color(0xFF8f561a), Icons.cancel);
      case ThreadStatus.onhold:
        return (const Color(0xFFc255c3), Icons.pause_circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _statusBadge;

    // Stretched: the icon segment has to match the taller text segment, or
    // the pill's edge shows a notch where they meet.
    return SegmentedPill(
      stretch: true,
      segments: [
        if (badge != null)
          PillSegment(
            color: badge.$1,
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
            child: Icon(badge.$2, color: Colors.white, size: 16),
          ),
        PillSegment(
          color: _versionColor,
          // Border matches the fill: a lighter edge here read as an artifact
          // against the cover art (aa2b0ba).
          borderAlpha: PillSegment.fillAlpha,
          child: Text(version, style: PillSegment.labelStyle),
        ),
      ],
    );
  }
}
