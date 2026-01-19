import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import 'package:ensemble/services/image_cache_service.dart';

class RadioStationCard extends StatefulWidget {
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
  State<RadioStationCard> createState() => _RadioStationCardState();
}

class _RadioStationCardState extends State<RadioStationCard> {
  bool _isTapping = false;

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(widget.radioStation, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap actions
          if (_isTapping) return;
          _isTapping = true;

          HapticFeedback.mediumImpact();
          // Play the radio station on selected player
          final selectedPlayer = maProvider.selectedPlayer;
          if (selectedPlayer != null) {
            maProvider.api?.playRadioStation(selectedPlayer.playerId, widget.radioStation);
          }

          // Reset after debounce delay
          Future.delayed(Timings.navigationDebounce, () {
            if (mounted) _isTapping = false;
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio station artwork - circular for radio
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.radioCover + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: ClipOval(
                  child: Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: imageUrl != null
                        ? CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
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
                tag: HeroTags.radioTitle + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    widget.radioStation.name,
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
