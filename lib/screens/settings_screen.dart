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
import '../services/draft_service.dart';
import '../services/forum_service.dart';
import '../services/image_cache_wipe.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_dialog.dart';
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

  /// Reads the cache's disk use for the button's readout; swappable for the
  /// same reason as [wipeCache].
  static Future<int> Function() cacheSize = imageCacheDirBytes;

  /// Unlike the image cache, this destroys text the user wrote and nothing
  /// refetches it, so it asks first and names the count it is about to take.
  Future<void> _clearDrafts(BuildContext context) async {
    final int count = DraftService.instance.count;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('Clear saved drafts?', style: TextStyle(fontSize: 16)),
        content: Text(
          count == 1
              ? 'Your 1 saved draft will be deleted. This cannot be undone.'
              : 'Your $count saved drafts will be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: GlassDialog.cancelStyle(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: GlassDialog.confirmStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await DraftService.instance.clearAll();
    AppToast.showOn(messenger, count == 1 ? 'Saved draft cleared.' : 'Saved drafts cleared.');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          // Auth changes show/hide the forum-account section; draft changes
          // move the count, including composing done while this tab stayed
          // alive in the background.
          listenable: Listenable.merge([SettingsService.instance, AuthService.instance, DraftService.instance]),
          builder: (context, _) {
            final settings = SettingsService.instance.settings;
            final int draftCount = DraftService.instance.count;

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
                const Align(alignment: Alignment.centerLeft, child: _ImageCacheButton()),
                // Absent rather than disabled at zero: with no drafts there is
                // nothing to say, and the count is the only hint the app gives
                // that unsent text is being held at all.
                if (draftCount > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _clearDrafts(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.65)),
                      ),
                      icon: const Icon(Icons.drafts_outlined, size: 18),
                      label: Text('Clear saved drafts ($draftCount)'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Unsent text from compose sheets you backed out of.',
                      style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
                    ),
                  ),
                ],
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
                Icon(
                  exclude ? Icons.remove : icon,
                  size: 13,
                  color: exclude ? colorScheme.error : AppColors.of(context).iconDefault,
                ),
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

/// Clear-image-cache button carrying what it would reclaim. Stateful because
/// measuring the folder is disk I/O, and the figure has to be re-read after
/// a wipe.
class _ImageCacheButton extends StatefulWidget {
  const _ImageCacheButton();

  @override
  State<_ImageCacheButton> createState() => _ImageCacheButtonState();
}

class _ImageCacheButtonState extends State<_ImageCacheButton> {
  /// Null while loading, and after a read that failed — the size is a
  /// nicety, so an unreadable one goes unmentioned rather than blocking the
  /// button or showing a figure nobody can trust.
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    int? bytes;
    try {
      bytes = await SettingsScreen.cacheSize();
    } catch (_) {
      bytes = null;
    }
    if (mounted) setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SettingsScreen.wipeCache();
      AppToast.showOn(messenger, 'Image cache cleared.');
    } catch (e) {
      AppToast.showOn(messenger, 'Could not clear cache: $e', error: true);
    }
    await _loadSize();
  }

  /// Megabytes once there is a megabyte to report, with a decimal below ten
  /// where the difference is still legible; kilobytes under that, so a small
  /// cache doesn't round away to a meaningless "0 MB".
  static String _formatBytes(int bytes) {
    const int mb = 1024 * 1024;
    if (bytes >= 10 * mb) return '${(bytes / mb).round()} MB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final int? bytes = _bytes;
    final String suffix = bytes == null || bytes == 0 ? '' : ' (${_formatBytes(bytes)})';

    return OutlinedButton.icon(
      onPressed: _clear,
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.65)),
      ),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text('Clear image cache$suffix'),
    );
  }
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
        'Viewing the alerts pop-up will not mark alerts as read. '
        'The Alerts screen in this app uses this setting. '
        'Saved to your forum account preferences.',
        style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 12),
      ),
      value: _value ?? false,
      onChanged: _value == null || _saving ? null : _save,
    );
  }
}
