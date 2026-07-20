import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/forum.dart';
import '../services/forum_service.dart';
import '../theme/app_colors.dart';
import 'app_toast.dart';
import 'glass_dialog.dart';

typedef ReportFormFetcher = Future<ReportForm> Function(String contentUrl);
typedef ReportSender =
    Future<void> Function(String action, String csrfToken, {required int reasonId, required String message});

/// Files a report against a post or profile post.
///
/// The reasons come off the site's own form rather than a baked-in list, so
/// the dialog fetches before it can show anything — hence the loading state.
/// That also gets a fresh CSRF token, which the submit needs.
class ReportDialog extends StatefulWidget {
  /// The content being reported: a post or profile-post permalink. The report
  /// overlay lives at this URL with `/report` appended.
  final String contentUrl;

  final ReportFormFetcher? fetchForm;
  final ReportSender? sendReport;

  const ReportDialog({super.key, required this.contentUrl, this.fetchForm, this.sendReport});

  /// Returns true once a report has actually been filed.
  static Future<bool> show(
    BuildContext context, {
    required String contentUrl,
    ReportFormFetcher? fetchForm,
    ReportSender? sendReport,
  }) async {
    final reported = await showDialog<bool>(
      context: context,
      builder: (_) => ReportDialog(contentUrl: contentUrl, fetchForm: fetchForm, sendReport: sendReport),
    );
    return reported ?? false;
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final TextEditingController _message = TextEditingController();

  ReportForm? _form;
  String? _error;
  int? _reasonId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final fetch = widget.fetchForm ?? ForumService.fetchReportForm;
      final form = await fetch('${widget.contentUrl}/report');
      if (!mounted) return;
      setState(() => _form = form);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    final form = _form;
    final reasonId = _reasonId;
    if (form == null || reasonId == null || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final send = widget.sendReport ?? ForumService.sendReport;
      await send(form.action, form.csrfToken, reasonId: reasonId, message: _message.text.trim());
      AppToast.showOn(messenger, 'Report sent. Thanks.');
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      AppToast.showOn(messenger, "Couldn't send the report: $e", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final form = _form;

    return GlassDialog(
      title: const Text('Report content', style: TextStyle(fontSize: 16)),
      content: _buildContent(colorScheme, form),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          style: GlassDialog.cancelStyle(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Gated on a reason: the site's form makes it a required radio, and
          // a report with no category is one a moderator has to guess at.
          onPressed: _reasonId == null || _sending ? null : _submit,
          style: GlassDialog.confirmStyle(context),
          child: Text(_sending ? 'Sending…' : 'Send report'),
        ),
      ],
    );
  }

  Widget _buildContent(ColorScheme colorScheme, ReportForm? form) {
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              "Couldn't load the report form",
              style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    if (form == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (!form.isAvailable) {
      return Text(
        "This content can't be reported.",
        style: TextStyle(color: AppColors.of(context).subtleText, fontSize: 13),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrapped pills rather than a SegmentedSelector: the reasons are read
        // off the site, so both their number and their label lengths are out
        // of our hands — the exception AGENTS.md carves out for exactly this.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final reason in form.reasons) _buildReasonPill(colorScheme, reason)],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('report-message-field'),
          controller: _message,
          maxLines: 3,
          minLines: 2,
          // The pills and buttons already refuse input while sending; without
          // this the note was still editable after the report had gone out.
          readOnly: _sending,
          style: TextStyle(color: AppColors.of(context).brightText, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Anything the moderators should know (optional)',
            hintStyle: TextStyle(color: AppColors.of(context).hintText, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildReasonPill(ColorScheme colorScheme, ReportReason reason) {
    final bool selected = _reasonId == reason.id;
    return GestureDetector(
      onTap: _sending ? null : () => setState(() => _reasonId = reason.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.4)),
        ),
        child: Text(
          reason.label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? colorScheme.primary : AppColors.of(context).bodyText,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
