import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Bundled glyphs for the site's reaction ids (sprite images aren't worth
/// fetching). A glyph is either a Material Symbols [icon] or an [emoji]
/// drawn as text — emoji codepoints aren't in the icon font, so forcing
/// them through [IconData] breaks release icon tree-shaking. Icons use
/// Material Symbols (the current Google design) rather than Flutter's
/// frozen classic Icons; [fill] mirrors each glyph's solid/outlined
/// character. Unknown ids get a neutral fallback so new reactions degrade
/// gracefully.
class ReactionGlyph {
  final IconData? icon;
  final String? emoji;
  final Color color;
  final double fill;

  const ReactionGlyph(IconData this.icon, this.color, {this.fill = 0}) : emoji = null;
  const ReactionGlyph.emoji(String this.emoji, this.color) : icon = null, fill = 0;

  static const Map<int, ReactionGlyph> _byId = {
    1: ReactionGlyph(Symbols.thumb_up, Color(0xFF378ADD), fill: 1), // Like
    2: ReactionGlyph(Symbols.favorite, Color(0xFFD4537E), fill: 1), // Heart
    3: ReactionGlyph(Symbols.sentiment_very_satisfied, Color(0xFFEF9F27)), // Haha
    4: ReactionGlyph.emoji('\u{1F62E}', Color(0xFFEF9F27)), // Wow
    5: ReactionGlyph(Symbols.sentiment_dissatisfied, Color(0xFF888780)), // Sad
    7: ReactionGlyph.emoji('\u{1F914}', Color(0xFF7F77DD)), // Thinking Face
    8: ReactionGlyph(Symbols.sentiment_very_dissatisfied, Color(0xFFE24B4A)), // Angry
    9: ReactionGlyph.emoji('\u{1F440}', Color(0xFF5DCAA5)), // Hey there
    12: ReactionGlyph(Symbols.celebration, Color(0xFF97C459)), // Yay, update!
    13: ReactionGlyph.emoji('\u{1F924}', Color(0xFF85B7EB)), // Jizzed my pants
    18: ReactionGlyph(Symbols.thumb_down, Color(0xFF993C1D), fill: 1), // Disagree
  };

  static ReactionGlyph of(int id) => _byId[id] ?? const ReactionGlyph(Symbols.add_reaction, Color(0xFF888780));
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
    final emoji = glyph.emoji;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: glyph.color.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: glyph.color.withValues(alpha: 0.6), width: 0.5),
      ),
      // Emoji render in their own colors via the system font (the circle
      // tint still carries the reaction's color); icons take the tint.
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: size * 0.58, height: 1.0))
          : Icon(glyph.icon, fill: glyph.fill, size: size * 0.62, color: glyph.color),
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
