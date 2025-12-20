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
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  bool _isDescriptionExpanded = false;
  String? _artistDescription;
  String? _artistImageUrl;

  // View preferences
  String _sortOrder = 'alpha'; // 'alpha' or 'year'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.artist.favorite ?? false;
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
        }
      });
    });
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
    if (maProvider.api == null) return;

    try {
      final newState = !_isFavorite;

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
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        _logger.log('Adding artist to favorites: provider=$actualProvider, itemId=$actualItemId');
        await maProvider.api!.addToFavorites('artist', actualItemId, actualProvider);
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

        _logger.log('Removing artist from favorites: libraryItemId=$libraryItemId');
        await maProvider.api!.removeFromFavorites('artist', libraryItemId);
      }

      setState(() {
        _isFavorite = newState;
      });

      maProvider.invalidateHomeCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites,
            ),
            duration: const Duration(seconds: 1),
          ),
        );
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

  Future<void> _startArtistRadio() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.playArtistRadio(selectedPlayer.playerId, widget.artist);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.startingRadio(widget.artist.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error starting artist radio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToStartRadio(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPlayOnMenu(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start ${widget.artist.name} radio on...',
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
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: colorScheme.onSurface,
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _addArtistRadioToQueue() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      // For adding to queue with radio mode, we use radio_mode but with 'add' option
      await maProvider.api?.playArtistRadioToQueue(selectedPlayer.playerId, widget.artist);
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
        CachedNetworkImageProvider(imageUrl),
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

    // Use cached artist albums method
    final allAlbums = await provider.getArtistAlbumsWithCache(widget.artist.name);

    if (mounted) {
      // Separate library albums from provider-only albums
      final libraryAlbums = allAlbums.where((a) => a.inLibrary).toList();
      final providerOnlyAlbums = allAlbums.where((a) => !a.inLibrary).toList();

      setState(() {
        _albums = libraryAlbums;
        _providerAlbums = providerOnlyAlbums;
        _sortAlbums(); // Apply saved sort order
        _isLoading = false;
      });
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
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
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
                        width: 200,
                        height: 200,
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.person_rounded,
                                  size: 100,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: 100,
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
                  const SizedBox(height: 16),
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
                    const SizedBox(height: 8),
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
                            onPressed: _startArtistRadio,
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

                      // "Play on..." Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: () => _showPlayOnMenu(context),
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

                      // "Add to Queue" Button (Square)
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: FilledButton.tonal(
                          onPressed: _addArtistRadioToQueue,
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
                              borderRadius: BorderRadius.circular(25),
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
                  const SizedBox(height: 16),
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
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildAlbumSliver(_providerAlbums),
              const SliverToBoxAdapter(child: SizedBox(height: 140)), // Space for bottom nav + mini player
            ],
          ],
        ],
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
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
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
          const SizedBox(height: 8),
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
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
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
            ),
          ),
        );
      },
    );
  }
}
