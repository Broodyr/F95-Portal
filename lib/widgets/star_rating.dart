import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final double starSize;
  final Color starColor;

  const StarRating({super.key, required this.rating, this.starSize = 16, this.starColor = const Color(0xFFFFD700)});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: starSize, color: starColor),
        const SizedBox(width: 2),
        Text(
          rating == 0.0 ? '—' : rating.toStringAsFixed(1),
          style: TextStyle(color: starColor, fontSize: starSize * 0.8, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
