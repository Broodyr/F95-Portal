import 'package:flutter/material.dart';

enum ThreadStatus { normal, completed, abandoned, onhold }

class VersionPill extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case ThreadStatus.normal:
        // Simple dark gray pill for normal threads
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF404040), borderRadius: BorderRadius.circular(12)),
          child: Text(
            version,
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        );

      case ThreadStatus.completed:
        // Split pill for completed threads (blue with checkmark)
        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Blue with checkmark
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                  ),
                  child: Center(child: Icon(Icons.task_alt, color: Colors.white, size: 16)),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
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
          ),
        );

      case ThreadStatus.abandoned:
        // Split pill for abandoned threads (light orange with cancel icon)
        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Light orange with cancel icon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8f561a),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                  ),
                  child: Center(
                    child: Icon(Icons.cancel, color: Colors.white, size: fontSize),
                  ),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
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
          ),
        );

      case ThreadStatus.onhold:
        // Split pill for onhold threads (pink with pause icon)
        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Pink with pause icon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFc255c3),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                  ),
                  child: Center(
                    child: Icon(Icons.pause_circle, color: Colors.white, size: fontSize),
                  ),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
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
          ),
        );
    }
  }
}
