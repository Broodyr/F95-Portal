import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A failure that has taken over a whole screen.
///
/// Sized like the app's other full-screen states — the sign-in gate, an empty
/// browse list — rather than like the inline notices inside sheets. Those two
/// scales had drifted together: an error that *is* the screen was being drawn
/// at the size used for a strip inside a bottom sheet.
///
/// [detail] is for what the site or API actually said. It reads under the
/// headline rather than replacing it, so the screen still says which thing
/// failed when the underlying message is jargon.
class ErrorView extends StatelessWidget {
  final String headline;
  final String? detail;
  final IconData icon;

  /// Omit where retrying cannot help — a 403 earns the same 403.
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.headline, this.detail, this.icon = Icons.cloud_off, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colors.mutedForeground),
            const SizedBox(height: 16),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.brightText, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.bodyText, fontSize: 14, height: 1.35),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              // A TextButton like every other Retry in the app. The one that
              // was an unstyled OutlinedButton drew Material's default border,
              // which comes from `colorScheme.outline` — a role this theme
              // leaves unset, so it landed pure white.
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
