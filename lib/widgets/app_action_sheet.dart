import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';

/// One row of an [showAppActionSheet]: an optional leading glyph, a label, and
/// the callback run when it's chosen. [destructive] tints the row in the
/// theme's error accent — the same mark the exclude chips carry — for the
/// removals (Delete, Remove bookmark).
class AppSheetAction {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const AppSheetAction({required this.label, required this.onTap, this.icon, this.destructive = false});
}

/// The screen rectangle of [context]'s render box, for anchoring a menu's
/// highlight to the control that opened it. Null before layout.
Rect? menuAnchorRect(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

/// A circular highlight window centred on [context]'s box, sized from
/// [glyphSize]. For the round glyph triggers: their padded hit box is
/// deliberately off-square, so tracing it would sit the ring off-centre and
/// squash it into a stubby pill — a circle on the glyph's own centre reads as
/// the control lighting up. Anchor to the glyph itself (not the padded box)
/// so the centre is exact.
({Rect rect, BorderRadius radius})? circleMenuAnchor(BuildContext context, {required double glyphSize}) {
  final box = menuAnchorRect(context);
  if (box == null) return null;
  final double r = glyphSize / 2 + 9;
  return (rect: Rect.fromCircle(center: box.center, radius: r), radius: BorderRadius.circular(r));
}

/// The app's shared overflow menu: a glass bottom sheet of tappable rows, in
/// place of the system [PopupMenuButton]. Grabber, blur, and rounded top match
/// the reactions and browse sheets, so every menu in the app reads as one
/// surface.
///
/// Pass [anchorRect] (+ [anchorRadius]) to light the control that opened the
/// sheet: the page-dimming barrier carries a window at that rect, so the
/// trigger stays bright and glows through the shade while everything else
/// recedes. The window lives in the sheet route's own barrier — below the
/// sheet, above the page — so the sheet itself is never dimmed and the glow
/// fades in and out in step with it.
///
/// The chosen action runs *after* the sheet has closed rather than from inside
/// it, so a callback is free to push a route or open its own sheet without
/// racing this one's dismissal — the same order the alerts long-press relied on
/// when this lived there.
Future<void> showAppActionSheet(
  BuildContext context, {
  required List<AppSheetAction> actions,
  Rect? anchorRect,
  BorderRadius anchorRadius = const BorderRadius.all(Radius.circular(10)),
}) async {
  if (actions.isEmpty) return;

  final Future<AppSheetAction?> result;
  if (anchorRect != null) {
    final navigator = Navigator.of(context);
    result = navigator.push(
      _HighlightSheetRoute<AppSheetAction>(
        builder: (_) => _AppActionSheet(actions: actions),
        capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        anchorRect: anchorRect,
        anchorRadius: anchorRadius,
        scrimColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
        glowColor: Theme.of(context).colorScheme.primary,
      ),
    );
  } else {
    result = showModalBottomSheet<AppSheetAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
      builder: (_) => _AppActionSheet(actions: actions),
    );
  }

  final chosen = await result;
  chosen?.onTap();
}

/// The card/toolbar overflow trigger: a tooltip'd `more_vert` that opens the
/// shared sheet and lights itself while the sheet is up. Sized by its own
/// padding rather than an M3 [IconButton], which won't go under 40x40 — too
/// tall for the badge and header rows these ride.
class AppOverflowButton extends StatefulWidget {
  final List<AppSheetAction> actions;
  final String tooltip;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final Color? iconColor;

  const AppOverflowButton({
    super.key,
    required this.actions,
    required this.tooltip,
    this.padding = const EdgeInsets.fromLTRB(8, 4, 2, 4),
    this.iconSize = 16,
    this.iconColor,
  });

  @override
  State<AppOverflowButton> createState() => _AppOverflowButtonState();
}

class _AppOverflowButtonState extends State<AppOverflowButton> {
  // Keyed so the highlight anchors to the glyph's own laid-out box rather than
  // the asymmetric padded hit box around it.
  final GlobalKey _iconKey = GlobalKey();

  void _open() {
    final iconContext = _iconKey.currentContext;
    final anchor = iconContext == null ? null : circleMenuAnchor(iconContext, glyphSize: widget.iconSize);
    showAppActionSheet(
      context,
      actions: widget.actions,
      anchorRect: anchor?.rect,
      anchorRadius: anchor?.radius ?? const BorderRadius.all(Radius.circular(9)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: Padding(
          padding: widget.padding,
          child: Icon(
            Icons.more_vert,
            key: _iconKey,
            size: widget.iconSize,
            color: widget.iconColor ?? AppColors.of(context).iconDefault,
          ),
        ),
      ),
    );
  }
}

class _AppActionSheet extends StatelessWidget {
  final List<AppSheetAction> actions;

  const _AppActionSheet({required this.actions});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool glass = SettingsService.instance.settings.glassEffects;

    final sheet = Container(
      decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            for (final action in actions) _row(context, colorScheme, action),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    // Container, not a filled Material: a Material of any non-transparency type
    // kills the BackdropFilter beneath it. See the reactions sheet.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: glass
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppBlur.panel, sigmaY: AppBlur.panel),
              child: sheet,
            )
          : sheet,
    );
  }

  Widget _row(BuildContext context, ColorScheme colorScheme, AppSheetAction action) {
    final Color labelColor = action.destructive ? colorScheme.error : AppColors.of(context).brightText;
    // The glyph rides a step under its label by default; a destructive row
    // keeps both on the error accent so the whole row reads as the warning.
    final Color iconColor = action.destructive ? colorScheme.error : AppColors.of(context).subtleText;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            if (action.icon != null) ...[Icon(action.icon, size: 19, color: iconColor), const SizedBox(width: 14)],
            Text(action.label, style: TextStyle(color: labelColor, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

/// A bottom-sheet route whose barrier dims the page *around* a window over the
/// trigger, lighting it through the shade. Because this is the route's own
/// barrier, it sits below the sheet (the sheet is never dimmed) and its fade
/// is driven by the route animation, so the glow tracks the sheet in and out.
class _HighlightSheetRoute<T> extends ModalBottomSheetRoute<T> {
  final Rect anchorRect;
  final BorderRadius anchorRadius;
  final Color scrimColor;
  final Color glowColor;

  _HighlightSheetRoute({
    required super.builder,
    required this.anchorRect,
    required this.anchorRadius,
    required this.scrimColor,
    required this.glowColor,
    super.capturedThemes,
    super.barrierLabel,
  }) : super(
         isScrollControlled: true,
         backgroundColor: Colors.transparent,
         // The dim is painted by the barrier below; the framework's own
         // barrier stays clear so the window isn't shaded twice.
         modalBarrierColor: Colors.transparent,
       );

  @override
  Widget buildModalBarrier() {
    return Stack(
      key: const Key('menu-highlight'),
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: AnimatedBuilder(
            animation: animation!,
            builder: (context, _) => CustomPaint(
              painter: _HighlightScrimPainter(
                rect: anchorRect,
                radius: anchorRadius,
                barrierColor: scrimColor,
                glowColor: glowColor,
                t: Curves.easeOut.transform(animation!.value.clamp(0.0, 1.0)),
              ),
            ),
          ),
        ),
        // The clear barrier above the shade is what dismisses on a tap outside.
        ModalBarrier(dismissible: barrierDismissible, semanticsLabel: barrierLabel),
      ],
    );
  }
}

class _HighlightScrimPainter extends CustomPainter {
  final Rect rect;
  final BorderRadius radius;
  final Color barrierColor;
  final Color glowColor;
  final double t;

  _HighlightScrimPainter({
    required this.rect,
    required this.radius,
    required this.barrierColor,
    required this.glowColor,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(rect);

    // The shade is the whole screen minus the trigger's window — painting the
    // difference leaves the trigger un-dimmed rather than punching a hole with
    // a saveLayer, which some raster backends handle unevenly.
    final shade = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rrect));
    canvas.drawPath(shade, Paint()..color = barrierColor.withValues(alpha: barrierColor.a * t));

    // A soft halo just outside the window, then a crisp lip on it: the trigger
    // reads as lit, not merely undimmed.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = glowColor.withValues(alpha: t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 7),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = glowColor.withValues(alpha: 0.9 * t),
    );
  }

  @override
  bool shouldRepaint(_HighlightScrimPainter old) =>
      old.t != t ||
      old.rect != rect ||
      old.radius != radius ||
      old.barrierColor != barrierColor ||
      old.glowColor != glowColor;
}
