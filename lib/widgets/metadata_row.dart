import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'star_rating.dart';

class MetadataRow extends StatelessWidget {
  final String timeUpdated;
  final int likes;
  final int views;
  final double rating;

  const MetadataRow({
    super.key,
    required this.timeUpdated,
    required this.likes,
    required this.views,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Time updated
        Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          ThreadUtils.formatTime(timeUpdated),
          style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 12),
        ),
        const SizedBox(width: 16),

        // Likes
        Icon(Icons.favorite, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          NumberFormatter.formatNumber(likes),
          style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 12),
        ),
        const SizedBox(width: 16),

        // Views
        Icon(Icons.visibility, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text(
          NumberFormatter.formatNumber(views),
          style: TextStyle(color: AppColors.of(context).bodyText, fontSize: 12),
        ),

        // Score, pushed to the row's right end
        const Spacer(),
        StarRating(rating: rating, starSize: 14),
      ],
    );
  }
}
