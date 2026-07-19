import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import 'glass_aware.dart';

/// A dialog wearing the app's glass treatment: a blurred translucent panel
/// with a hairline edge, so popups match the sheets instead of sitting on
/// Material's flat surface.
///
/// The slots mirror [AlertDialog], but the panel is built from scratch rather
/// than restyled. [Dialog] hardcodes `MaterialType.card`, which renders as a
/// [PhysicalShape] — a compositing boundary. A [BackdropFilter] beneath one
/// samples that empty layer instead of the page, so the blur silently does
/// nothing and only the panel's own fill shows. The [Material] here is
/// [MaterialType.transparency] (no [PhysicalShape]) and sits *inside* the
/// filter, giving the fields and buttons the Material ancestor they require
/// without capping the backdrop.
class GlassDialog extends StatelessWidget {
  /// Used only when the ambient [DialogTheme] leaves these unset — a bare
  /// MaterialApp in tests. The app's real values live in main.dart.
  static const EdgeInsets _fallbackInsetPadding = EdgeInsets.symmetric(horizontal: 40, vertical: 24);
  static const ShapeBorder _fallbackShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(28)),
  );

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  const GlassDialog({super.key, this.title, this.content, this.actions = const []});

  /// Dismissive action: thin pill outline, muted label.
  static ButtonStyle cancelStyle(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: AppColors.of(context).bodyText,
      shape: StadiumBorder(
        // Heavier than the app's hairline borders on purpose: this one has to
        // hold its own beside a filled confirm button, and 0.5 is about where
        // Material's own outlined-button border sits.
        side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    );
  }

  /// Affirmative action, matching the app's CTA buttons: primary fill,
  /// secondary label.
  static ButtonStyle confirmStyle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    );
  }

  Widget _maybeBlur(bool glass, {required Widget child}) {
    if (!glass) return child;
    return BackdropFilter(
      // Quartered blur so the glass effect is visible on top of forum text
      filter: ImageFilter.blur(sigmaX: AppBlur.dialog, sigmaY: AppBlur.dialog),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogTheme = DialogTheme.of(context);
    final shape = dialogTheme.shape ?? _fallbackShape;
    final background = dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface;

    return GlassAware(
      builder: (context, glass) {
        return Padding(
          // Matches Dialog: the view inset keeps the panel above the keyboard
          // when a field inside it takes focus.
          padding: MediaQuery.viewInsetsOf(context) + (dialogTheme.insetPadding ?? _fallbackInsetPadding),
          child: Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280),
              child: ClipPath(
                // Clips to the themed shape. A plain clip is safe here; it is
                // a PhysicalShape (see above) that would break the blur.
                clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.maybeOf(context)),
                child: _maybeBlur(
                  glass,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: shape,
                      color: background.withValues(alpha: glass ? 0.65 : 0.97),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (title != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                              child: DefaultTextStyle.merge(style: dialogTheme.titleTextStyle, child: title!),
                            ),
                          if (content != null)
                            Flexible(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(24, title == null ? 22 : 14, 24, 0),
                                child: DefaultTextStyle.merge(
                                  style: dialogTheme.contentTextStyle,
                                  child: content!,
                                ),
                              ),
                            ),
                          if (actions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                              child: OverflowBar(
                                alignment: MainAxisAlignment.end,
                                overflowAlignment: OverflowBarAlignment.end,
                                spacing: 8,
                                overflowSpacing: 8,
                                children: actions,
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
      },
    );
  }
}
