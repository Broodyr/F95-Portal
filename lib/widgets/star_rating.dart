import 'package:flutter/material.dart';

/// Five stars with half-marks, the score rounded to the nearest half.
/// The numeric companion to this is [StarRating]; this is the shape the
/// forum itself draws for thread scores and review ratings.
class StarBar extends StatelessWidget {
  final double rating;
  final double starSize;
  final Color starColor;

  const StarBar({super.key, required this.rating, this.starSize = 16, this.starColor = const Color(0xFFFFD700)});

  @override
  Widget build(BuildContext context) {
    final int halves = (rating * 2).round().clamp(0, 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int star = 0; star < 5; star++)
          Icon(
            halves >= (star + 1) * 2
                ? Icons.star
                : halves == star * 2 + 1
                ? Icons.star_half
                : Icons.star_border,
            size: starSize,
            color: starColor,
          ),
      ],
    );
  }
}

/// Five tappable stars for picking a whole-star rating (the review sheet).
/// Unlike the site's hover widget, each star is a full-size touch target.
class StarPicker extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  final double starSize;
  final Color starColor;

  const StarPicker({
    super.key,
    required this.rating,
    required this.onChanged,
    this.starSize = 34,
    this.starColor = const Color(0xFFFFD700),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int star = 1; star <= 5; star++)
          Semantics(
            button: true,
            label: '$star star${star == 1 ? '' : 's'}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(star),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(
                  star <= rating ? Icons.star : Icons.star_border,
                  size: starSize,
                  color: starColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

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
