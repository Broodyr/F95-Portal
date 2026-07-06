import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

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
      barrierColor: Colors.black.withValues(alpha: 0.55),
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

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
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
          Text(
            widget.heading,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            icon: _sending
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 16),
            label: Text(widget.submitLabel),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: sheet) : sheet,
    );
  }
}
