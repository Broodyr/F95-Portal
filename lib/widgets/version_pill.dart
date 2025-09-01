import 'package:flutter/material.dart';

enum GameStatus { normal, completed, abandoned, onhold }

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

  GameStatus get _status {
    if (isCompleted) return GameStatus.completed;
    if (isAbandoned) return GameStatus.abandoned;
    if (isOnhold) return GameStatus.onhold;
    return GameStatus.normal;
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case GameStatus.normal:
        // Simple dark gray pill for normal games
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF404040),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            version,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

      case GameStatus.completed:
        // Split pill for completed games (blue with checkmark)
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
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.task_alt, color: Colors.white, size: 16),
                  ),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      version,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case GameStatus.abandoned:
        // Split pill for abandoned games (light orange with cancel icon)
        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Light orange with cancel icon
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8f561a),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.cancel,
                      color: Colors.white,
                      size: fontSize,
                    ),
                  ),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      version,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case GameStatus.onhold:
        // Split pill for onhold games (pink with pause icon)
        return IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Pink with pause icon
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFc255c3),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.pause_circle,
                      color: Colors.white,
                      size: fontSize,
                    ),
                  ),
                ),
                // Right side: Version text on dark gray
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF404040),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      version,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
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
