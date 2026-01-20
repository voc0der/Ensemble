import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/playlist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import 'package:ensemble/services/image_cache_service.dart';

class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(widget.playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
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
              child: PlaylistDetailsScreen(
                playlist: widget.playlist,
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
            // Playlist artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
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
                                Icons.playlist_play_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.playlist_play_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Playlist title
            Hero(
              tag: HeroTags.playlistTitle + (widget.playlist.uri ?? widget.playlist.itemId) + suffix,
              child: Material(
                color: Colors.transparent,
                child: Text(
                  widget.playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            // Owner/track count
            Text(
              widget.playlist.owner ?? (widget.playlist.trackCount != null ? '${widget.playlist.trackCount} tracks' : ''),
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
}
