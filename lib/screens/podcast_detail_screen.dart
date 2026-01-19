import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_picker_sheet.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/debug_logger.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';

class PodcastDetailScreen extends StatefulWidget {
  final MediaItem podcast;
  final String? heroTagSuffix;
  final String? initialImageUrl;

  const PodcastDetailScreen({
    super.key,
    required this.podcast,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<PodcastDetailScreen> createState() => _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends State<PodcastDetailScreen> {
  final _logger = DebugLogger();
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  List<MediaItem> _episodes = [];
  bool _isLoadingEpisodes = false;
  bool _isDescriptionExpanded = false;
  bool _isInLibrary = false;
  String? _expandedEpisodeId; // Track which episode is expanded for actions

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isInLibrary = _checkIfInLibrary(widget.podcast);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _extractColors();
        }
      });
      _loadEpisodes();
    });
  }

  /// Check if podcast is in library
  bool _checkIfInLibrary(MediaItem podcast) {
    if (podcast.provider == 'library') return true;
    return podcast.providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  /// Toggle library status
  Future<void> _toggleLibrary() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isInLibrary;

      if (newState) {
        // Add to library - MUST use non-library provider
        String? actualProvider;
        String? actualItemId;

        if (widget.podcast.providerMappings != null && widget.podcast.providerMappings!.isNotEmpty) {
          // For adding to library, we MUST use a non-library provider
          final nonLibraryMapping = widget.podcast.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        // Fallback to item's own provider if no non-library mapping found
        if (actualProvider == null || actualItemId == null) {
          if (widget.podcast.provider != 'library') {
            actualProvider = widget.podcast.provider;
            actualItemId = widget.podcast.itemId;
          } else {
            // Item is library-only, can't add
            _logger.log('Cannot add to library: podcast is library-only');
            return;
          }
        }

        // OPTIMISTIC UPDATE: Update UI immediately
        setState(() {
          _isInLibrary = newState;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.addedToLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        _logger.log('Adding podcast to library: provider=$actualProvider, itemId=$actualItemId');
        // Fire and forget - API call happens in background
        maProvider.addToLibrary(
          mediaType: 'podcast',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to add podcast to library: $e');
          // Revert on failure
          if (mounted) {
            setState(() {
              _isInLibrary = !newState;
            });
          }
          return false;
        });
      } else {
        // Remove from library
        int? libraryItemId;
        if (widget.podcast.provider == 'library') {
          libraryItemId = int.tryParse(widget.podcast.itemId);
        } else if (widget.podcast.providerMappings != null) {
          final libraryMapping = widget.podcast.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.podcast.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Cannot remove from library: no library ID found');
          return;
        }

        // OPTIMISTIC UPDATE: Update UI immediately
        setState(() {
          _isInLibrary = newState;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context)!.removedFromLibrary),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        // Fire and forget - API call happens in background
        maProvider.removeFromLibrary(
          mediaType: 'podcast',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to remove podcast from library: $e');
          // Revert on failure
          if (mounted) {
            setState(() {
              _isInLibrary = !newState;
            });
          }
          return false;
        });
      }
    } catch (e) {
      _logger.log('Error toggling podcast library: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update library: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use initialImageUrl first for consistency with hero animation
    final imageUrl = widget.initialImageUrl ?? maProvider.getPodcastImageUrl(widget.podcast);

    if (imageUrl != null) {
      try {
        final colorSchemes = await PaletteHelper.extractColorSchemes(
          CachedNetworkImageProvider(imageUrl),
        );
        if (mounted && colorSchemes != null) {
          setState(() {
            _lightColorScheme = colorSchemes.$1;
            _darkColorScheme = colorSchemes.$2;
          });
        }
      } catch (e) {
        _logger.log('🎙️ Error extracting colors: $e');
      }
    }
  }

  Future<void> _loadEpisodes() async {
    if (_isLoadingEpisodes) return;

    setState(() {
      _isLoadingEpisodes = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.api != null) {
        List<MediaItem> episodes = [];

        // Try loading with the podcast's own ID and provider first
        try {
          episodes = await maProvider.api!.getPodcastEpisodes(
            widget.podcast.itemId,
            provider: widget.podcast.provider,
          );
        } catch (e) {
          _logger.log('🎙️ Primary episode load failed: $e');
        }

        // If that failed and we have provider mappings, try those
        if (episodes.isEmpty && widget.podcast.providerMappings != null) {
          for (final mapping in widget.podcast.providerMappings!) {
            if (mapping.itemId.isNotEmpty && mapping.providerInstance.isNotEmpty) {
              try {
                _logger.log('🎙️ Trying provider mapping: ${mapping.providerInstance}');
                episodes = await maProvider.api!.getPodcastEpisodes(
                  mapping.itemId,
                  provider: mapping.providerInstance,
                );
                if (episodes.isNotEmpty) {
                  _logger.log('🎙️ Loaded episodes via provider mapping');
                  break;
                }
              } catch (e) {
                _logger.log('🎙️ Provider mapping failed: $e');
              }
            }
          }
        }

        if (mounted) {
          _logger.log('🎙️ Loaded ${episodes.length} episodes for ${widget.podcast.name}');
          // Debug: Log first episode metadata to see available fields
          if (episodes.isNotEmpty) {
            final first = episodes.first;
            _logger.log('🎙️ First episode metadata keys: ${first.metadata?.keys.toList()}');
            _logger.log('🎙️ First episode metadata: ${first.metadata}');
          }
          setState(() {
            _episodes = episodes;
          });
        }
      }
    } catch (e) {
      _logger.log('🎙️ Error loading episodes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEpisodes = false;
        });
      }
    }
  }

  void _playEpisode(MediaItem episode) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer != null) {
      try {
        // Set podcast context before playing so player UI shows correct podcast name
        maProvider.setCurrentPodcastName(widget.podcast.name);
        await maProvider.api?.playPodcastEpisode(selectedPlayer.playerId, episode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing: ${episode.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        _logger.log('🎙️ Error playing episode: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to play episode: $e')),
          );
        }
      }
    } else {
      _showPlayOnMenu(context, episode);
    }
  }

  void _showPlayOnMenu(BuildContext context, MediaItem episode) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        // Set podcast context before playing so player UI shows correct podcast name
        maProvider.setCurrentPodcastName(widget.podcast.name);
        await maProvider.api?.playPodcastEpisode(player.playerId, episode);
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes} min';
  }

  /// Format release date from episode metadata
  /// Tries various common field names for publication date
  String? _formatReleaseDate(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;

    // Try various common field names for publication date
    dynamic dateValue = metadata['published'] ??
        metadata['pub_date'] ??
        metadata['release_date'] ??
        metadata['aired'] ??
        metadata['timestamp'];

    if (dateValue == null) return null;

    try {
      DateTime? date;
      if (dateValue is String) {
        date = DateTime.tryParse(dateValue);
      } else if (dateValue is int) {
        // Unix timestamp
        date = DateTime.fromMillisecondsSinceEpoch(dateValue * 1000);
      }

      if (date != null) {
        // Format as "Jan 15, 2024"
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    } catch (e) {
      _logger.log('🎙️ Error parsing release date: $e');
    }

    return null;
  }

  /// Add episode to queue on current player
  Future<void> _addToQueue(MediaItem episode) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      // Convert MediaItem to Track for queue addition
      final track = Track(
        itemId: episode.itemId,
        provider: episode.provider,
        name: episode.name,
        uri: episode.uri,
        duration: episode.duration,
        metadata: episode.metadata,
      );
      await maProvider.addTrackToQueue(selectedPlayer.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('🎙️ Error adding episode to queue: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use select() instead of watch() to prevent rebuilds during Hero animation
    // watch() rebuilds on ANY provider change (library updates, etc.) causing animation jank
    // select() only rebuilds when the specific podcast image URL changes
    final providerImageUrl = context.select<MusicAssistantProvider, String?>(
      (provider) => provider.getPodcastImageUrl(widget.podcast),
    );
    // Use initialImageUrl for seamless hero animation (same URL as source)
    final imageUrl = widget.initialImageUrl ?? providerImageUrl;

    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      adaptiveScheme = isDark
          ? (_darkColorScheme ?? adaptiveDarkScheme)
          : (_lightColorScheme ?? adaptiveLightScheme);
    }
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final description = widget.podcast.metadata?['description'] as String?;
    final author = widget.podcast.metadata?['author'] as String?;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          clearAdaptiveColorsOnBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = (constraints.maxWidth * 0.7).clamp(200.0, 320.0);
            final expandedHeight = coverSize + 70;

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: expandedHeight,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      clearAdaptiveColorsOnBack(context);
                      Navigator.pop(context);
                    },
                    color: colorScheme.onSurface,
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Hero(
                          tag: HeroTags.podcastCover + (widget.podcast.uri ?? widget.podcast.itemId) + _heroTagSuffix,
                          // Match audiobook pattern: ClipRRect + CachedNetworkImage for smooth hero
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: coverSize,
                              height: coverSize,
                              color: colorScheme.surfaceContainerHighest,
                              child: imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      // Match source memCacheWidth for smooth Hero animation
                                      memCacheWidth: 256,
                                      memCacheHeight: 256,
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      placeholder: (_, __) => Center(
                                        child: Icon(
                                          MdiIcons.podcast,
                                          size: coverSize * 0.43,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Center(
                                        child: Icon(
                                          MdiIcons.podcast,
                                          size: coverSize * 0.43,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        MdiIcons.podcast,
                                        size: coverSize * 0.43,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Podcast title
                        Text(
                          widget.podcast.name,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (author != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            author,
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Action buttons row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              // Main Play Latest Episode Button
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoadingEpisodes || _episodes.isEmpty
                                        ? null
                                        : () => _playEpisode(_episodes.first),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: Text(S.of(context)!.play),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colorScheme.primary,
                                      foregroundColor: colorScheme.onPrimary,
                                      disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
                                      disabledForegroundColor: colorScheme.onPrimary.withOpacity(0.38),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // "Play on..." Button
                              SizedBox(
                                height: 50,
                                width: 50,
                                child: FilledButton.tonal(
                                  onPressed: _isLoadingEpisodes || _episodes.isEmpty
                                      ? null
                                      : () => _showPlayOnMenu(context, _episodes.first),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Icon(Icons.speaker_group_outlined),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Library button
                              SizedBox(
                                height: 50,
                                width: 50,
                                child: FilledButton.tonal(
                                  onPressed: _toggleLibrary,
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Icon(
                                    _isInLibrary ? Icons.library_add_check : Icons.library_add,
                                    color: _isInLibrary
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Description
                        if (description != null && description.isNotEmpty) ...[
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isDescriptionExpanded = !_isDescriptionExpanded;
                              });
                            },
                            child: AnimatedCrossFade(
                              firstChild: Text(
                                description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              secondChild: Text(
                                description,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              crossFadeState: _isDescriptionExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 200),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Episodes header
                        Row(
                          children: [
                            Text(
                              S.of(context)!.episodes,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_episodes.isNotEmpty)
                              Text(
                                '(${_episodes.length})',
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Episodes list
                if (_isLoadingEpisodes)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: colorScheme.primary),
                      ),
                    ),
                  )
                else if (_episodes.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              MdiIcons.microphoneOff,
                              size: 48,
                              color: colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No episodes found',
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final episode = _episodes[index];
                        final episodeDescription = episode.metadata?['description'] as String?;
                        final duration = episode.duration;
                        final episodeId = episode.uri ?? episode.itemId;
                        final isExpanded = _expandedEpisodeId == episodeId;
                        final episodeImageUrl = context.read<MusicAssistantProvider>().getImageUrl(episode, size: 256);

                        // Try to get release date from metadata
                        final releaseDate = _formatReleaseDate(episode.metadata);

                        return Column(
                          children: [
                            InkWell(
                              onTap: () => _playEpisode(episode),
                              onLongPress: () {
                                setState(() {
                                  _expandedEpisodeId = isExpanded ? null : episodeId;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Episode cover (bigger than before)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        color: colorScheme.surfaceContainerHighest,
                                        child: episodeImageUrl != null
                                            ? CachedNetworkImage(
                                                imageUrl: episodeImageUrl,
                                                fit: BoxFit.cover,
                                                fadeInDuration: Duration.zero,
                                                fadeOutDuration: Duration.zero,
                                                placeholder: (_, __) => Icon(
                                                  MdiIcons.podcast,
                                                  size: 32,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                                errorWidget: (_, __, ___) => Icon(
                                                  MdiIcons.podcast,
                                                  size: 32,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              )
                                            : Icon(
                                                MdiIcons.podcast,
                                                size: 32,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Episode info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            episode.name,
                                            style: textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (episodeDescription != null && episodeDescription.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              episodeDescription,
                                              maxLines: isExpanded ? 100 : 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurface.withOpacity(0.6),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          // Duration and release date row
                                          Row(
                                            children: [
                                              if (duration != null && duration > Duration.zero) ...[
                                                Icon(
                                                  Icons.access_time,
                                                  size: 14,
                                                  color: colorScheme.onSurface.withOpacity(0.5),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatDuration(duration),
                                                  style: textTheme.bodySmall?.copyWith(
                                                    color: colorScheme.onSurface.withOpacity(0.5),
                                                  ),
                                                ),
                                              ],
                                              if (duration != null && duration > Duration.zero && releaseDate != null)
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    '•',
                                                    style: textTheme.bodySmall?.copyWith(
                                                      color: colorScheme.onSurface.withOpacity(0.5),
                                                    ),
                                                  ),
                                                ),
                                              if (releaseDate != null)
                                                Text(
                                                  releaseDate,
                                                  style: textTheme.bodySmall?.copyWith(
                                                    color: colorScheme.onSurface.withOpacity(0.5),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Expanded action buttons (matching album track style)
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Padding(
                                padding: const EdgeInsets.only(left: 100, right: 16, bottom: 12),
                                child: Row(
                                  children: [
                                    // Play button
                                    SizedBox(
                                      height: 44,
                                      width: 44,
                                      child: FilledButton.tonal(
                                        onPressed: () => _playEpisode(episode),
                                        style: FilledButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(Icons.play_arrow, size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Play on... button
                                    SizedBox(
                                      height: 44,
                                      width: 44,
                                      child: FilledButton.tonal(
                                        onPressed: () => _showPlayOnMenu(context, episode),
                                        style: FilledButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(Icons.speaker_group_outlined, size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Add to queue button
                                    SizedBox(
                                      height: 44,
                                      width: 44,
                                      child: FilledButton.tonal(
                                        onPressed: () => _addToQueue(episode),
                                        style: FilledButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(Icons.playlist_add, size: 20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              crossFadeState: isExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 200),
                            ),
                          ],
                        );
                      },
                      childCount: _episodes.length,
                    ),
                  ),

                // Bottom padding for mini player
                SliverToBoxAdapter(
                  child: SizedBox(height: BottomSpacing.withMiniPlayer),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
