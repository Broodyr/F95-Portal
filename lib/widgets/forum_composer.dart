import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import 'glass_dialog.dart';

/// Compose sheet for replies and new threads: optional title field, a
/// BBCode message field, and a submit that runs [onSubmit] (closing on
/// success, surfacing errors inline).
class ForumComposer extends StatefulWidget {
  final String heading;
  final String submitLabel;
  final bool withTitle;
  final String initialMessage;
  final Future<void> Function(String title, String message) onSubmit;

  const ForumComposer({
    super.key,
    required this.heading,
    required this.onSubmit,
    this.submitLabel = 'Post',
    this.withTitle = false,
    this.initialMessage = '',
  });

  /// Returns true when something was posted.
  static Future<bool> show(
    BuildContext context, {
    required String heading,
    required Future<void> Function(String title, String message) onSubmit,
    String submitLabel = 'Post',
    bool withTitle = false,
    String initialMessage = '',
  }) async {
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: AppAlphas.sheetBarrier),
      builder: (context) => ForumComposer(
        heading: heading,
        onSubmit: onSubmit,
        submitLabel: submitLabel,
        withTitle: withTitle,
        initialMessage: initialMessage,
      ),
    );
    return posted == true;
  }

  @override
  State<ForumComposer> createState() => _ForumComposerState();
}

class _ForumComposerState extends State<ForumComposer> {
  late final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _messageController = TextEditingController(text: widget.initialMessage);
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_sending &&
      _messageController.text.trim().isNotEmpty &&
      (!widget.withTitle || _titleController.text.trim().isNotEmpty);

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_titleController.text.trim(), _messageController.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  /// The common F95zone tags as tap-to-reference examples; a stopgap until
  /// (or unless) the composer grows real formatting buttons.
  static const List<(String, String)> _bbCodeTags = [
    ('[b]bold[/b]', 'Bold'),
    ('[i]italic[/i]', 'Italic'),
    ('[u]underline[/u]', 'Underline'),
    ('[s]strike[/s]', 'Strikethrough'),
    ('[color=red]text[/color]', 'Colored text'),
    ('[size=5]text[/size]', 'Text size (1–7)'),
    ('[url=https://…]link[/url]', 'Link'),
    ('[img]https://…[/img]', 'Image'),
    ('[media=youtube]video-id[/media]', 'Embedded media'),
    ('[quote="name"]text[/quote]', 'Quote someone'),
    ('[spoiler=Title]hidden[/spoiler]', 'Spoiler (title optional)'),
    ('[code]monospace block[/code]', 'Code block'),
    ('[icode]inline code[/icode]', 'Inline code'),
    ('[list]\n[*]item\n[/list]', 'Bullet list'),
    ('[center]text[/center]', 'Centered text'),
    ('[user=1234]@name[/user]', 'Mention a member'),
  ];

  void _showBbCodeCheatsheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: const Text('BBCode cheatsheet'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            key: const Key('bbcode-cheatsheet-list'),
            shrinkWrap: true,
            itemCount: _bbCodeTags.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final (code, label) = _bbCodeTags[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    code,
                    style: TextStyle(color: colorScheme.primary, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: GlassDialog.cancelStyle(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.of(context).hintText, fontSize: 13),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool glass = SettingsService.instance.settings.glassEffects;

    final sheet = Container(
      decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewPadding.bottom + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 30,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.heading,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                key: const Key('composer-bbcode-help'),
                onPressed: () => _showBbCodeCheatsheet(context),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.help_outline, size: 15),
                label: const Text('BBCode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.withTitle) ...[
            TextField(
              key: const Key('composer-title'),
              controller: _titleController,
              maxLength: 150,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _decoration('Thread title').copyWith(counterText: ''),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('composer-message'),
            controller: _messageController,
            minLines: 4,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            decoration: _decoration('Write your message… BBCode works: [b]bold[/b], [spoiler]…[/spoiler]'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: colorScheme.error, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.secondary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              textStyle: AppButtons.ctaTextStyle,
            ),
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                // The send glyph reads heavier than most icons; keep it a
                // touch under the shared CTA icon size.
                : const Icon(Icons.send, size: 20),
            label: Text(widget.submitLabel),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: glass
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppBlur.panel, sigmaY: AppBlur.panel),
              child: sheet,
            )
          : sheet,
    );
  }
}
