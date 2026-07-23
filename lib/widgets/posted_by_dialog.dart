import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../services/forum_service.dart';
import '../theme/app_colors.dart';
import 'glass_dialog.dart';
import 'reaction_icon.dart';

typedef UserFinder = Future<List<UserSuggestion>> Function(String query);

/// The search screen's "Posted by" prompt: chosen member names as removable
/// chips over a field whose typing feeds the site's inline member finder,
/// suggestions listed beneath as they arrive. Applying returns the names
/// (an empty list clears the filter); dismissing returns null.
class PostedByDialog extends StatefulWidget {
  /// A pause in typing long enough to ask the finder. Short of a settle so
  /// mid-word queries don't stack, long enough to feel live.
  static const Duration debounce = Duration(milliseconds: 250);

  final List<String> initial;
  final UserFinder? finder;

  const PostedByDialog({super.key, this.initial = const [], this.finder});

  static Future<List<String>?> show(BuildContext context, {List<String> initial = const [], UserFinder? finder}) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => PostedByDialog(initial: initial, finder: finder),
    );
  }

  @override
  State<PostedByDialog> createState() => _PostedByDialogState();
}

class _PostedByDialogState extends State<PostedByDialog> {
  final TextEditingController _controller = TextEditingController();
  late final List<String> _names = [...widget.initial];
  List<UserSuggestion> _suggestions = const [];
  Timer? _debounce;

  /// Stamp of the newest query; a slower earlier response must not clobber
  /// the results of the one typed after it.
  int _querySeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    // The site's finder stays quiet under two characters too.
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(PostedByDialog.debounce, () => _find(query));
  }

  Future<void> _find(String query) async {
    final seq = ++_querySeq;
    try {
      final run = widget.finder ?? ForumService.findUsers;
      final found = await run(query);
      if (!mounted || seq != _querySeq) return;
      setState(() => _suggestions = found);
    } catch (_) {
      // Suggestions are a convenience; typing the name out still works.
    }
  }

  bool _has(String name) => _names.any((existing) => existing.toLowerCase() == name.toLowerCase());

  void _add(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _debounce?.cancel();
    _querySeq++;
    setState(() {
      if (!_has(trimmed)) _names.add(trimmed);
      _suggestions = const [];
      _controller.clear();
    });
  }

  void _apply() {
    // A name still sitting in the field counts; demanding it be chip-ed
    // first would drop it silently.
    final pending = _controller.text.trim();
    Navigator.of(context).pop(<String>[..._names, if (pending.isNotEmpty && !_has(pending)) pending]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GlassDialog(
      title: const Text('Posted by'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final name in _names) _buildNameChip(name)]),
              ),
            TextField(
              key: const Key('posted-by-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: _onChanged,
              onSubmitted: _add,
              style: TextStyle(color: colors.brightText, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: _names.isEmpty ? 'Member name…' : 'Add another member…',
                hintStyle: TextStyle(color: colors.hintText, fontSize: 14),
              ),
            ),
            if (_suggestions.isNotEmpty)
              ConstrainedBox(
                // Roughly five rows; more scroll within.
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 6),
                  children: [for (final suggestion in _suggestions) _buildSuggestionRow(suggestion)],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: GlassDialog.cancelStyle(context),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(style: GlassDialog.confirmStyle(context), onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }

  Widget _buildNameChip(String name) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: AppAlphas.labelChip),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: TextStyle(color: colorScheme.primary, fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _names.remove(name)),
            child: Icon(Icons.close, size: 14, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionRow(UserSuggestion suggestion) {
    return InkWell(
      onTap: () => _add(suggestion.username),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            ForumAvatar(username: suggestion.username, avatarUrl: suggestion.avatarUrl, size: 24),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                suggestion.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.of(context).brightText, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
