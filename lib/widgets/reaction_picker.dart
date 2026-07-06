import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'reaction_icon.dart';

/// Bottom sheet listing every reaction; pops with the picked reaction id
/// (null when dismissed).
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({super.key});

  static Future<int?> show(BuildContext context) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const ReactionPicker(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool glass = SettingsService.instance.settings.glassEffects;

    final sheet = Container(
      decoration: BoxDecoration(color: colorScheme.surface.withValues(alpha: glass ? 0.65 : 0.97)),
      padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewPadding.bottom),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'React',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in ReactionGlyph.all.entries)
                  GestureDetector(
                    key: Key('pick-reaction-${entry.key}'),
                    onTap: () => Navigator.of(context).pop(entry.key),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: entry.value.color.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReactionBadge(reactionId: entry.key, size: 20),
                          const SizedBox(width: 6),
                          Text(entry.value.label, style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
