import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/thread_page.dart';
import '../models/thread_summary.dart';
import '../services/thread_page_service.dart';
import '../utils/formatters.dart';
import 'engine_tag.dart';
import 'screenshot_gallery.dart';
import 'sfw_blur.dart';
import 'version_pill.dart';

/// Popped by the modal when the user picks a tag: tap adds it to the active
/// search, long-press replaces the search with just that tag.
class ThreadTagSelection {
  final int tagId;
  final bool replace;

  const ThreadTagSelection({required this.tagId, required this.replace});
}

typedef UrlLauncher = Future<bool> Function(Uri uri);
typedef FetchThreadPage = Future<ThreadPage> Function(int threadId);

class ThreadDetailsModal extends StatefulWidget {
  final ThreadSummary thread;
  final SearchCategory category;
  final UrlLauncher? urlLauncher;
  final FetchThreadPage? fetchThreadPage;

  const ThreadDetailsModal({
    super.key,
    required this.thread,
    this.category = SearchCategory.games,
    this.urlLauncher,
    this.fetchThreadPage,
  });

  static Future<ThreadTagSelection?> show(
    BuildContext context,
    ThreadSummary thread, {
    SearchCategory category = SearchCategory.games,
    UrlLauncher? urlLauncher,
    FetchThreadPage? fetchThreadPage,
  }) {
    return showModalBottomSheet<ThreadTagSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) => ThreadDetailsModal(
        thread: thread,
        category: category,
        urlLauncher: urlLauncher,
        fetchThreadPage: fetchThreadPage,
      ),
    );
  }

  @override
  State<ThreadDetailsModal> createState() => _ThreadDetailsModalState();
}

class _ThreadDetailsModalState extends State<ThreadDetailsModal> {
  ThreadPage? _page;
  bool _loadingPage = true;
  String? _pageError;
  bool _overviewExpanded = false;
  final Set<int> _expandedSpoilers = {};
  int _platformIndex = 0;

  ThreadSummary get thread => widget.thread;

  Uri get _threadUri => Uri.parse('https://f95zone.to/threads/${thread.threadId}/');

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loadingPage = true;
      _pageError = null;
    });

    try {
      final fetch = widget.fetchThreadPage ?? ThreadPageService.fetch;
      final page = await fetch(thread.threadId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loadingPage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pageError = e.toString();
        _loadingPage = false;
      });
    }
  }

  Future<void> _launch(Uri uri) async {
    final launch =
        widget.urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(uri);
  }

  void _shareThread() {
    SharePlus.instance.share(ShareParams(text: '${thread.title} — $_threadUri'));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Same glass treatment as the search modal: blur + translucent surface.
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: 0.65)),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewPadding.bottom),
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  _buildCoverHeader(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.title,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('by ${thread.creator}', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                      ],
                    ),
                  ),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _buildStatsRow(colorScheme)),
                  if (thread.screens.isNotEmpty) ...[
                    _buildSectionLabel('Screenshots'),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: thread.screens.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _buildScreenshotThumb(context, index),
                      ),
                    ),
                  ],
                  if (thread.tags.isNotEmpty) ...[
                    _buildSectionLabel('Tags', hint: 'tap to add to search · hold to replace'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildTagChips(context, colorScheme),
                    ),
                  ],
                  ..._buildPageSections(colorScheme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _launch(_threadUri),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open thread'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: _shareThread,
                          tooltip: 'Share',
                          // The share glyph's visual weight sits right of
                          // center; nudge it so it reads centered.
                          icon: Transform.translate(
                            offset: const Offset(-1, 0),
                            child: const Icon(Icons.share_outlined, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Scraped page sections -----------------------------------------------

  List<Widget> _buildPageSections(ColorScheme colorScheme) {
    if (_loadingPage) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Loading thread details…', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
      ];
    }

    if (_pageError != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't load thread details",
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ),
              TextButton(onPressed: _loadPage, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }

    final page = _page;
    if (page == null) return const [];

    final metaFields = [
      for (final field in page.metaFields)
        if (!{'genre', 'overview'}.contains(field.label.toLowerCase())) field,
    ];
    final spoilers = [
      for (final spoiler in page.spoilers)
        if (spoiler.title.toLowerCase() != 'genre') spoiler,
    ];

    return [
      if (metaFields.isNotEmpty) ...[
        _buildSectionLabel('Info'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildInfoGrid(metaFields)),
      ],
      if (page.overview.isNotEmpty) ...[
        _buildSectionLabel('Overview'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildOverviewCard(colorScheme, page.overview),
        ),
      ],
      if (page.downloads != null && !page.downloads!.isEmpty) ...[
        _buildSectionLabel('Downloads'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildDownloadsCard(colorScheme, page.downloads!),
        ),
      ],
      for (int i = 0; i < spoilers.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildSpoilerCard(colorScheme, i, spoilers[i]),
        ),
    ];
  }

  Widget _buildInfoGrid(List<MetaField> fields) {
    final itemWidth = (MediaQuery.of(context).size.width - 48) / 2;
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        for (final field in fields)
          SizedBox(
            width: itemWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                Text(field.value, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewCard(ColorScheme colorScheme, String overview) {
    return GestureDetector(
      onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          overview,
          maxLines: _overviewExpanded ? null : 5,
          overflow: _overviewExpanded ? null : TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.45),
        ),
      ),
    );
  }

  Widget _buildDownloadsCard(ColorScheme colorScheme, DownloadsSection downloads) {
    final platforms = downloads.platforms;
    final selected = platforms.isEmpty ? null : platforms[_platformIndex.clamp(0, platforms.length - 1)];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (platforms.length > 1) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < platforms.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _platformIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: i == _platformIndex
                            ? colorScheme.primary.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: i == _platformIndex
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        platforms[i].label,
                        style: TextStyle(
                          fontSize: 12,
                          color: i == _platformIndex ? colorScheme.primary : Colors.grey[400],
                          fontWeight: i == _platformIndex ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ] else if (platforms.length == 1) ...[
            Text(platforms.single.label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 6),
          ],
          if (selected != null) _buildHostLinks(colorScheme, selected.links),
          if (downloads.extras.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            ),
            Text('Extras', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 6),
            for (final extra in downloads.extras) ...[
              if (extra.label.toLowerCase() != 'extras' && extra.label.toLowerCase() != 'extra')
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(extra.label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ),
              _buildHostLinks(colorScheme, extra.links),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHostLinks(ColorScheme colorScheme, List<DownloadLink> links) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final link in links)
          GestureDetector(
            onTap: () => _launch(Uri.parse(link.url)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, size: 12, color: colorScheme.primary),
                  const SizedBox(width: 5),
                  Text(link.host, style: TextStyle(color: Colors.grey[200], fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpoilerCard(ColorScheme colorScheme, int index, SpoilerSection spoiler) {
    final bool expanded = _expandedSpoilers.contains(index);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => expanded ? _expandedSpoilers.remove(index) : _expandedSpoilers.add(index)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      spoiler.title,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey[500]),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                spoiler.content,
                style: TextStyle(color: Colors.grey[300], fontSize: 13, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }

  // --- Phase-1 sections (unchanged) ----------------------------------------

  Widget _buildCoverHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        key: const Key('details-cover'),
        behavior: HitTestBehavior.opaque,
        // Covers are cropped to 3:1 here; tap to see the full image.
        onTap: thread.cover.isEmpty ? null : () => ScreenshotGallery.show(context, [thread.cover]),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 3.0,
                child: thread.cover.isEmpty
                    ? Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48),
                      )
                    : SfwBlur(
                        child: CachedNetworkImage(
                          imageUrl: thread.cover,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48),
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: EngineTag(engines: ThreadUtils.getEnginesFromThread(thread.prefixes, category: widget.category)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: VersionPill(
                version: thread.version,
                isCompleted: thread.isCompleted,
                isAbandoned: thread.isAbandoned,
                isOnhold: thread.isOnhold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ColorScheme colorScheme) {
    Widget stat(IconData icon, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: Colors.grey[400]),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        stat(Icons.star_outline, thread.rating > 0 ? thread.rating.toStringAsFixed(1) : '-'),
        const SizedBox(width: 6),
        stat(Icons.favorite_outline, NumberFormatter.formatNumber(thread.likes)),
        const SizedBox(width: 6),
        stat(Icons.visibility_outlined, NumberFormatter.formatNumber(thread.views)),
        const SizedBox(width: 6),
        stat(Icons.schedule, thread.date),
      ],
    );
  }

  Widget _buildSectionLabel(String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScreenshotThumb(BuildContext context, int index) {
    return GestureDetector(
      onTap: () => ScreenshotGallery.show(context, thread.screens, initialIndex: index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 150,
          child: SfwBlur(
            child: CachedNetworkImage(
              imageUrl: thread.screens[index],
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: const Color(0xFF2A2A2A)),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF2A2A2A),
                child: const Icon(Icons.broken_image_outlined, color: Color(0xFF666666)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChips(BuildContext context, ColorScheme colorScheme) {
    final metadata = F95Metadata.instance;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tagId in thread.tags)
          GestureDetector(
            onTap: () {
              // selectionClick/vibrate are used (not light/heavyImpact)
              // because Android maps heavyImpact to CONTEXT_CLICK, which
              // feels weaker than lightImpact on many devices.
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(ThreadTagSelection(tagId: tagId, replace: false));
            },
            onLongPress: () {
              HapticFeedback.vibrate();
              Navigator.of(context).pop(ThreadTagSelection(tagId: tagId, replace: true));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(
                metadata.tagName(tagId) ?? '#$tagId',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
