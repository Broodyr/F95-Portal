import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/f95_metadata.dart';
import '../models/search_query.dart';
import '../utils/formatters.dart';

class _BarChip {
  final IconData icon;
  final String label;
  final bool exclude;
  final SearchQuery Function() remove;

  const _BarChip({required this.icon, required this.label, required this.remove, this.exclude = false});
}

/// Glass strip shown over the threads list while a search is active:
/// one removable chip per filter, the live result count, and a clear-all
/// button. Tapping a chip removes just that filter.
class ActiveFiltersBar extends StatelessWidget {
  final SearchQuery query;
  final int? resultCount;
  final ValueChanged<SearchQuery> onQueryChanged;

  const ActiveFiltersBar({super.key, required this.query, required this.resultCount, required this.onQueryChanged});

  List<_BarChip> _buildChips() {
    final metadata = F95Metadata.instance;
    final chips = <_BarChip>[];

    if (query.search.trim().isNotEmpty) {
      chips.add(
        _BarChip(icon: Icons.search, label: '"${query.search.trim()}"', remove: () => query.copyWith(search: '')),
      );
    }
    if (query.creator.trim().isNotEmpty) {
      chips.add(
        _BarChip(icon: Icons.person_outline, label: query.creator.trim(), remove: () => query.copyWith(creator: '')),
      );
    }

    void addIdChips(List<int> ids, {required bool isTag, required bool exclude}) {
      for (final id in ids) {
        final label = isTag ? (metadata.tagName(id) ?? '#$id') : (metadata.prefixById(query.category, id)?.name ?? '#$id');
        chips.add(
          _BarChip(
            icon: isTag ? Icons.tag : Icons.memory,
            label: label,
            exclude: exclude,
            remove: () {
              List<int> without(List<int> list) => [for (final v in list) if (v != id) v];
              if (isTag) {
                return exclude ? query.copyWith(notags: without(query.notags)) : query.copyWith(tags: without(query.tags));
              }
              return exclude
                  ? query.copyWith(noprefixes: without(query.noprefixes))
                  : query.copyWith(prefixes: without(query.prefixes));
            },
          ),
        );
      }
    }

    addIdChips(query.tags, isTag: true, exclude: false);
    addIdChips(query.notags, isTag: true, exclude: true);
    addIdChips(query.prefixes, isTag: false, exclude: false);
    addIdChips(query.noprefixes, isTag: false, exclude: true);

    if (query.sort != SortOrder.date) {
      chips.add(
        _BarChip(
          icon: Icons.swap_vert,
          label: 'Sort: ${query.sort.displayLabel}',
          remove: () => query.copyWith(sort: SortOrder.date),
        ),
      );
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chips = _buildChips();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
          ),
          child: Row(
            children: [
              if (resultCount != null) ...[
                Text(
                  '${NumberFormatter.formatNumber(resultCount!)} results',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final chip in chips) ...[
                        _buildChip(colorScheme, chip),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Clear all filters',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.filter_alt_off_outlined, size: 18, color: Colors.grey[400]),
                onPressed: () => onQueryChanged(SearchQuery(category: query.category)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(ColorScheme colorScheme, _BarChip chip) {
    final Color accent = chip.exclude ? colorScheme.error : colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onQueryChanged(chip.remove()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chip.exclude ? Icons.remove : chip.icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(chip.label, style: const TextStyle(fontSize: 12, color: Colors.white)),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 13, color: Colors.white.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
