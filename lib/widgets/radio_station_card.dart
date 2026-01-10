import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';

class RadioStationCard extends StatelessWidget {
  final MediaItem radioStation;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const RadioStationCard({
    super.key,
    required this.radioStation,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(radioStation, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = heroTagSuffix != null ? '_$heroTagSuffix' : '';
    final cacheSize = imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap ?? () {
          HapticFeedback.mediumImpact();
          // Play the radio station on selected player
          final selectedPlayer = maProvider.selectedPlayer;
          if (selectedPlayer != null) {
            maProvider.api?.playRadioStation(selectedPlayer.playerId, radioStation);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio station artwork - circular for radio
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.radioCover + (radioStation.uri ?? radioStation.itemId) + suffix,
                child: ClipOval(
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: cacheSize,
                            memCacheHeight: cacheSize,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => const SizedBox(),
                            errorWidget: (context, url, error) => Center(
                              child: Icon(
                                Icons.radio_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.radio_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Radio station name - fixed height container so image size is consistent
            SizedBox(
              height: 36, // Fixed height for 2 lines of text
              child: Hero(
                tag: HeroTags.radioTitle + (radioStation.uri ?? radioStation.itemId) + suffix,
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    radioStation.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
