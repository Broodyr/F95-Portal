import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/search_query.dart';
import '../services/settings_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/search_options_modal.dart';
import '../widgets/segmented_selector.dart';

class SettingsScreen extends StatelessWidget {
  /// The list's controller; MainApp watches it to hide/show the bottom nav
  /// and route the nav bar's pass-through drags here.
  final ScrollController? scrollController;

  const SettingsScreen({super.key, this.scrollController});

  Future<void> _editDefaults(BuildContext context) async {
    final current = SettingsService.instance.settings;
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final bool glass = SettingsService.instance.settings.glassEffects;
        final content = DecoratedBox(
          decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
          child: SearchOptionsModal(
            initialQuery: current.defaultQuery,
            submitLabel: 'Save',
            // Swipe-dismiss also saves: the modal reports its state when
            // popped without an explicit submit.
            onDismissSave: (query) =>
                SettingsService.instance.update(SettingsService.instance.settings.copyWith(defaultQuery: query)),
          ),
        );
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: content) : content,
        );
      },
    );

    if (result != null) {
      await SettingsService.instance.update(current.copyWith(defaultQuery: result));
    }
  }

  Future<void> _clearImageCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DefaultCacheManager().emptyCache();
      PaintingBinding.instance.imageCache.clear();
      AppToast.showOn(messenger, 'Image cache cleared.');
    } catch (e) {
      AppToast.showOn(messenger, 'Could not clear cache: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: SettingsService.instance,
          builder: (context, _) {
            final settings = SettingsService.instance.settings;

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                _sectionHeader('Search defaults'),
                Text(
                  'Every new search starts from these. Clearing the filter bar returns to them.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildDefaultsSummary(colorScheme, settings.defaultQuery),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _editDefaults(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Edit defaults'),
                    ),
                    const SizedBox(width: 8),
                    if (settings.defaultQuery != const SearchQuery())
                      TextButton(
                        onPressed: () =>
                            SettingsService.instance.update(settings.copyWith(defaultQuery: const SearchQuery())),
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                _sectionHeader('Appearance'),
                Text(
                  'Text size across the app',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const SizedBox(height: 12),
                SegmentedSelector<FontSizeOption>(
                  values: FontSizeOption.values,
                  isSelected: (option) => settings.fontSize == option,
                  label: (option) => switch (option) {
                    FontSizeOption.small => 'Small',
                    FontSizeOption.medium => 'Medium',
                    FontSizeOption.large => 'Large',
                  },
                  onSelect: (option) => SettingsService.instance.update(settings.copyWith(fontSize: option)),
                ),
                _sectionHeader('Privacy'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('SFW mode', style: TextStyle(color: Colors.white, fontSize: 15)),
                  subtitle: Text(
                    'Blur all covers and screenshots',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  activeTrackColor: colorScheme.primary,
                  value: settings.sfwBlur,
                  onChanged: (value) => SettingsService.instance.update(settings.copyWith(sfwBlur: value)),
                ),
                _sectionHeader('Performance'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Glass effects', style: TextStyle(color: Colors.white, fontSize: 15)),
                  subtitle: Text(
                    'Backdrop blur on sheets, nav bar, overlays, and card reflections; disable if animations lag',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  activeTrackColor: colorScheme.primary,
                  value: settings.glassEffects,
                  onChanged: (value) => SettingsService.instance.update(settings.copyWith(glassEffects: value)),
                ),
                if (!kReleaseMode)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Performance overlay', style: TextStyle(color: Colors.white, fontSize: 15)),
                    subtitle: Text(
                      'Flutter frame-time graphs (debug/profile builds only)',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    activeTrackColor: colorScheme.primary,
                    value: settings.showPerfOverlay,
                    onChanged: (value) => SettingsService.instance.update(settings.copyWith(showPerfOverlay: value)),
                  ),
                _sectionHeader('Storage'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _clearImageCache(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.65)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear image cache'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDefaultsSummary(ColorScheme colorScheme, SearchQuery query) {
    final metadata = F95Metadata.instance;
    final entries = <(IconData, String, bool)>[
      (Icons.category_outlined, query.category.displayLabel, false),
      (Icons.swap_vert, 'Sort: ${query.sort.displayLabel}', false),
      (Icons.schedule, query.dateDays == null ? 'Updated: Any' : 'Updated: ${query.dateDays}d', false),
      if (query.search.trim().isNotEmpty) (Icons.search, '"${query.search.trim()}"', false),
      if (query.creator.trim().isNotEmpty) (Icons.person_outline, query.creator.trim(), false),
      for (final id in query.tags) (Icons.tag, metadata.tagName(id) ?? '#$id', false),
      for (final id in query.notags) (Icons.tag, metadata.tagName(id) ?? '#$id', true),
      for (final id in query.prefixes) (Icons.memory, metadata.prefixById(query.category, id)?.name ?? '#$id', false),
      for (final id in query.noprefixes) (Icons.memory, metadata.prefixById(query.category, id)?.name ?? '#$id', true),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label, exclude) in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (exclude ? colorScheme.error : colorScheme.surfaceContainerHighest).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: exclude
                    ? colorScheme.error.withValues(alpha: 0.6)
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(exclude ? Icons.remove : icon, size: 13, color: exclude ? colorScheme.error : Colors.grey[400]),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: exclude ? colorScheme.error : Colors.grey[300])),
              ],
            ),
          ),
      ],
    );
  }

}
