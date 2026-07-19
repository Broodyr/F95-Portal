import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import 'reaction_icon.dart';

typedef FetchReactions = Future<ReactionsPage> Function(String url);

/// Bottom sheet listing who reacted to a post: per-reaction filter pills
/// (with real counts from the overlay page) above the member list.
class ReactionsSheet extends StatefulWidget {
  final String url;
  final int postNumber;
  final FetchReactions fetchReactions;

  const ReactionsSheet({super.key, required this.url, required this.postNumber, required this.fetchReactions});

  static Future<void> show(
    BuildContext context, {
    required String url,
    required int postNumber,
    required FetchReactions fetchReactions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
      builder: (context) => ReactionsSheet(url: url, postNumber: postNumber, fetchReactions: fetchReactions),
    );
  }

  @override
  State<ReactionsSheet> createState() => _ReactionsSheetState();
}

class _ReactionsSheetState extends State<ReactionsSheet> {
  ReactionsPage? _page;
  String? _error;
  int _selectedReactionId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await widget.fetchReactions(widget.url);
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  String _reactionName(int id) {
    for (final tab in _page?.tabs ?? const <ReactionTab>[]) {
      if (tab.id == id) return tab.name;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool glass = SettingsService.instance.settings.glassEffects;

    final page = _page;
    final members = [
      for (final member in page?.members ?? const <ReactionMember>[])
        if (_selectedReactionId == 0 || member.reactionId == _selectedReactionId) member,
    ];

    Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Couldn't load reactions",
                style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13),
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else if (page == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final tab in page.tabs)
                  Padding(padding: const EdgeInsets.only(right: 6), child: _buildPill(colorScheme, tab)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewPadding.bottom),
              itemCount: members.length,
              itemBuilder: (context, index) => _buildMemberRow(members[index]),
            ),
          ),
        ],
      );
    }

    final sheet = Container(
      decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 30,
            width: double.infinity,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              'Reactions to #${widget.postNumber}',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(child: body),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: glass
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: AppBlur.panel, sigmaY: AppBlur.panel),
                child: sheet,
              )
            : sheet,
      ),
    );
  }

  Widget _buildPill(ColorScheme colorScheme, ReactionTab tab) {
    final bool selected = _selectedReactionId == tab.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedReactionId = tab.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // A translucent lift rather than a surface fill: the sheet is
          // itself surface, so surface-derived tokens land back on its own
          // colour and the pill disappears. Staying translucent also keeps
          // the blur reading through it.
          color: selected ? colorScheme.primary.withValues(alpha: 0.25) : colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? colorScheme.primary : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.id != 0) ...[ReactionBadge(reactionId: tab.id, size: 14), const SizedBox(width: 5)],
            Text(
              '${tab.name} ${tab.count}',
              style: TextStyle(
                fontSize: 11.5,
                color: selected ? Colors.white : AppColors.of(context).bodyText,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow(ReactionMember member) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          ForumAvatar(username: member.username, avatarUrl: member.avatarUrl, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.username, style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (member.memberTitle.isNotEmpty)
                  Text(member.memberTitle, style: TextStyle(color: AppColors.of(context).hintText, fontSize: 10.5)),
              ],
            ),
          ),
          ReactionBadge(reactionId: member.reactionId, size: 15),
          const SizedBox(width: 5),
          Text(
            _reactionName(member.reactionId),
            style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
