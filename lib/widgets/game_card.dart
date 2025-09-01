import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/game_thread.dart';
import '../utils/formatters.dart';
import 'cover_image.dart';
import 'engine_tag.dart';
import 'version_pill.dart';
import 'star_rating.dart';
import 'metadata_row.dart';

class GameCard extends StatelessWidget {
  final GameThread game;
  final VoidCallback? onTap;

  const GameCard({super.key, required this.game, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image section
            Stack(
              children: [
                // Cover image with top border radius matching card
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    topRight: Radius.circular(11),
                  ),
                  child: CoverImage(imageUrl: game.cover),
                ),

                // Engine tag (top-left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: EngineTag(
                    engines: GameUtils.getEnginesFromGame(
                      game.prefixes,
                      game.tags,
                    ),
                  ),
                ),

                // Version pill (top-right)
                Positioned(
                  top: 8,
                  right: 8,
                  child: VersionPill(
                    version: game.version,
                    isCompleted: game.isCompleted,
                    isAbandoned: game.isAbandoned,
                    isOnhold: game.isOnhold,
                  ),
                ),

                // Star rating (bottom-right)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: StarRating(rating: game.rating),
                ),
              ],
            ),

            // Content section with padding
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(11.0),
                bottomRight: Radius.circular(11.0),
              ),
              child: RepaintBoundary(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Cover image reflection
                    Positioned.fill(
                      child: ClipRect(
                        child: OverflowBox(
                          // These settings should mirror whatever layout the
                          // main CoverImage is using to overflow.
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: Transform.scale(
                            scaleY: -1,
                            child: CoverImage(imageUrl: game.cover),
                          ),
                        ),
                      ),
                    ),

                    // Cover image filter layer
                    Positioned(
                      top: -1,
                      left: -1,
                      right: -1,
                      bottom: -1,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(11.0),
                          bottomRight: Radius.circular(11.0),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 2),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(11.0),
                                bottomRight: Radius.circular(11.0),
                              ),
                              border: const Border(
                                top: BorderSide(
                                  color: Color.fromARGB(127, 0, 0, 0),
                                  width: 1,
                                ),
                              ),
                              // gradient: LinearGradient(
                              //   begin: Alignment.topCenter,
                              //   end: Alignment(0.0, 0.4),
                              //   colors: [
                              //     Colors.black.withValues(alpha: 0),
                              //     Colors.black.withValues(alpha: 0.8),
                              //     Colors.black.withValues(alpha: 1),
                              //   ],
                              //   stops: [0.0, 0.4, 0.7],
                              // ),
                              gradient: RadialGradient(
                                center: Alignment(0, -1),
                                radius: 4,
                                colors: [
                                  Colors.black.withValues(alpha: 0.4),
                                  Colors.black.withValues(alpha: 0.75),
                                  Colors.black.withValues(alpha: 1),
                                ],
                                stops: [0, 0.4, 0.8],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Foreground content (defines the size of the Stack)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Game title
                          Text(
                            game.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Metadata row
                          MetadataRow(
                            timeUpdated: game.date,
                            likes: game.likes,
                            views: game.views,
                          ),
                        ],
                      ),
                    ),
                    // Positioned(
                    //   bottom: -1,
                    //   left: 0,
                    //   right: 0,
                    //   child: Container(height: 1, color: Colors.black),
                    // ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
