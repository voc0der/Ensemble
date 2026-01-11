import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/playlist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import '../l10n/app_localizations.dart';
import '../services/debug_logger.dart';

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
  final _logger = DebugLogger();
  late bool _isFavorite;
  bool _showFavoriteOverlay = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.playlist.favorite ?? false;
  }

  @override
  void didUpdateWidget(PlaylistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.favorite != widget.playlist.favorite) {
      _isFavorite = widget.playlist.favorite ?? false;
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show overlay briefly
    setState(() => _showFavoriteOverlay = true);

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        // Adding to favorites
        String actualProvider = widget.playlist.provider;
        String actualItemId = widget.playlist.itemId;

        if (widget.playlist.providerMappings != null && widget.playlist.providerMappings!.isNotEmpty) {
          final mapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.playlist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.playlist.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding playlist to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'playlist',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // Removing from favorites
        int? libraryItemId;

        if (widget.playlist.provider == 'library') {
          libraryItemId = int.tryParse(widget.playlist.itemId);
        } else if (widget.playlist.providerMappings != null) {
          final libraryMapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.playlist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          throw Exception('Could not determine library ID');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'playlist',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        setState(() {
          _isFavorite = newState;
        });

        maProvider.invalidateHomeCache();

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (_isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _logger.log('Error toggling playlist favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    // Hide overlay after animation
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _showFavoriteOverlay = false);
    }
  }

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
          );
        },
        onLongPress: _toggleFavorite,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist artwork with favorite overlay
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  Hero(
                    tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + suffix,
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
                  // Favorite indicator (always shown if favorite)
                  if (_isFavorite)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 16,
                        ),
                      ),
                    ),
                  // Animated favorite overlay on long-press
                  if (_showFavoriteOverlay)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Container(
                          color: Colors.black54,
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.5, end: 1.0),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.elasticOut,
                              builder: (context, scale, child) {
                                return Transform.scale(
                                  scale: scale,
                                  child: Icon(
                                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                                    color: _isFavorite ? Colors.red : Colors.white,
                                    size: 48,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
