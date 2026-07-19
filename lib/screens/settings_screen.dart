import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../constants.dart';
import '../models/account.dart';
import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/search_query.dart';
import '../services/auth_service.dart';
import '../services/forum_service.dart';
import '../services/image_cache_wipe.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/remote_image.dart';
import '../widgets/search_options_sheet.dart';
import '../widgets/segmented_selector.dart';

/// Loads the account's alert preferences (page fetch on device, mock on web).
typedef AlertPrefsLoader = Future<AlertPreferences> Function();

/// Saves the pop-up skips-mark-read preference back to the forum account.
typedef AlertPrefsSaver = Future<void> Function(bool value);

class SettingsScreen extends StatelessWidget {
  /// The list's controller; MainApp watches it to hide/show the bottom nav
  /// and route the nav bar's pass-through drags here.
  final ScrollController? scrollController;

  /// Test seams for the forum-account tile; default to ForumService.
  final AlertPrefsLoader? alertPrefsLoader;
  final AlertPrefsSaver? alertPrefsSaver;

  const SettingsScreen({super.key, this.scrollController, this.alertPrefsLoader, this.alertPrefsSaver});

  Future<void> _editDefaults(BuildContext context) async {
    final current = SettingsService.instance.settings;
    final result = await showModalBottomSheet<SearchQuery>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final bool glass = SettingsService.instance.settings.glassEffects;
        final content = DecoratedBox(
          decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
          child: SearchOptionsSheet(
            initialQuery: current.defaultQuery,
            submitLabel: 'Save',
            // Swipe-dismiss also saves: the sheet reports its state when
            // popped without an explicit submit.
            onDismissSave: (query) =>
                SettingsService.instance.update(SettingsService.instance.settings.copyWith(defaultQuery: query)),
          ),
        );
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: glass
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: AppBlur.panel, sigmaY: AppBlur.panel),
                  child: content,
                )
              : content,
        );
      },
    );

    if (result != null) {
      await SettingsService.instance.update(current.copyWith(defaultQuery: result));
    }
  }

  /// Performs the actual wipe; swappable so widget tests don't touch the
  /// real cache manager (which needs platform channels).
  static Future<void> Function() wipeCache = _defaultWipeCache;

  static Future<void> _defaultWipeCache() async {
    // emptyCache clears the sqlite index and in-memory maps; the on-disk
    // files need wipeImageCacheDir (see its doc for the upstream bug that
    // leaves them all behind).
    await DefaultCacheManager().emptyCache();
    await wipeImageCacheDir();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    RemoteImage.forgetResolved();
  }

  Future<void> _clearImageCache(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await wipeCache();
      AppToast.showOn(messenger, 'Image cache cleared.');
    } catch (e) {
      AppToast.showOn(messenger, 'Could not clear cache: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          // Auth changes show/hide the forum-account section.
          listenable: Listenable.merge([SettingsService.instance, AuthService.instance]),
          builder: (context, _) {
            final settings = SettingsService.instance.settings;

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Settings',
                  style: TextStyle(color: AppColors.of(context).brightText, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                _sectionHeader(context, 'Search defaults'),
                Text(
                  'Every new search starts from these. Clearing the filter bar returns to them.',
                  style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildDefaultsSummary(context, colorScheme, settings.defaultQuery),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _editDefaults(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.secondary,
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
                _sectionHeader(context, 'Appearance'),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Text size', style: TextStyle(color: AppColors.of(context).brightText, fontSize: 15)),
                ),
                Text(
                  'Scales text across the app (default: Medium)',
                  style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
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
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('SFW mode', style: TextStyle(color: AppColors.of(context).brightText, fontSize: 15)),
                  subtitle: Text(
                    'Blur all covers and screenshots',
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
                  ),
                  value: settings.sfwBlur,
                  onChanged: (value) => SettingsService.instance.update(settings.copyWith(sfwBlur: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Glass effects', style: TextStyle(color: AppColors.of(context).brightText, fontSize: 15)),
                  subtitle: Text(
                    'Backdrop blur on sheets, nav bar, overlays, and card reflections; disable if animations lag',
                    style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
                  ),
                  value: settings.glassEffects,
                  onChanged: (value) => SettingsService.instance.update(settings.copyWith(glassEffects: value)),
                ),
                if (!kReleaseMode)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Performance overlay',
                      style: TextStyle(color: AppColors.of(context).brightText, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Flutter frame-time graphs (debug/profile builds only)',
                      style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
                    ),
                    value: settings.showPerfOverlay,
                    onChanged: (value) => SettingsService.instance.update(settings.copyWith(showPerfOverlay: value)),
                  ),
                if (kIsWeb || AuthService.instance.isLoggedIn) ...[
                  _sectionHeader(context, 'Forum account'),
                  _AlertsPopupPrefTile(
                    loader: alertPrefsLoader ?? ForumService.fetchAlertPreferences,
                    saver: alertPrefsSaver ?? ForumService.setAlertsPopupSkipsMarkRead,
                  ),
                ],
                _sectionHeader(context, 'Storage'),
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

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Text(
        label,
        style: TextStyle(color: AppColors.of(context).brightText, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDefaultsSummary(BuildContext context, ColorScheme colorScheme, SearchQuery query) {
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
              color: (exclude ? colorScheme.error : colorScheme.surfaceContainerHighest).withValues(
                alpha: AppAlphas.chipFill,
              ),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                color: exclude
                    ? colorScheme.error.withValues(alpha: 0.6)
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(exclude ? Icons.remove : icon, size: 13, color: exclude ? colorScheme.error : Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: exclude ? colorScheme.error : AppColors.of(context).brightText),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The site's "Alerts pop-up skips mark read" account preference: when on,
/// alerts stay unread until visited instead of being marked read when the
/// app displays them (see ForumService.acknowledgeAlerts). Lives on the
/// forum account, so it loads from and saves to the site.
class _AlertsPopupPrefTile extends StatefulWidget {
  final AlertPrefsLoader loader;
  final AlertPrefsSaver saver;

  const _AlertsPopupPrefTile({required this.loader, required this.saver});

  @override
  State<_AlertsPopupPrefTile> createState() => _AlertsPopupPrefTileState();
}

class _AlertsPopupPrefTileState extends State<_AlertsPopupPrefTile> {
  /// Null until the account preference loads; the switch stays disabled.
  bool? _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await widget.loader();
      if (mounted) setState(() => _value = prefs.popupSkipsMarkRead);
    } catch (_) {
      // Site unreachable: leave the switch disabled.
    }
  }

  Future<void> _save(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _value = value;
    });
    try {
      await widget.saver(value);
    } catch (e) {
      if (mounted) setState(() => _value = !value);
      AppToast.showOn(messenger, 'Could not save to the site: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Alerts pop-up skips mark read',
        style: TextStyle(color: AppColors.of(context).brightText, fontSize: 15),
      ),
      subtitle: Text(
        'Alerts stay unread until you open them, instead of being marked '
        'read once shown. Saved to your forum account preferences.',
        style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
      ),
      value: _value ?? false,
      onChanged: _value == null || _saving ? null : _save,
    );
  }
}
