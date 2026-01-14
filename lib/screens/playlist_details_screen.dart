import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/debug_logger.dart';
import '../services/recently_played_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_picker_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';

class PlaylistDetailsScreen extends StatefulWidget {
  final Playlist playlist;
  final String? heroTagSuffix;
  /// Initial image URL from the source (e.g., PlaylistCard) for seamless hero animation
  final String? initialImageUrl;

  // Legacy constructor parameters for backward compatibility
  final String? provider;
  final String? itemId;

  const PlaylistDetailsScreen({
    super.key,
    required this.playlist,
    this.heroTagSuffix,
    this.initialImageUrl,
    this.provider,
    this.itemId,
  });

  @override
  State<PlaylistDetailsScreen> createState() => _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState extends State<PlaylistDetailsScreen> with SingleTickerProviderStateMixin {
  final _logger = DebugLogger();
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  int? _expandedTrackIndex;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  // Helper to get provider/itemId from widget or playlist
  String get _provider => widget.provider ?? widget.playlist.provider;
  String get _itemId => widget.itemId ?? widget.playlist.itemId;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.playlist.favorite ?? false;
    _loadTracks();

    // Defer color extraction until after hero animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _extractColors();
        }
      });
    });
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(widget.playlist, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      _logger.log('Failed to extract colors for playlist: $e');
    }
  }

  Future<void> _loadTracks() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final cacheKey = '${_provider}_$_itemId';

    // 1. Show cached data immediately (if available)
    final cachedTracks = maProvider.getCachedPlaylistTracks(cacheKey);
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = cachedTracks;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final freshTracks = await maProvider.getPlaylistTracksWithCache(
        _provider,
        _itemId,
        forceRefresh: cachedTracks != null,
      );

      // 3. Update if we got different data
      if (mounted && freshTracks.isNotEmpty) {
        final tracksChanged = _tracks.length != freshTracks.length ||
            (_tracks.isNotEmpty && freshTracks.isNotEmpty &&
             _tracks.first.itemId != freshTracks.first.itemId);
        if (tracksChanged || _tracks.isEmpty) {
          setState(() {
            _tracks = freshTracks;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Silent failure - keep showing cached data
      _logger.log('Background refresh failed: $e');
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        // For adding: use the actual provider and itemId from provider_mappings
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
        // For removing: need the library_item_id (numeric)
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
          throw Exception('Could not determine library ID for this playlist');
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
      _logger.log('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleTrackFavorite(int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return;

    final track = _tracks[trackIndex];
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = track.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        int? libraryItemId;
        if (track.provider == 'library') {
          libraryItemId = int.tryParse(track.itemId);
        } else if (track.providerMappings != null) {
          final libraryMapping = track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'track',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      } else {
        String actualProvider = track.provider;
        String actualItemId = track.itemId;

        if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
          final mapping = track.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => track.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => track.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          itemId: actualItemId,
          provider: actualProvider,
        );
      }

      if (success) {
        setState(() {
          _tracks[trackIndex] = Track(
            itemId: track.itemId,
            provider: track.provider,
            name: track.name,
            uri: track.uri,
            favorite: !currentFavorite,
            artists: track.artists,
            album: track.album,
            duration: track.duration,
            providerMappings: track.providerMappings,
          );
        });

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (!currentFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      _logger.log('Error toggling track favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _playPlaylist() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing playlist on ${player.name}');
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      _logger.log('Playlist queued successfully');

      RecentlyPlayedService.instance.recordPlaylistPlayed(widget.playlist);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.playingPlaylist(widget.playlist.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error playing playlist: $e');
      _showError('Error playing playlist: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing tracks on ${player.name} starting at index $index');
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      _logger.log('Tracks queued on ${player.name}');
    } catch (e) {
      _logger.log('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playTracks(player.playerId, _tracks);
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _addPlaylistToQueue() {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              S.of(context)!.addToQueueOn,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(S.of(context)!.noPlayersAvailable),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, playerIndex) {
                    final player = players[playerIndex];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          _logger.log('Adding playlist to queue on ${player.name}');
                          await maProvider.playTracks(
                            player.playerId,
                            _tracks,
                            startIndex: 0,
                            clearQueue: false,
                          );
                          _logger.log('Playlist added to queue on ${player.name}');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.tracksAddedToQueue),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error adding playlist to queue: $e');
                          _showError('Failed to add playlist to queue: $e');
                        }
                      },
                    );
                  },
                ),
              ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _addTrackToQueue(BuildContext context, int index) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    GlobalPlayerOverlay.hidePlayer();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              S.of(context)!.addToQueueOn,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(S.of(context)!.noPlayersAvailable),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: players.length,
                  itemBuilder: (context, playerIndex) {
                    final player = players[playerIndex];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await maProvider.playTracks(
                            player.playerId,
                            _tracks,
                            startIndex: index,
                            clearQueue: false,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.tracksAddedToQueue),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error adding to queue: $e');
                          _showError('Failed to add to queue: $e');
                        }
                      },
                    );
                  },
                ),
              ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _showPlayRadioMenu(BuildContext context, int trackIndex) {
    final maProvider = context.read<MusicAssistantProvider>();
    final track = _tracks[trackIndex];

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playRadio(player.playerId, track);
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show fullscreen playlist art overlay
  void _showFullscreenArt(String? imageUrl) {
    if (imageUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                  Navigator.of(context).pop();
                }
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      memCacheWidth: 1024,
                      memCacheHeight: 1024,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Use select() to reduce rebuilds
    final providerImageUrl = context.select<MusicAssistantProvider, String?>(
      (provider) => provider.getImageUrl(widget.playlist, size: 512),
    );
    final imageUrl = providerImageUrl ?? widget.initialImageUrl;
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
            // Responsive cover size: 70% of screen width, clamped between 200-320
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
                        GestureDetector(
                          onTap: () => _showFullscreenArt(imageUrl),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Hero(
                              tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + _heroTagSuffix,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: coverSize,
                                  height: coverSize,
                                  color: colorScheme.surfaceContainerHighest,
                                  child: imageUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 256,
                                          memCacheHeight: 256,
                                          fadeInDuration: Duration.zero,
                                          fadeOutDuration: Duration.zero,
                                          placeholder: (_, __) => const SizedBox(),
                                          errorWidget: (_, __, ___) => Icon(
                                            Icons.playlist_play_rounded,
                                            size: coverSize * 0.43,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : Icon(
                                          Icons.playlist_play_rounded,
                                          size: coverSize * 0.43,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
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
                    padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Playlist title with Hero animation
                        Hero(
                          tag: HeroTags.playlistTitle + (widget.playlist.uri ?? widget.playlist.itemId) + _heroTagSuffix,
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              widget.playlist.name,
                              style: textTheme.headlineMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Owner info
                        if (widget.playlist.owner != null)
                          Text(
                            S.of(context)!.byOwner(widget.playlist.owner!),
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Track count
                        Text(
                          S.of(context)!.trackCount(_tracks.isNotEmpty ? _tracks.length : (widget.playlist.trackCount ?? 0)),
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Action buttons row
                        Row(
                          children: [
                            // Main Play Button
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading || _tracks.isEmpty ? null : _playPlaylist,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text(S.of(context)!.play),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    disabledBackgroundColor: colorScheme.primary.withOpacity(0.38),
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
                                onPressed: _isLoading || _tracks.isEmpty ? null : () => _showPlayOnMenu(context),
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

                            // "Add to Queue" Button
                            SizedBox(
                              height: 50,
                              width: 50,
                              child: FilledButton.tonal(
                                onPressed: _isLoading || _tracks.isEmpty ? null : _addPlaylistToQueue,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(Icons.playlist_add),
                              ),
                            ),

                            const SizedBox(width: 12),

                            // Favorite Button
                            SizedBox(
                              height: 50,
                              width: 50,
                              child: FilledButton.tonal(
                                onPressed: _toggleFavorite,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(Radii.xxl),
                                  ),
                                ),
                                child: Icon(
                                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                                  color: _isFavorite
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: colorScheme.primary),
                    ),
                  )
                else if (_tracks.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        S.of(context)!.noTracksInPlaylist,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.54),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = _tracks[index];
                        final isExpanded = _expandedTrackIndex == index;
                        final trackImageUrl = context.read<MusicAssistantProvider>().getImageUrl(track, size: 80);

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Track number
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${index + 1}',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface.withOpacity(0.5),
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Track artwork
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      color: colorScheme.surfaceContainerHighest,
                                      child: trackImageUrl != null
                                          ? CachedNetworkImage(
                                              imageUrl: trackImageUrl,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 96,
                                              memCacheHeight: 96,
                                              fadeInDuration: Duration.zero,
                                              fadeOutDuration: Duration.zero,
                                              placeholder: (_, __) => const SizedBox(),
                                              errorWidget: (_, __, ___) => Icon(
                                                Icons.music_note,
                                                size: 24,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            )
                                          : Icon(
                                              Icons.music_note,
                                              size: 24,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text(
                                track.name,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                track.artistsString,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: track.duration != null
                                  ? Text(
                                      _formatDuration(track.duration!),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurface.withOpacity(0.5),
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                if (isExpanded) {
                                  setState(() {
                                    _expandedTrackIndex = null;
                                  });
                                } else {
                                  _playTrack(index);
                                }
                              },
                              onLongPress: () {
                                setState(() {
                                  _expandedTrackIndex = isExpanded ? null : index;
                                });
                              },
                            ),
                            // Expandable action buttons
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: isExpanded
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 16.0, bottom: 12.0, top: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          // Radio button
                                          SizedBox(
                                            height: 44,
                                            width: 44,
                                            child: FilledButton.tonal(
                                              onPressed: () => _showPlayRadioMenu(context, index),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Icon(Icons.radio, size: 20),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // Add to queue button
                                          SizedBox(
                                            height: 44,
                                            width: 44,
                                            child: FilledButton.tonal(
                                              onPressed: () => _addTrackToQueue(context, index),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Icon(Icons.playlist_add, size: 20),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // Favorite button
                                          SizedBox(
                                            height: 44,
                                            width: 44,
                                            child: FilledButton.tonal(
                                              onPressed: () => _toggleTrackFavorite(index),
                                              style: FilledButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(Radii.xxl),
                                                ),
                                              ),
                                              child: Icon(
                                                track.favorite == true ? Icons.favorite : Icons.favorite_border,
                                                size: 20,
                                                color: track.favorite == true
                                                    ? colorScheme.error
                                                    : colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      },
                      childCount: _tracks.length,
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)), // Space for bottom nav + mini player
              ],
            );
          },
        ),
      ),
    );
  }
}
