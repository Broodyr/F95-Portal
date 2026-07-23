import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import 'glass_aware.dart';

/// App-styled toast: a self-sized floating pill on the bottom nav's glass
/// surface (blur when glass effects are on, near-opaque otherwise). Rides
/// the SnackBar machinery, so it queues and dismisses like one; a new
/// toast replaces the current one instead of queueing behind it.
class AppToast {
  /// Shows the toast. Pass [actionLabel]/[onAction] for a trailing button (an
  /// Undo, say); returns the SnackBar controller so callers can await its
  /// `.closed` — e.g. to commit a deferred action once the toast is gone.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return showOn(ScaffoldMessenger.of(context), message, error: error, actionLabel: actionLabel, onAction: onAction);
  }

  /// For callers that captured the messenger before an await.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOn(
    ScaffoldMessengerState messenger,
    String message, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colorScheme = Theme.of(messenger.context).colorScheme;

    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(32, 0, 32, 72),
        duration: AppDurations.toastDuration,
        content: Center(
          child: GlassAware(
            builder: (context, glass) => ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _maybeBlur(
                glass,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: glass ? 0.4 : 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4)),
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 32, offset: const Offset(0, 8)),
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
                          style: TextStyle(color: AppColors.of(context).brightText, fontSize: 12.5, height: 1.35),
                        ),
                      ),
                      if (actionLabel != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            onAction?.call();
                            messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2, right: 2),
                            child: Text(
                              actionLabel,
                              style: TextStyle(color: colorScheme.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
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
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: AppBlur.bar, sigmaY: AppBlur.bar),
      child: child,
    );
  }
}
