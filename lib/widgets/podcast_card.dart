import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/podcast_detail_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import 'package:ensemble/services/image_cache_service.dart';

class PodcastCard extends StatefulWidget {
  final MediaItem podcast;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  /// Image decode size in pixels. Defaults to 256.
  /// Use smaller values (e.g., 128) for list views, larger for grids.
  final int? imageCacheSize;

  const PodcastCard({
    super.key,
    required this.podcast,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<PodcastCard> createState() => _PodcastCardState();
}

class _PodcastCardState extends State<PodcastCard> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use provider's getPodcastImageUrl which includes iTunes cache
    final imageUrl = maProvider.getPodcastImageUrl(widget.podcast, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // PERF: Use appropriate cache size based on display size
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap navigation
          if (_isNavigating) return;
          _isNavigating = true;

          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PodcastDetailScreen(
                podcast: widget.podcast,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          ).then((_) {
            // Reset after navigation debounce delay
            Future.delayed(Timings.navigationDebounce, () {
              if (mounted) _isNavigating = false;
            });
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Podcast artwork - square with rounded corners
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.podcastCover + (widget.podcast.uri ?? widget.podcast.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    color: colorScheme.surfaceVariant,
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
                                MdiIcons.podcast,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              MdiIcons.podcast,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Podcast title
            Hero(
              tag: HeroTags.podcastTitle + (widget.podcast.uri ?? widget.podcast.itemId) + suffix,
              child: Material(
                color: Colors.transparent,
                child: Text(
                  widget.podcast.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Podcast author (if available)
            Text(
              _getAuthor(widget.podcast),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract author from podcast metadata
  String _getAuthor(MediaItem podcast) {
    final metadata = podcast.metadata;
    if (metadata == null) return '';

    // Try different metadata fields for author
    final author = metadata['author'] ??
                   metadata['artist'] ??
                   metadata['owner'] ?? '';
    return author.toString();
  }
}
