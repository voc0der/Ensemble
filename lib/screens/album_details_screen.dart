import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../core/ui_notify.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../services/recently_played_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_picker_sheet.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import 'artist_details_screen.dart';
import 'package:ensemble/services/image_cache_service.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final Album album;
  final String? heroTagSuffix;
  /// Initial image URL from the source (e.g., AlbumCard) for seamless hero animation
  final String? initialImageUrl;

  const AlbumDetailsScreen({
    super.key,
    required this.album,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<AlbumDetailsScreen> createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> with SingleTickerProviderStateMixin {
  final _logger = DebugLogger();
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _isInLibrary = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  int? _expandedTrackIndex;
  bool _isDescriptionExpanded = false;
  String? _albumDescription;
  Album? _freshAlbum; // Full album data with image metadata

  /// Get the best album data available (fresh with images, or widget.album as fallback)
  Album get _displayAlbum => _freshAlbum ?? widget.album;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.album.favorite ?? false;
    _isInLibrary = widget.album.inLibrary;
    _loadTracks();
    _loadAlbumDescription();

    // CRITICAL FIX: Defer both fresh data loading AND color extraction until
    // after the hero animation completes. This prevents:
    // 1. setState with new image URL during animation → grey icon flash
    // 2. Expensive palette extraction blocking animation frames
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 350ms matches FadeSlidePageRoute duration (300ms) + buffer
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _loadFreshAlbumData();
          _extractColors();
        }
      });
    });
  }

  /// Load fresh album data from API to get full metadata including images
  Future<void> _loadFreshAlbumData() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    // Need a URI to fetch fresh album data
    final albumUri = widget.album.uri;
    if (albumUri == null || albumUri.isEmpty) {
      _logger.log('Cannot load fresh album: album has no URI');
      return;
    }

    try {
      final freshAlbum = await maProvider.api!.getAlbumByUri(albumUri);
      if (freshAlbum != null && mounted) {
        setState(() {
          _freshAlbum = freshAlbum;
          _isFavorite = freshAlbum.favorite ?? false;
        });
        // Re-extract colors now that we have fresh album with images
        _extractColors();
      }
    } catch (e) {
      _logger.log('Error loading fresh album data: $e');
    }
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(_displayAlbum, size: 512);

    if (imageUrl == null) return;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl, cacheManager: AuthenticatedCacheManager.instance),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      _logger.log('Failed to extract colors for album: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        // For adding: use the actual provider and itemId from provider_mappings
        String actualProvider = widget.album.provider;
        String actualItemId = widget.album.itemId;

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          // Find a non-library provider mapping (e.g., spotify, qobuz, etc.)
          final mapping = widget.album.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.album.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.album.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'album',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // For removing: need the library_item_id (numeric)
        int? libraryItemId;

        if (widget.album.provider == 'library') {
          libraryItemId = int.tryParse(widget.album.itemId);
        } else if (widget.album.providerMappings != null) {
          final libraryMapping = widget.album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.album.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          throw Exception('Could not determine library ID for this album');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'album',
          libraryItemId: libraryItemId,
        );
      }

      if (success) {
        // Optimistically update UI regardless of online/offline state
        setState(() {
          _isFavorite = newState;
        });

        // Invalidate home cache so the home screen shows updated favorite status
        maProvider.invalidateHomeCache();

        if (mounted) {
          final isOffline = !maProvider.isConnected;
          final message = isOffline
              ? S.of(context)!.actionQueuedForSync
              : (_isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites);
          UiNotify.info(message);
        }
      }
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
      if (mounted) {
        UiNotify.error(S.of(context)!.failedToUpdateFavorite(e.toString()));
      }
    }
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

        if (widget.album.providerMappings != null && widget.album.providerMappings!.isNotEmpty) {
          // For adding to library, we MUST use a non-library provider
          final nonLibraryMapping = widget.album.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        // Fallback to item's own provider if no non-library mapping found
        if (actualProvider == null || actualItemId == null) {
          if (widget.album.provider != 'library') {
            actualProvider = widget.album.provider;
            actualItemId = widget.album.itemId;
          } else {
            // Item is library-only, can't add
            _logger.log('Cannot add to library: album is library-only');
            return;
          }
        }

        // OPTIMISTIC UPDATE: Update UI immediately
        setState(() {
          _isInLibrary = newState;
        });

        if (mounted) {
          UiNotify.info(S.of(context)!.addedToLibrary);
        }

        _logger.log('Adding album to library: provider=$actualProvider, itemId=$actualItemId');
        // Fire and forget - API call happens in background
        maProvider.addToLibrary(
          mediaType: 'album',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to add album to library: $e');
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
        if (widget.album.provider == 'library') {
          libraryItemId = int.tryParse(widget.album.itemId);
        } else if (widget.album.providerMappings != null) {
          final libraryMapping = widget.album.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.album.providerMappings!.first,
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
          mediaType: 'album',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to remove album from library: $e');
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
      _logger.log('Error toggling album library: $e');
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

  Future<void> _toggleTrackFavorite(int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return;

    final track = _tracks[trackIndex];
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = track.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites - need library_item_id
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
        // Add to favorites
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
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
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
        // Optimistically update local state
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

  Future<void> _loadTracks() async {
    final provider = context.read<MusicAssistantProvider>();
    final cacheKey = '${widget.album.provider}_${widget.album.itemId}';

    // 1. Show cached data immediately (if available)
    final cachedTracks = provider.getCachedAlbumTracks(cacheKey);
    if (cachedTracks != null && cachedTracks.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = cachedTracks;
          _isLoading = false;
        });
      }
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final freshTracks = await provider.getAlbumTracksWithCache(
        widget.album.provider,
        widget.album.itemId,
        forceRefresh: cachedTracks != null, // Force refresh if we had cache
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
      _logger.log('⚠️ Background refresh failed: $e');
    }

    // Ensure loading is false even if everything failed
    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _playAlbum() async {
    if (_tracks.isEmpty) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing album on ${player.name}: ${player.playerId}');

      // Queue all tracks via Music Assistant
      await maProvider.playTracks(player.playerId, _tracks, startIndex: 0);
      _logger.log('Album queued on ${player.name}');

      // Record to local recently played (per-profile)
      RecentlyPlayedService.instance.recordAlbumPlayed(widget.album);
      // Stay on album page - mini player will appear
    } catch (e) {
      _logger.log('Error playing album: $e');
      _showError('Failed to play album: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      // Use the selected player
      final player = maProvider.selectedPlayer;
      if (player == null) {
        _showError(S.of(context)!.noPlayerSelected);
        return;
      }

      _logger.log('Queueing tracks on ${player.name} starting at index $index');

      // Queue tracks starting at the selected index
      await maProvider.playTracks(player.playerId, _tracks, startIndex: index);
      _logger.log('Tracks queued on ${player.name}');
      // Stay on album page - mini player will appear
    } catch (e) {
      _logger.log('Error playing track: $e');
      _showError('Failed to play track: $e');
    }
  }

  void _addAlbumToQueue() {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    // Slide mini player down out of the way
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
            Spacing.vGap16,
            Text(
              S.of(context)!.addAlbumToQueueOn,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Spacing.vGap16,
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
                          _logger.log('Adding album to queue on ${player.name}');
                          await maProvider.playTracks(
                            player.playerId,
                            _tracks,
                            startIndex: 0,
                            clearQueue: false,
                          );
                          _logger.log('Album added to queue on ${player.name}');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.albumAddedToQueue),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error adding album to queue: $e');
                          _showError('Failed to add album to queue: $e');
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
      // Show mini player again when sheet closes
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _addTrackToQueue(BuildContext context, int index) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

    // Slide mini player down out of the way
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
            Spacing.vGap16,
            Text(
              S.of(context)!.addToQueueOn,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Spacing.vGap16,
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
                          // Add tracks from this index onwards to queue
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
      // Slide mini player back up when sheet is dismissed
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _navigateToArtist() {
    // Navigate to the first artist if available
    if (_displayAlbum.artists != null && _displayAlbum.artists!.isNotEmpty) {
      final artist = _displayAlbum.artists!.first;
      final maProvider = context.read<MusicAssistantProvider>();
      final imageUrl = maProvider.getImageUrl(artist, size: 256);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ArtistDetailsScreen(
            artist: artist,
            initialImageUrl: imageUrl,
          ),
        ),
      );
    }
  }

  Future<void> _loadAlbumDescription() async {
    final artistName = widget.album.artists?.firstOrNull?.name ?? '';
    final albumName = widget.album.name;

    if (artistName.isEmpty || albumName.isEmpty) return;

    final description = await MetadataService.getAlbumDescription(
      artistName,
      albumName,
      widget.album.metadata,
    );

    if (mounted) {
      setState(() {
        _albumDescription = description;
      });
    }
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

  /// Show fullscreen album art overlay
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
      cacheManager: AuthenticatedCacheManager.instance,
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

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use select() instead of watch() to reduce rebuilds
    // Only rebuild when specific properties change, not on every provider update
    // Use _displayAlbum which has fresh data with images if available
    final providerImageUrl = context.select<MusicAssistantProvider, String?>(
      (provider) => provider.getImageUrl(_displayAlbum, size: 512),
    );
    // Use initialImageUrl as fallback for seamless hero animation
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

    // Determine if we should use adaptive theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use - prefer local state over provider
    // Local state (_darkColorScheme/_lightColorScheme) is set by _extractColors()
    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      // Use local state first (from _extractColors), fallback to provider
      adaptiveScheme = isDark
        ? (_darkColorScheme ?? adaptiveDarkScheme)
        : (_lightColorScheme ?? adaptiveLightScheme);
    }

    // Use adaptive scheme if available, otherwise use global theme
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
        backgroundColor: colorScheme.background,
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
            backgroundColor: colorScheme.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                clearAdaptiveColorsOnBack(context);
                Navigator.pop(context);
              },
              color: colorScheme.onBackground,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  GestureDetector(
                    onTap: () => _showFullscreenArt(imageUrl),
                    // Shadow container (outside Hero for correct clipping)
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
                        tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                        // FIXED: Match source structure - ClipRRect(12) → Container → CachedNetworkImage
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: coverSize,
                            height: coverSize,
                            color: colorScheme.surfaceVariant,
                            child: imageUrl != null
                                ? CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
      imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    // Match source memCacheWidth for smooth Hero
                                    memCacheWidth: 256,
                                    memCacheHeight: 256,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    placeholder: (_, __) => const SizedBox(),
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.album_rounded,
                                      size: coverSize * 0.43,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Icon(
                                    Icons.album_rounded,
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
                  Hero(
                    tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.album.nameWithYear,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Spacing.vGap8,
                  Hero(
                    tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _navigateToArtist(),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            _displayAlbum.artistsString,
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onBackground.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Spacing.vGap16,
                  // Album Description
                  if (_albumDescription != null && _albumDescription!.isNotEmpty) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _albumDescription!,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onBackground.withOpacity(0.8),
                          ),
                          maxLines: _isDescriptionExpanded ? null : 2,
                          overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Spacing.vGap8,
                  ],
                  Row(
                    children: [
                      // Main Play Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading || _tracks.isEmpty ? null : _playAlbum,
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

                      // "Play on..." Button (Square)
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

                      // "Add Album to Queue" Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _isLoading || _tracks.isEmpty ? null : _addAlbumToQueue,
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
                              borderRadius: BorderRadius.circular(Radii.xxl), // Circular
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

                      const SizedBox(width: 12),

                      // Library Button
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
                  S.of(context)!.noTracksFound,
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
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

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${track.position ?? index + 1}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
                            // Single tap to collapse when expanded
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

  void _showPlayAlbumFromHereMenu(BuildContext context, int startIndex) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        await maProvider.playTracks(
          player.playerId,
          _tracks,
          startIndex: startIndex,
        );
      },
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
