import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/playlist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';

class PlaylistCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = heroTagSuffix != null ? '_$heroTagSuffix' : '';
    final cacheSize = imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap ?? () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PlaylistDetailsScreen(
                playlist: playlist,
                heroTagSuffix: heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.playlistCover + (playlist.uri ?? playlist.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
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
            const SizedBox(height: 8),
            // Playlist title
            Hero(
              tag: HeroTags.playlistTitle + (playlist.uri ?? playlist.itemId) + suffix,
              child: Material(
                color: Colors.transparent,
                child: Text(
                  playlist.name,
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
              playlist.owner ?? (playlist.trackCount != null ? '${playlist.trackCount} tracks' : ''),
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
