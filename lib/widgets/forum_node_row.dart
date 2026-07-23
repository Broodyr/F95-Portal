import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../theme/app_colors.dart';

/// One forum row, shared by the directory and the subforum block at the
/// top of a thread list. [compact] drops the last-post teaser line.
class ForumNodeRow extends StatelessWidget {
  final ForumNode node;
  final VoidCallback onTap;
  final bool compact;
  final bool showDivider;

  const ForumNodeRow({
    super.key,
    required this.node,
    required this.onTap,
    this.compact = false,
    this.showDivider = false,
  });

  /// Loose keyword mapping so familiar forums get a fitting glyph; anything
  /// unrecognized falls back to a generic forum icon.
  ///
  /// Order matters, and runs most-specific first. A subforum shares its
  /// parent's subject, so its status word ("Rejected Game Requests") tells
  /// it apart from its siblings where the topic word can't; likewise a
  /// request forum always sits beside the release forum that owns the topic
  /// glyph. Both are checked ahead of the topic keywords for that reason.
  static IconData iconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('completed') || t.contains('solved')) return Icons.check_circle_outline;
    if (t.contains('rejected')) return Icons.cancel_outlined;
    if (t.contains('planned')) return Icons.schedule;
    if (t.contains('request')) return Icons.add_circle_outline;
    if (t.contains('translation')) return Icons.translate;
    if (t.contains('game')) return Icons.sports_esports_outlined;
    if (t.contains('mod') || t.contains('cheat')) return Icons.build_outlined;
    if (t.contains('comic') || t.contains('manga')) return Icons.menu_book_outlined;
    if (t.contains('animation') || t.contains('video')) return Icons.movie_filter_outlined;
    // Both before the asset check: 'art' is a substring of "… & Art" and
    // of "Artwork".
    if (t.contains('development') || t.contains('programming')) return Icons.code;
    if (t.contains('artwork')) return Icons.palette_outlined;
    if (t.contains('asset') || t.contains('art')) return Icons.layers_outlined;
    if (t.contains('intro')) return Icons.waving_hand_outlined;
    if (t.contains('off-topic') || t.contains('off topic')) return Icons.beach_access_outlined;
    if (t.contains('recommendation') || t.contains('identification')) return Icons.travel_explore_outlined;
    if (t.contains('tool')) return Icons.handyman_outlined;
    if (t.contains('troubleshooting')) return Icons.healing;
    if (t.contains('help') || t.contains('support') || t.contains('question')) return Icons.help_outline;
    if (t.contains('rule') || t.contains('announcement') || t.contains('news')) return Icons.campaign_outlined;
    if (t.contains('feedback')) return Icons.rate_review_outlined;
    if (t.contains('crack')) return Icons.lock_open;
    if (t.contains('recruitment') || t.contains('service')) return Icons.work_outline;
    if (t.contains('contest')) return Icons.emoji_events_outlined;
    if (t.contains('problem')) return Icons.report_problem_outlined;
    return Icons.forum_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lastPost = node.lastPost;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 9 : 10),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.onSurface.withValues(alpha: AppAlphas.hairline)),
                ),
              )
            : null,
        child: Row(
          children: [
            Icon(iconFor(node.title), size: compact ? 16 : 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.of(context).brightText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (node.threads.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          compact ? node.threads : '${node.threads} threads',
                          style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5),
                        ),
                      ],
                    ],
                  ),
                  if (!compact && lastPost != null)
                    Text(
                      '${lastPost.title} — ${lastPost.date}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.of(context).hintText, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (node.unread)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                ),
              )
            else if (compact)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, size: 15, color: AppColors.of(context).iconDefault),
              ),
          ],
        ),
      ),
    );
  }
}
