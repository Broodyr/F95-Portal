import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import 'glass_dialog.dart';

/// Chevrons plus a compact pill neighborhood: first, around current, last.
/// The thread viewer's page bar, shared with the reviews page.
class PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onSelect;

  const PaginationBar({super.key, required this.page, required this.totalPages, required this.onSelect});

  // Pill metrics, shared by the widgets below and the width estimate that
  // decides how many of them fit — the two must not drift apart.
  static const double _chevronWidth = 34;
  static const double _pillFontSize = 12;
  static const double _pillHMargin = 2;
  static const double _pillHPadding = 11;
  static const double _gapHPadding = 9;
  static const double _pillVPadding = 5;

  // Both pills centre on the line box, which leaves their glyphs a shade off
  // centre — a digit rides about 0.16px high (no descender to fill the space
  // under it), an ellipsis sits a few px low (it hugs the baseline). Both are
  // deliberate.
  //
  // The digit case was corrected once and reverted. The correction has to
  // come from ascent, cap height and descent, which are the font's, so it
  // only holds for Roboto: under SF Pro, which is what Flutter's Material
  // typography uses on iOS, the same numbers overshoot by roughly 7x and tip
  // the digits low instead. A sub-pixel gain is not worth pinning the layout
  // to one platform's font, especially as correcting the geometry exactly
  // still did not read as centred — what is left is optical, and optical
  // tuning against one device is how this gets worse everywhere else.
  //
  // The ellipsis stays low on purpose too: it should read as punctuation. A
  // vertically centred triple dot is a menu glyph, and the app now has real
  // ones — the overflow buttons on posts and bookmark cards.

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adjacent pages are what the row sheds first when it runs out of
        // width. They carry the longest numbers, so they're the widest pills
        // going — and the least worth their width, since telling 10001 from
        // 10003 means reading five digits and diffing the last one. The
        // chevrons already do ±1, and do it without any reading at all.
        //
        // The bar is a plain fit, not some allowance to shrink into: a pill
        // is only ~23dp tall to begin with, which is already under a
        // comfortable touch target on a phone, so there's no headroom to
        // trade. Width goes to keeping the remaining pills full size.
        final double available = constraints.maxWidth - _chevronWidth * 2;
        List<int> pages = _pageWindow(neighbours: true);
        if (_clusterWidth(context, pages) > available) {
          pages = _pageWindow(neighbours: false);
        }

        final pills = <Widget>[];
        int? previous;
        for (final pill in pages) {
          if (previous != null && pill - previous > 1) {
            // Tappable gap: jump straight to a typed page number. Styled as a
            // pill like its neighbors so it reads as tappable, with a dotted
            // outline instead of a fill to keep it subordinate to real pages.
            pills.add(
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _promptForPage(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: _pillHMargin),
                  padding: const EdgeInsets.symmetric(horizontal: _gapHPadding, vertical: _pillVPadding),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: colorScheme.onSurface.withValues(alpha: AppAlphas.subtleEdge)),
                  ),
                  child: Text(
                    '…',
                    // No explicit `height`: it would shorten this pill's line
                    // box while the digits beside it keep the font's own, and
                    // the padding is already the same, so the gap would sit
                    // 4px shorter than every pill it separates.
                    style: TextStyle(
                      color: AppColors.of(context).bodyText,
                      fontSize: _pillFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }
          pills.add(_buildPagePill(context, colorScheme, pill));
          previous = pill;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPageChevron(context, Icons.chevron_left, 'Previous page', page - 1),
              // Dropping n±1 buys a lot of width but can't guarantee a fit on
              // its own — five digits on a small phone still run long. Scale
              // as the backstop so the row can never overflow, whatever the
              // page count, font, or text scale turns out to be.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: pills),
                ),
              ),
              _buildPageChevron(context, Icons.chevron_right, 'Next page', page + 1),
            ],
          ),
        );
      },
    );
  }

  /// The pages worth a pill: first, last, the current one, and optionally the
  /// two either side of it.
  List<int> _pageWindow({required bool neighbours}) {
    return <int>{
      1,
      if (neighbours && page > 1) page - 1,
      page,
      if (neighbours && page < totalPages) page + 1,
      totalPages,
    }.where((p) => p >= 1 && p <= totalPages).toList()..sort();
  }

  /// What [pages] would take at full size, gap pills included. Measured
  /// rather than assumed, so it holds up under a different font or a bumped
  /// system text size.
  double _clusterWidth(BuildContext context, List<int> pages) {
    double width = 0;
    int? previous;
    for (final pill in pages) {
      if (previous != null && pill - previous > 1) {
        width += _labelWidth(context, '…') + (_gapHPadding + _pillHMargin) * 2;
      }
      width += _labelWidth(context, '$pill') + (_pillHPadding + _pillHMargin) * 2;
      previous = pill;
    }
    return width;
  }

  /// Always measured at w600 — the current page's weight, and the widest a
  /// pill's label ever renders.
  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: _pillFontSize, fontWeight: FontWeight.w600, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  /// A chevron narrowed from IconButton's 48px default: at full size the pair
  /// ate a quarter of the row, which is what pushed it into overflow. Only the
  /// width gives — shrinkWrap is what lets `constraints` actually apply, and
  /// the 48px height keeps the tap target reachable.
  Widget _buildPageChevron(BuildContext context, IconData icon, String tooltip, int target) {
    return IconButton(
      onPressed: target >= 1 && target <= totalPages ? () => onSelect(target) : null,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: AppColors.of(context).iconDefault,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: _chevronWidth, height: 48),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    );
  }

  Future<void> _promptForPage(BuildContext context) async {
    // No controller (the field tracks its own text); reading via onChanged
    // avoids disposing a controller while the dialog is still animating out.
    int? entered;
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('Go to page'),
        content: TextField(
          key: const Key('page-jump-field'),
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (value) => entered = int.tryParse(value.trim()),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(int.tryParse(value.trim())),
          decoration: InputDecoration(
            hintText: '1–$totalPages',
            hintStyle: TextStyle(color: AppColors.of(context).hintText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: GlassDialog.cancelStyle(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(entered),
            style: GlassDialog.confirmStyle(context),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (picked != null) onSelect(picked.clamp(1, totalPages));
  }

  Widget _buildPagePill(BuildContext context, ColorScheme colorScheme, int pill) {
    final bool current = pill == page;
    return GestureDetector(
      onTap: () => onSelect(pill),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: _pillHMargin),
        padding: const EdgeInsets.symmetric(horizontal: _pillHPadding, vertical: _pillVPadding),
        decoration: BoxDecoration(
          // Opaque rather than the translucent chipFill chips elsewhere use:
          // those sit on cards, while the pills sit on the page background,
          // where 35% of a near-black surface all but disappears.
          color: current ? colorScheme.primary.withValues(alpha: AppAlphas.selectedFill) : colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: current ? colorScheme.primary : Colors.transparent),
        ),
        child: Text(
          '$pill',
          style: TextStyle(
            fontSize: _pillFontSize,
            color: current ? Colors.white : AppColors.of(context).bodyText,
            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
