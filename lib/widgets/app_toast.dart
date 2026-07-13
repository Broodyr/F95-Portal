import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass_aware.dart';

/// App-styled toast: a self-sized floating pill on the bottom nav's glass
/// surface (blur when glass effects are on, near-opaque otherwise). Rides
/// the SnackBar machinery, so it queues and dismisses like one; a new
/// toast replaces the current one instead of queueing behind it.
class AppToast {
  static void show(BuildContext context, String message, {bool error = false}) {
    showOn(ScaffoldMessenger.of(context), message, error: error);
  }

  /// For callers that captured the messenger before an await.
  static void showOn(ScaffoldMessengerState messenger, String message, {bool error = false}) {
    final colorScheme = Theme.of(messenger.context).colorScheme;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(32, 0, 32, 72),
          duration: const Duration(milliseconds: 2800),
          content: Center(
            child: GlassAware(
              builder: (context, glass) => ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _maybeBlur(
                  glass,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E).withValues(alpha: glass ? 0.4 : 0.92),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (error) ...[
                          Icon(Icons.error_outline, size: 15, color: colorScheme.error),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            message,
                            style: const TextStyle(color: Color(0xFFE8E8E8), fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  /// Wraps [child] in a backdrop blur only when glass effects are enabled.
  static Widget _maybeBlur(bool glass, {required Widget child}) {
    if (!glass) return child;
    return BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: child);
  }
}
