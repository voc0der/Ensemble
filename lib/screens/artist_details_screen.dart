import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../services/metadata_service.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import 'package:ensemble/services/image_cache_service.dart';

class ArtistDetailsScreen extends StatefulWidget {
  final Artist artist;
  final String? heroTagSuffix;
  final String? initialImageUrl;

  const ArtistDetailsScreen({
    super.key,
    required this.artist,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<ArtistDetailsScreen> createState() => _ArtistDetailsScreenState();
}

class _ArtistDetailsScreenState extends State<ArtistDetailsScreen> {
  final _logger = DebugLogger();
  List<Album> _albums = [];
  List<Album> _providerAlbums = [];
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _isInLibrary = false;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _artistDescription;
  String? _artistImageUrl;
  MusicAssistantProvider? _maProvider;

  // View preferences
  String _sortOrder = 'alpha'; // 'alpha' or 'year'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.artist.favorite ?? false;
    _isInLibrary = _checkIfInLibrary(widget.artist);
    // Use initial image URL immediately for smooth hero animation
    _artistImageUrl = widget.initialImageUrl;
    _loadViewPreferences();
    _loadArtistAlbums();
    _loadArtistDescription();
    _refreshFavoriteStatus();

    // Defer higher-res image loading and color extraction until after transition
    // But hero animation now works because we have initialImageUrl
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _loadArtistImage();
          // Note: _extractColors is called by _loadArtistImage after image loads

          // CRITICAL FIX: Delay adding provider listener until AFTER Hero animation
          // Adding it immediately causes rebuilds during animation (jank)
          _maProvider = context.read<MusicAssistantProvider>();
          _maProvider?.addListener(_onProviderChanged);
        }
      });
    });
  }

  void _onProviderChanged() {
    if (!mounted) return;
    // Re-check library status when provider data changes
    final newIsInLibrary = _checkIfInLibraryFromProvider();
    if (newIsInLibrary != _isInLibrary) {
      setState(() {
        _isInLibrary = newIsInLibrary;
      });
    }
  }

  /// Check if artist is in library using provider's artists list
  bool _checkIfInLibraryFromProvider() {
    if (_maProvider == null) return _checkIfInLibrary(widget.artist);

    final artistName = widget.artist.name.toLowerCase();
    final artistUri = widget.artist.uri;

    // Check if this artist exists in the provider's library
    return _maProvider!.artists.any((a) {
      // Match by URI if available
      if (artistUri != null && a.uri == artistUri) return true;
      // Match by name as fallback
      if (a.name.toLowerCase() == artistName) return true;
      // Check provider mappings for matching URIs
      if (widget.artist.providerMappings != null) {
        for (final mapping in widget.artist.providerMappings!) {
          if (a.providerMappings?.any((m) =>
            m.providerInstance == mapping.providerInstance &&
            m.itemId == mapping.itemId) == true) {
            return true;
          }
        }
      }
      return false;
    });
  }

  @override
  void dispose() {
    _maProvider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  Future<void> _loadViewPreferences() async {
    final sortOrder = await SettingsService.getArtistAlbumsSortOrder();
    final viewMode = await SettingsService.getArtistAlbumsViewMode();
    if (mounted) {
      setState(() {
        _sortOrder = sortOrder;
        _viewMode = viewMode;
      });
    }
  }

  void _toggleSortOrder() {
    final newOrder = _sortOrder == 'alpha' ? 'year' : 'alpha';
    setState(() {
      _sortOrder = newOrder;
      _sortAlbums();
    });
    SettingsService.setArtistAlbumsSortOrder(newOrder);
  }

  void _cycleViewMode() {
    String newMode;
    switch (_viewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() {
      _viewMode = newMode;
    });
    SettingsService.setArtistAlbumsViewMode(newMode);
  }

  void _sortAlbums() {
    if (_sortOrder == 'year') {
      // Sort by year ascending (oldest first), null years at end
      _albums.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
      _providerAlbums.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      // Sort alphabetically
      _albums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _providerAlbums.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  Future<void> _refreshFavoriteStatus() async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    final artistUri = widget.artist.uri;
    if (artistUri == null || artistUri.isEmpty) {
      _logger.log('Cannot refresh favorite status: artist has no URI');
      return;
    }

    try {
      final freshArtist = await maProvider.api!.getArtistByUri(artistUri);
      if (freshArtist != null && mounted) {
        setState(() {
          _isFavorite = freshArtist.favorite ?? false;
        });
      }
    } catch (e) {
      _logger.log('Error refreshing artist favorite status: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final newState = !_isFavorite;
      bool success;

      if (newState) {
        String actualProvider = widget.artist.provider;
        String actualItemId = widget.artist.itemId;

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          final mapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.artist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.artist.providerMappings!.first,
            ),
          );
          // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding artist to favorites: provider=$actualProvider, itemId=$actualItemId');
        success = await maProvider.addToFavorites(
          mediaType: 'artist',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;

        if (widget.artist.provider == 'library') {
          libraryItemId = int.tryParse(widget.artist.itemId);
        } else if (widget.artist.providerMappings != null) {
          final libraryMapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.artist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) {
          _logger.log('Error: Could not determine library_item_id for removal');
          throw Exception('Could not determine library ID for this artist');
        }

        success = await maProvider.removeFromFavorites(
          mediaType: 'artist',
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
      _logger.log('Error toggling artist favorite: $e');
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

  /// Check if artist is in library
  bool _checkIfInLibrary(Artist artist) {
    if (artist.provider == 'library') return true;
    return artist.providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
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

        if (widget.artist.providerMappings != null && widget.artist.providerMappings!.isNotEmpty) {
          // For adding to library, we MUST use a non-library provider
          final nonLibraryMapping = widget.artist.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        // Fallback to item's own provider if no non-library mapping found
        if (actualProvider == null || actualItemId == null) {
          if (widget.artist.provider != 'library') {
            actualProvider = widget.artist.provider;
            actualItemId = widget.artist.itemId;
          } else {
            // Item is library-only, can't add
            _logger.log('Cannot add to library: artist is library-only');
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

        _logger.log('Adding artist to library: provider=$actualProvider, itemId=$actualItemId');
        // Fire and forget - API call happens in background
        maProvider.addToLibrary(
          mediaType: 'artist',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to add artist to library: $e');
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
        if (widget.artist.provider == 'library') {
          libraryItemId = int.tryParse(widget.artist.itemId);
        } else if (widget.artist.providerMappings != null) {
          final libraryMapping = widget.artist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.artist.providerMappings!.first,
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
          mediaType: 'artist',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          _logger.log('❌ Failed to remove artist from library: $e');
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
      _logger.log('Error toggling artist library: $e');
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

  void _showRadioMenu(BuildContext context) {
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
              S.of(context)!.startRadioOn(widget.artist.name),
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
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await maProvider.playArtistRadio(player.playerId, widget.artist);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.startingRadioOnPlayer(widget.artist.name, player.name)),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error starting artist radio on player: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.failedToStartRadio(e.toString())),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
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

  void _showAddToQueueMenu(BuildContext context) {
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
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        final api = maProvider.api;
                        if (api == null) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(S.of(context)!.notConnected)),
                            );
                          }
                          return;
                        }
                        try {
                          await api.playArtistRadioToQueue(player.playerId, widget.artist);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.addedRadioToQueue(widget.artist.name)),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          _logger.log('Error adding artist radio to queue: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(S.of(context)!.failedToAddToQueue(e.toString())),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
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

  Future<void> _loadArtistImage() async {
    final maProvider = context.read<MusicAssistantProvider>();

    // Get image URL with fallback to Deezer/Fanart.tv
    final imageUrl = await maProvider.getArtistImageUrlWithFallback(widget.artist, size: 512);

    if (mounted && imageUrl != null) {
      setState(() {
        _artistImageUrl = imageUrl;
      });
      // Extract colors after we have the image
      _extractColors(imageUrl);
    }
  }

  Future<void> _extractColors(String imageUrl) async {
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
      _logger.log('Failed to extract colors for artist: $e');
    }
  }

  Future<void> _loadArtistDescription() async {
    final artistName = widget.artist.name;

    if (artistName.isEmpty) return;

    final description = await MetadataService.getArtistDescription(
      artistName,
      widget.artist.metadata,
    );

    if (mounted) {
      setState(() {
        _artistDescription = description;
      });
    }
  }

  Future<void> _loadArtistAlbums() async {
    final provider = context.read<MusicAssistantProvider>();

    // 1. Show cached data immediately (if available)
    final cachedAlbums = provider.getCachedArtistAlbums(widget.artist.name);
    if (cachedAlbums != null && cachedAlbums.isNotEmpty) {
      final libraryAlbums = cachedAlbums.where((a) => a.inLibrary).toList();
      final providerOnlyAlbums = cachedAlbums.where((a) => !a.inLibrary).toList();

      if (mounted) {
        setState(() {
          _albums = libraryAlbums;
          _providerAlbums = providerOnlyAlbums;
          _sortAlbums();
          _isLoading = false;
        });
      }
    }

    // 2. Fetch fresh data in background (silent refresh)
    try {
      final allAlbums = await provider.getArtistAlbumsWithCache(
        widget.artist.name,
        forceRefresh: cachedAlbums != null,
      );

      if (mounted && allAlbums.isNotEmpty) {
        // Check if data actually changed
        final albumsChanged = _albums.length != allAlbums.where((a) => a.inLibrary).length;

        if (albumsChanged || _albums.isEmpty) {
          final libraryAlbums = allAlbums.where((a) => a.inLibrary).toList();
          final providerOnlyAlbums = allAlbums.where((a) => !a.inLibrary).toList();

          setState(() {
            _albums = libraryAlbums;
            _providerAlbums = providerOnlyAlbums;
            _sortAlbums();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Use select() instead of watch() to reduce rebuilds
    // Only rebuild when specific properties change, not on every provider update
    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    // Use the loaded image URL (with fallback) instead of directly from MA
    final imageUrl = _artistImageUrl;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get the color scheme to use - prefer local state over provider
    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      // Use local state first (from _extractColors), fallback to provider
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
        backgroundColor: colorScheme.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive cover size: 70% of screen width, clamped between 160-280 (smaller for circular artist image)
            final coverSize = (constraints.maxWidth * 0.7).clamp(160.0, 280.0);
            final expandedHeight = coverSize + 100;

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
                  Hero(
                    tag: HeroTags.artistImage + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
                    child: ClipOval(
                      child: Container(
                        width: coverSize,
                        height: coverSize,
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
      imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                // Match source memCacheWidth for smooth Hero animation
                                memCacheWidth: 256,
                                memCacheHeight: 256,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) => const SizedBox(),
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.person_rounded,
                                  size: coverSize * 0.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: coverSize * 0.5,
                                color: colorScheme.onSurfaceVariant,
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: HeroTags.artistName + (widget.artist.uri ?? widget.artist.itemId) + _heroTagSuffix,
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        widget.artist.name,
                        style: textTheme.headlineMedium?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Spacing.vGap16,
                  if (_artistDescription != null && _artistDescription!.isNotEmpty) ...[
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
                          _artistDescription!,
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
                  // Action Buttons Row
                  Row(
                    children: [
                      // Main Radio Button
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => _showRadioMenu(context),
                            icon: const Icon(Icons.radio),
                            label: Text(S.of(context)!.radio),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // "Add to Queue" Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: () => _showAddToQueueMenu(context),
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
                  Spacing.vGap16,
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
          else if (_albums.isEmpty && _providerAlbums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  S.of(context)!.noAlbumsFound,
                  style: TextStyle(
                    color: colorScheme.onBackground.withOpacity(0.54),
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else ...[
            // Library Albums Section with inline controls
            if (_albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 8.0, 12.0, 8.0),
                  child: Row(
                    children: [
                      Text(
                        S.of(context)!.inLibrary,
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      // Sort toggle
                      IconButton(
                        icon: Icon(
                          _sortOrder == 'alpha' ? Icons.sort_by_alpha : Icons.calendar_today,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        tooltip: _sortOrder == 'alpha' ? S.of(context)!.sortByYear : S.of(context)!.sortAlphabetically,
                        onPressed: _toggleSortOrder,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                      // View mode toggle
                      IconButton(
                        icon: Icon(
                          _viewMode == 'list'
                              ? Icons.view_list
                              : _viewMode == 'grid3'
                                  ? Icons.grid_view
                                  : Icons.grid_on,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        tooltip: _viewMode == 'grid2'
                            ? S.of(context)!.threeColumnGrid
                            : _viewMode == 'grid3'
                                ? S.of(context)!.listView
                                : S.of(context)!.twoColumnGrid,
                        onPressed: _cycleViewMode,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                    ],
                  ),
                ),
              ),
              _buildAlbumSliver(_albums),
            ],

            // Provider Albums Section
            if (_providerAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24.0, _albums.isEmpty ? 8.0 : 24.0, 12.0, 8.0),
                  child: Row(
                    children: [
                      Text(
                        S.of(context)!.fromProviders,
                        style: textTheme.titleLarge?.copyWith(
                          color: colorScheme.onBackground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Only show controls here if no library albums
                      if (_albums.isEmpty) ...[
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _sortOrder == 'alpha' ? Icons.sort_by_alpha : Icons.calendar_today,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          tooltip: _sortOrder == 'alpha' ? S.of(context)!.sortByYear : S.of(context)!.sortAlphabetically,
                          onPressed: _toggleSortOrder,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        ),
                        IconButton(
                          icon: Icon(
                            _viewMode == 'list'
                                ? Icons.view_list
                                : _viewMode == 'grid3'
                                    ? Icons.grid_view
                                    : Icons.grid_on,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          tooltip: _viewMode == 'grid2'
                              ? S.of(context)!.threeColumnGrid
                              : _viewMode == 'grid3'
                                  ? S.of(context)!.listView
                                  : S.of(context)!.twoColumnGrid,
                          onPressed: _cycleViewMode,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildAlbumSliver(_providerAlbums),
              SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)), // Space for bottom nav + mini player
            ],
          ],
        ],
        );
          },
        ),
      ),
    );
  }

  Widget _buildAlbumCard(Album album) {
    // Use read instead of passing provider to avoid rebuild dependencies
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const String heroSuffix = 'artist_albums';

    return InkWell(
      onTap: () {
        // Update adaptive colors immediately on tap
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AlbumDetailsScreen(
              album: album,
              heroTagSuffix: heroSuffix,
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,  // Square album art
            child: Hero(
              tag: HeroTags.albumCover + (album.uri ?? album.itemId) + '_$heroSuffix',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: colorScheme.surfaceVariant,
                  child: imageUrl != null
                      ? CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
      imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          errorWidget: (_, __, ___) => Center(
                            child: Icon(
                              Icons.album_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.album_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Spacing.vGap8,
          Hero(
            tag: HeroTags.albumTitle + (album.uri ?? album.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.nameWithYear,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Hero(
            tag: HeroTags.artistName + (album.uri ?? album.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                album.artistsString,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumSliver(List<Album> albums) {
    if (_viewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAlbumListTile(albums[index]),
            childCount: albums.length,
          ),
        ),
      );
    }

    final crossAxisCount = _viewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _viewMode == 'grid3' ? 0.70 : 0.78;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAlbumCard(albums[index]),
          childCount: albums.length,
        ),
      ),
    );
  }

  Widget _buildAlbumListTile(Album album) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          color: colorScheme.surfaceVariant,
          child: imageUrl != null
              ? CachedNetworkImage(
      cacheManager: AuthenticatedCacheManager.instance,
      imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, __, ___) => Icon(
                    Icons.album_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : Icon(
                  Icons.album_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
      title: Text(
        album.nameWithYear,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        album.artistsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        updateAdaptiveColorsFromImage(context, imageUrl);
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AlbumDetailsScreen(
              album: album,
              heroTagSuffix: 'artist_albums',
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
    );
  }
}
