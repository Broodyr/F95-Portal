import 'package:flutter/material.dart';
import '../utils/formatters.dart';

class MetadataRow extends StatelessWidget {
  final String timeUpdated;
  final int likes;
  final int views;

  const MetadataRow({
    super.key,
    required this.timeUpdated,
    required this.likes,
    required this.views,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Time updated
        Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          GameUtils.formatTime(timeUpdated),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        const SizedBox(width: 16),

        // Likes
        Icon(Icons.favorite, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          NumberFormatter.formatNumber(likes),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        const SizedBox(width: 16),

        // Views
        Icon(Icons.visibility, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          NumberFormatter.formatNumber(views),
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
      ],
    );
  }
}
