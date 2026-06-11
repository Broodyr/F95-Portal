import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/thread_summary.dart';
import '../utils/formatters.dart';
import 'engine_tag.dart';
import 'screenshot_gallery.dart';
import 'version_pill.dart';

/// Popped by the modal when the user picks a tag: tap adds it to the active
/// search, long-press replaces the search with just that tag.
class ThreadTagSelection {
  final int tagId;
  final bool replace;

  const ThreadTagSelection({required this.tagId, required this.replace});
}

typedef UrlLauncher = Future<bool> Function(Uri uri);

class ThreadDetailsModal extends StatelessWidget {
  final ThreadSummary thread;
  final SearchCategory category;
  final UrlLauncher? urlLauncher;

  const ThreadDetailsModal({super.key, required this.thread, this.category = SearchCategory.games, this.urlLauncher});

  static Future<ThreadTagSelection?> show(
    BuildContext context,
    ThreadSummary thread, {
    SearchCategory category = SearchCategory.games,
    UrlLauncher? urlLauncher,
  }) {
    return showModalBottomSheet<ThreadTagSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (BuildContext context) =>
          ThreadDetailsModal(thread: thread, category: category, urlLauncher: urlLauncher),
    );
  }

  Uri get _threadUri => Uri.parse('https://f95zone.to/threads/${thread.threadId}/');

  Future<void> _openThread() async {
    final launch = urlLauncher ?? ((uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication));
    await launch(_threadUri);
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openThread,
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
                          // The share glyph's visual weight sits high-right; nudge
                          // it so it reads centered in the circle.
                          icon: Transform.translate(
                            offset: const Offset(-1, 1),
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
                    : CachedNetworkImage(
                        imageUrl: thread.cover,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.image_outlined, color: Color(0xFF666666), size: 48),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: EngineTag(engines: ThreadUtils.getEnginesFromThread(thread.prefixes, category: category)),
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
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(ThreadTagSelection(tagId: tagId, replace: false));
            },
            onLongPress: () {
              HapticFeedback.heavyImpact();
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
