import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Bundled glyphs for the site's reaction ids (sprite images aren't worth
/// fetching). Unknown ids get a neutral fallback so new reactions degrade
/// gracefully.
class ReactionGlyph {
  final IconData icon;
  final Color color;

  const ReactionGlyph(this.icon, this.color);

  static const Map<int, ReactionGlyph> _byId = {
    1: ReactionGlyph(Icons.thumb_up, Color(0xFF378ADD)),
    2: ReactionGlyph(Icons.favorite, Color(0xFFD4537E)),
    3: ReactionGlyph(Icons.sentiment_very_satisfied, Color(0xFFEF9F27)),
    4: ReactionGlyph(Icons.star, Color(0xFFEF9F27)),
    5: ReactionGlyph(Icons.sentiment_dissatisfied, Color(0xFF888780)),
    7: ReactionGlyph(Icons.psychology_alt, Color(0xFF7F77DD)),
    8: ReactionGlyph(Icons.sentiment_very_dissatisfied, Color(0xFFE24B4A)),
    9: ReactionGlyph(Icons.waving_hand, Color(0xFF5DCAA5)),
    12: ReactionGlyph(Icons.celebration, Color(0xFF97C459)),
    13: ReactionGlyph(Icons.water_drop, Color(0xFF85B7EB)),
    14: ReactionGlyph(Icons.favorite, Color(0xFFD4537E)),
    17: ReactionGlyph(Icons.emoji_events, Color(0xFFFAC775)),
    18: ReactionGlyph(Icons.thumb_down, Color(0xFF993C1D)),
  };

  static ReactionGlyph of(int id) => _byId[id] ?? const ReactionGlyph(Icons.add_reaction, Color(0xFF888780));
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
      decoration: BoxDecoration(
        color: glyph.color.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: glyph.color.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Icon(glyph.icon, size: size * 0.62, color: glyph.color),
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
