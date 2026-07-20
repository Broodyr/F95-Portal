import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// System emoji for the site's reaction ids (sprite images aren't worth
/// fetching). Emoji are drawn as text via the platform font: they render
/// reliably (unlike Material Symbols' variable-font glyphs, which Impeller
/// blanks selectively on some devices), carry their own color, and match
/// f95zone's own emoji reactions. Each still gets a tinted circle. Unknown
/// ids fall back to a neutral glyph so new reactions degrade gracefully.
class ReactionGlyph {
  final String emoji;
  final Color color;
  final String label;

  const ReactionGlyph(this.emoji, this.color, [this.label = '']);

  /// Insertion order is the site's own, taken from its picker template
  /// (`#xfReactTooltipTemplate`) — the picker renders the map in order, and
  /// a test pins it against the fixture. The template also offers 15
  /// (Star-struck) and 17 (Crown), which the live site no longer shows and
  /// the API rejects; leave both out.
  static const Map<int, ReactionGlyph> _byId = {
    1: ReactionGlyph('\u{1F44D}', Color(0xFF378ADD), 'Like'), // 👍
    14: ReactionGlyph('\u{2764}\u{FE0F}', Color(0xFFE05785), 'Heart'), // ❤️
    13: ReactionGlyph('\u{1F924}', Color(0xFF85B7EB), 'Jizzed my pants'), // 🤤
    12: ReactionGlyph('\u{1F973}', Color(0xFF97C459), 'Yay, update!'), // 🥳
    3: ReactionGlyph('\u{1F923}', Color(0xFFFF7C25), 'Haha'), // 🤣
    9: ReactionGlyph('\u{1F440}', Color(0xFF5DCAA5), 'Hey there'), // 👀
    4: ReactionGlyph('\u{1F632}', Color(0xFFEF9F27), 'Wow'), // 😲
    7: ReactionGlyph('\u{1F914}', Color(0xFF7F77DD), 'Thinking'), // 🤔
    5: ReactionGlyph('\u{1F622}', Color(0xFF888780), 'Sad'), // 😢
    // Deliberately not the site's sprite, which is an unimpressed face: a
    // thumb down reads as disagreement at a glance. Don't "fix" to match.
    18: ReactionGlyph('\u{1F44E}', Color(0xFF993C1D), 'Disagree'), // 👎
    8: ReactionGlyph('\u{1F621}', Color(0xFFE24B4A), 'Angry'), // 😡
  };

  /// The pickable reactions, in site order (map order).
  static Map<int, ReactionGlyph> get all => _byId;

  static ReactionGlyph of(int id) => _byId[id] ?? const ReactionGlyph('\u{2753}', Color(0xFF888780)); // ❓
}

/// Small colored circle holding a reaction glyph, used in summary chips
/// and the reactions sheet.
class ReactionBadge extends StatelessWidget {
  final int reactionId;
  final double size;

  const ReactionBadge({super.key, required this.reactionId, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final glyph = ReactionGlyph.of(reactionId);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: glyph.color.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: glyph.color.withValues(alpha: 0.6), width: 0.5),
      ),
      // Emoji render in their own colors via the system font; the circle
      // tint carries the reaction's accent.
      child: Text(glyph.emoji, style: TextStyle(fontSize: size * 0.58, height: 1.0)),
    );
  }
}

/// Initials avatar with a deterministic per-user color; shows the network
/// image when the user has one.
class ForumAvatar extends StatelessWidget {
  static const List<Color> _palette = [
    Color(0xFF534AB7),
    Color(0xFF1D9E75),
    Color(0xFF993C1D),
    Color(0xFF185FA5),
    Color(0xFF993556),
    Color(0xFF3B6D11),
    Color(0xFF854F0B),
  ];

  final String username;
  final String? avatarUrl;
  final double size;

  const ForumAvatar({super.key, required this.username, this.avatarUrl, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? Container(
                color: _palette[username.hashCode.abs() % _palette.length],
                alignment: Alignment.center,
                child: Text(
                  username.isEmpty ? '?' : username[0].toUpperCase(),
                  style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600),
                ),
              )
            : CachedNetworkImage(
                imageUrl: url.startsWith('/') ? 'https://f95zone.to$url' : url,
                fit: BoxFit.cover,
                errorWidget: (context, imageUrl, error) => Container(
                  color: AppColors.of(context).placeholderSurface,
                  alignment: Alignment.center,
                  child: Icon(Icons.person, size: size * 0.6, color: AppColors.of(context).mutedForeground),
                ),
              ),
      ),
    );
  }
}
