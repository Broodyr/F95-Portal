import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final double starSize;
  final Color starColor;

  const StarRating({super.key, required this.rating, this.starSize = 16, this.starColor = const Color(0xFFFFD700)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6), // Increased opacity since no blur
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: starSize, color: starColor),
          const SizedBox(width: 2),
          Text(
            rating == 0.0 ? '—' : rating.toStringAsFixed(1),
            style: TextStyle(color: starColor, fontSize: starSize * 0.8, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
