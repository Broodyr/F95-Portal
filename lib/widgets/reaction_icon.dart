import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// System emoji for the site's reaction ids (sprite images aren't worth
/// fetching). Emoji are drawn as text via the platform font: they render
/// reliably (unlike Material Symbols' variable-font glyphs, which Impeller
/// blanks selectively on some devices), carry their own color, and match
/// f95zone's own emoji reactions. Each still gets a tinted circle. Unknown
/// ids fall back to a neutral glyph so new reactions degrade gracefully.
class ReactionGlyph {
  final String emoji;
  final Color color;

  const ReactionGlyph(this.emoji, this.color);

  static const Map<int, ReactionGlyph> _byId = {
    1: ReactionGlyph('\u{1F44D}', Color(0xFF378ADD)), // Like 👍
    2: ReactionGlyph('\u{2764}\u{FE0F}', Color(0xFFD4537E)), // Heart ❤️
    3: ReactionGlyph('\u{1F606}', Color(0xFFEF7727)), // Haha 😆
    4: ReactionGlyph('\u{1F62E}', Color(0xFFEF9F27)), // Wow 😮
    5: ReactionGlyph('\u{1F622}', Color(0xFF888780)), // Sad 😢
    7: ReactionGlyph('\u{1F914}', Color(0xFF7F77DD)), // Thinking Face 🤔
    8: ReactionGlyph('\u{1F620}', Color(0xFFE24B4A)), // Angry 😠
    9: ReactionGlyph('\u{1F440}', Color(0xFF5DCAA5)), // Hey there 👀
    12: ReactionGlyph('\u{1F389}', Color(0xFF97C459)), // Yay, update! 🎉
    13: ReactionGlyph('\u{1F924}', Color(0xFF85B7EB)), // Jizzed my pants 🤤
    17: ReactionGlyph('\u{1F451}', Color(0xFFE3B341)), // Crown 👑
    18: ReactionGlyph('\u{1F44E}', Color(0xFF993C1D)), // Disagree 👎
  };

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
                  color: const Color(0xFF2A2A2A),
                  alignment: Alignment.center,
                  child: Icon(Icons.person, size: size * 0.6, color: const Color(0xFF666666)),
                ),
              ),
      ),
    );
  }
}
