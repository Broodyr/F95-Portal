import 'package:flutter/material.dart';

enum ThreadStatus { normal, completed, abandoned, onhold }

class VersionPill extends StatelessWidget {
  static const Color _versionColor = Color(0xFF404040);

  final String version;
  final bool isCompleted;
  final bool isAbandoned;
  final bool isOnhold;
  final double? fontSize;

  const VersionPill({
    super.key,
    required this.version,
    required this.isCompleted,
    this.isAbandoned = false,
    this.isOnhold = false,
    this.fontSize = 12,
  });

  ThreadStatus get _status {
    if (isCompleted) return ThreadStatus.completed;
    if (isAbandoned) return ThreadStatus.abandoned;
    if (isOnhold) return ThreadStatus.onhold;
    return ThreadStatus.normal;
  }

  (Color, IconData)? get _statusBadge {
    switch (_status) {
      case ThreadStatus.normal:
        return null;
      case ThreadStatus.completed:
        return (const Color(0xFF2189FF), Icons.task_alt);
      case ThreadStatus.abandoned:
        return (const Color(0xFF8f561a), Icons.cancel);
      case ThreadStatus.onhold:
        return (const Color(0xFFc255c3), Icons.pause_circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _statusBadge;

    // Solid pills with a hint of transparency: per-pill backdrop blur was a
    // measured frame-time killer (re-blurs every frame over animated covers).
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
              decoration: BoxDecoration(
                color: badge.$1.withValues(alpha: 0.9),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                border: Border.all(color: badge.$1.withValues(alpha: 0.95)),
              ),
              child: Center(child: Icon(badge.$2, color: Colors.white, size: 16)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _versionColor.withValues(alpha: 0.9),
              borderRadius: badge == null
                  ? BorderRadius.circular(12)
                  : const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
              border: Border.all(color: _versionColor.withValues(alpha: 0.9)),
            ),
            child: Center(
              child: Text(
                version,
                style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
