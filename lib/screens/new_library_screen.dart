import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_avatar.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../services/settings_service.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';

/// Media type for the library
enum LibraryMediaType { music, books, podcasts }

class NewLibraryScreen extends StatefulWidget {
  const NewLibraryScreen({super.key});

  @override
  State<NewLibraryScreen> createState() => _NewLibraryScreenState();
}

class _NewLibraryScreenState extends State<NewLibraryScreen>
    with SingleTickerProviderStateMixin, RestorationMixin {
  late TabController _tabController;
  List<Playlist> _playlists = [];
  List<Track> _favoriteTracks = [];
  bool _isLoadingPlaylists = true;
  bool _isLoadingTracks = false;
  bool _showFavoritesOnly = false;

  // Media type selection (Music, Books, Podcasts)
  LibraryMediaType _selectedMediaType = LibraryMediaType.music;

  // View mode settings
  String _artistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _albumsViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _playlistsViewMode = 'list'; // 'grid2', 'grid3', 'list'

  // Restoration: Remember selected tab across app restarts
  final RestorableInt _selectedTabIndex = RestorableInt(0);

  int get _tabCount {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return _showFavoritesOnly ? 4 : 3;
      case LibraryMediaType.books:
        return 3; // Authors, All Books, Series
      case LibraryMediaType.podcasts:
        return 1; // Coming soon placeholder
    }
  }

  @override
  String? get restorationId => 'new_library_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_selectedTabIndex, 'selected_tab_index');
    // Apply restored tab index after TabController is created
    if (_tabController.index != _selectedTabIndex.value &&
        _selectedTabIndex.value < _tabController.length) {
      _tabController.index = _selectedTabIndex.value;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    // Listen to tab changes to persist selection
    _tabController.addListener(_onTabChanged);
    _loadPlaylists();
    _loadViewPreferences();
  }

  Future<void> _loadViewPreferences() async {
    final artistsMode = await SettingsService.getLibraryArtistsViewMode();
    final albumsMode = await SettingsService.getLibraryAlbumsViewMode();
    final playlistsMode = await SettingsService.getLibraryPlaylistsViewMode();
    if (mounted) {
      setState(() {
        _artistsViewMode = artistsMode;
        _albumsViewMode = albumsMode;
        _playlistsViewMode = playlistsMode;
      });
    }
  }

  void _cycleArtistsViewMode() {
    String newMode;
    switch (_artistsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _artistsViewMode = newMode);
    SettingsService.setLibraryArtistsViewMode(newMode);
  }

  void _cycleAlbumsViewMode() {
    String newMode;
    switch (_albumsViewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() => _albumsViewMode = newMode);
    SettingsService.setLibraryAlbumsViewMode(newMode);
  }

  void _cyclePlaylistsViewMode() {
    String newMode;
    switch (_playlistsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _playlistsViewMode = newMode);
    SettingsService.setLibraryPlaylistsViewMode(newMode);
  }

  IconData _getViewModeIcon(String mode) {
    switch (mode) {
      case 'list':
        return Icons.view_list;
      case 'grid3':
        return Icons.grid_view;
      default:
        return Icons.grid_on;
    }
  }

  String _getCurrentViewMode() {
    // Return the view mode for the currently selected tab
    final tabIndex = _tabController.index;
    if (_showFavoritesOnly) {
      // Artists, Albums, Tracks, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return 'list'; // Tracks always list
        case 3:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    } else {
      // Artists, Albums, Playlists
      switch (tabIndex) {
        case 0:
          return _artistsViewMode;
        case 1:
          return _albumsViewMode;
        case 2:
          return _playlistsViewMode;
        default:
          return 'list';
      }
    }
  }

  void _cycleCurrentViewMode() {
    final tabIndex = _tabController.index;
    if (_showFavoritesOnly) {
      switch (tabIndex) {
        case 0:
          _cycleArtistsViewMode();
          break;
        case 1:
          _cycleAlbumsViewMode();
          break;
        case 2:
          // Tracks - no view toggle
          break;
        case 3:
          _cyclePlaylistsViewMode();
          break;
      }
    } else {
      switch (tabIndex) {
        case 0:
          _cycleArtistsViewMode();
          break;
        case 1:
          _cycleAlbumsViewMode();
          break;
        case 2:
          _cyclePlaylistsViewMode();
          break;
      }
    }
  }

  void _recreateTabController() {
    final oldIndex = _tabController.index;
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Restore to previous index if valid, otherwise default to 0
    if (oldIndex < _tabCount) {
      _tabController.index = oldIndex;
    }
  }

  void _changeMediaType(LibraryMediaType type) {
    if (_selectedMediaType == type) return;
    setState(() {
      _selectedMediaType = type;
      _recreateTabController();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _selectedTabIndex.value = _tabController.index;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _selectedTabIndex.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists({bool? favoriteOnly}) async {
    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final playlists = await maProvider.api!.getPlaylists(
        limit: 100,
        favoriteOnly: favoriteOnly,
      );
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _isLoadingPlaylists = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteTracks() async {
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      final tracks = await maProvider.api!.getTracks(
        limit: 500,
        favoriteOnly: true,
      );
      if (mounted) {
        setState(() {
          _favoriteTracks = tracks;
          _isLoadingTracks = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
        });
      }
    }
  }

  void _toggleFavoritesMode(bool value) {
    setState(() {
      _showFavoritesOnly = value;
      _recreateTabController();
    });
    if (value) {
      _loadPlaylists(favoriteOnly: true);
      _loadFavoriteTracks();
    } else {
      _loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when connection state changes
    return Selector<MusicAssistantProvider, bool>(
      selector: (_, provider) => provider.isConnected,
      builder: (context, isConnected, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        if (!isConnected) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(
                'Library',
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.w300,
                ),
              ),
              centerTitle: true,
              actions: const [PlayerSelector()],
            ),
            body: DisconnectedState.withSettingsAction(
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 0,
            toolbarHeight: 56,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100), // Pills + Tabs
              child: Column(
                children: [
                  // Media type pills (centered)
                  _buildMediaTypePills(colorScheme),
                  const SizedBox(height: 8),
                  // Contextual tabs
                  Stack(
                    children: [
                      // Bottom border line extending full width
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 1,
                          color: colorScheme.outlineVariant.withOpacity(0.3),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TabBar(
                              controller: _tabController,
                              labelColor: colorScheme.primary,
                              unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
                              indicatorColor: colorScheme.primary,
                              indicatorWeight: 3,
                              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                              tabs: _buildTabs(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: _buildTabViews(context),
          ),
        );
      },
    );
  }

  // ============ MEDIA TYPE PILLS ============
  Widget _buildMediaTypePills(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPill(
          label: 'Music',
          isSelected: _selectedMediaType == LibraryMediaType.music,
          onTap: () => _changeMediaType(LibraryMediaType.music),
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 12),
        _buildPill(
          label: 'Books',
          isSelected: _selectedMediaType == LibraryMediaType.books,
          onTap: () => _changeMediaType(LibraryMediaType.books),
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 12),
        _buildPill(
          label: 'Podcasts',
          isSelected: _selectedMediaType == LibraryMediaType.podcasts,
          onTap: () => _changeMediaType(LibraryMediaType.podcasts),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.primary.withOpacity(0.4),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ============ CONTEXTUAL TABS ============
  List<Tab> _buildTabs() {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return [
          const Tab(text: 'Artists'),
          const Tab(text: 'Albums'),
          if (_showFavoritesOnly) const Tab(text: 'Tracks'),
          const Tab(text: 'Playlists'),
        ];
      case LibraryMediaType.books:
        return const [
          Tab(text: 'Authors'),
          Tab(text: 'All Books'),
          Tab(text: 'Series'),
        ];
      case LibraryMediaType.podcasts:
        return const [
          Tab(text: 'Shows'),
        ];
    }
  }

  List<Widget> _buildTabViews(BuildContext context) {
    switch (_selectedMediaType) {
      case LibraryMediaType.music:
        return [
          _buildArtistsTab(context),
          _buildAlbumsTab(context),
          if (_showFavoritesOnly) _buildTracksTab(context),
          _buildPlaylistsTab(context),
        ];
      case LibraryMediaType.books:
        return [
          _buildBooksAuthorsTab(context),
          _buildAllBooksTab(context),
          _buildSeriesTab(context),
        ];
      case LibraryMediaType.podcasts:
        return [
          _buildPodcastsComingSoonTab(context),
        ];
    }
  }

  // ============ BOOKS TABS (Placeholders) ============
  Widget _buildBooksAuthorsTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 64,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Authors',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse audiobooks by author',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Coming in Phase 6',
            style: TextStyle(
              color: colorScheme.primary.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllBooksTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_rounded,
            size: 64,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'All Books',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View all audiobooks in your library',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Coming in Phase 6',
            style: TextStyle(
              color: colorScheme.primary.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.collections_bookmark_rounded,
            size: 64,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Series',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse audiobook series',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Waiting for Music Assistant support',
            style: TextStyle(
              color: colorScheme.primary.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ============ PODCASTS TAB (Placeholder) ============
  Widget _buildPodcastsComingSoonTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.podcasts_rounded,
            size: 64,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Podcasts',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Podcast support coming soon',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ============ ARTISTS TAB ============
  Widget _buildArtistsTab(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when artists or loading state changes
    return Selector<MusicAssistantProvider, (List<Artist>, bool)>(
      selector: (_, provider) => (provider.artists, provider.isLoading),
      builder: (context, data, _) {
        final (allArtists, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final artists = _showFavoritesOnly
            ? allArtists.where((a) => a.favorite == true).toList()
            : allArtists;

        if (artists.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              icon: Icons.favorite_border,
              title: 'No favorite artists',
              subtitle: 'Tap the heart on an artist to add them to favorites',
            );
          }
          return EmptyState.artists(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: _artistsViewMode == 'list'
              ? ListView.builder(
                  key: PageStorageKey<String>('library_artists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                  cacheExtent: 500,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  itemCount: artists.length,
                  padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return _buildArtistTile(
                      context,
                      artist,
                      key: ValueKey(artist.uri ?? artist.itemId),
                    );
                  },
                )
              : GridView.builder(
                  key: PageStorageKey<String>('library_artists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_artistsViewMode'),
                  cacheExtent: 500,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _artistsViewMode == 'grid3' ? 3 : 2,
                    childAspectRatio: _artistsViewMode == 'grid3' ? 0.75 : 0.80,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: artists.length,
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return _buildArtistGridCard(context, artist);
                  },
                ),
        );
      },
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    Artist artist, {
    Key? key,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final suffix = '_library';
    // Get image URL for hero animation
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return RepaintBoundary(
      child: ListTile(
        key: key,
        leading: ArtistAvatar(
          artist: artist,
          radius: 24,
          imageSize: 128,
          heroTag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
        ),
      title: Hero(
        tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
        child: Material(
          color: Colors.transparent,
          child: Text(
            artist.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
        onTap: () {
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'library',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtistGridCard(BuildContext context, Artist artist) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: ArtistDetailsScreen(
              artist: artist,
              heroTagSuffix: 'library_grid',
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use LayoutBuilder to get available width for proper circle sizing
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use the smaller dimension to ensure a circle
                final size = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: ArtistAvatar(
                    artist: artist,
                    radius: size / 2,
                    imageSize: 256,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            artist.name,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============ ALBUMS TAB ============
  Widget _buildAlbumsTab(BuildContext context) {
    // Use Selector for targeted rebuilds - only rebuild when albums or loading state changes
    return Selector<MusicAssistantProvider, (List<Album>, bool)>(
      selector: (_, provider) => (provider.albums, provider.isLoading),
      builder: (context, data, _) {
        final (allAlbums, isLoading) = data;
        final colorScheme = Theme.of(context).colorScheme;

        if (isLoading) {
          return Center(child: CircularProgressIndicator(color: colorScheme.primary));
        }

        // Filter by favorites if enabled
        final albums = _showFavoritesOnly
            ? allAlbums.where((a) => a.favorite == true).toList()
            : allAlbums;

        if (albums.isEmpty) {
          if (_showFavoritesOnly) {
            return EmptyState.custom(
              icon: Icons.favorite_border,
              title: 'No favorite albums',
              subtitle: 'Tap the heart on an album to add it to favorites',
            );
          }
          return EmptyState.albums(
            onRefresh: () => context.read<MusicAssistantProvider>().loadLibrary(),
          );
        }

        return RefreshIndicator(
          color: colorScheme.primary,
          backgroundColor: colorScheme.surface,
          onRefresh: () async => context.read<MusicAssistantProvider>().loadLibrary(),
          child: _albumsViewMode == 'list'
              ? ListView.builder(
                  key: PageStorageKey<String>('library_albums_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                  cacheExtent: 500,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return _buildAlbumListTile(context, album);
                  },
                )
              : GridView.builder(
                  key: PageStorageKey<String>('library_albums_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_albumsViewMode'),
                  cacheExtent: 500,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _albumsViewMode == 'grid3' ? 3 : 2,
                    childAspectRatio: _albumsViewMode == 'grid3' ? 0.70 : 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return AlbumCard(
                      key: ValueKey(album.uri ?? album.itemId),
                      album: album,
                      heroTagSuffix: 'library_grid',
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildAlbumListTile(BuildContext context, Album album) {
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
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox(),
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
            child: AlbumDetailsScreen(album: album),
          ),
        );
      },
    );
  }

  // ============ PLAYLISTS TAB ============
  Widget _buildPlaylistsTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingPlaylists) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_playlists.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          icon: Icons.favorite_border,
          title: 'No favorite playlists',
          subtitle: 'Tap the heart on a playlist to add it to favorites',
        );
      }
      return EmptyState.playlists(onRefresh: () => _loadPlaylists());
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadPlaylists(favoriteOnly: _showFavoritesOnly ? true : null),
      child: _playlistsViewMode == 'list'
          ? ListView.builder(
              key: PageStorageKey<String>('library_playlists_list_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
              cacheExtent: 500,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              itemCount: _playlists.length,
              padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return _buildPlaylistTile(context, playlist);
              },
            )
          : GridView.builder(
              key: PageStorageKey<String>('library_playlists_grid_${_showFavoritesOnly ? 'fav' : 'all'}_$_playlistsViewMode'),
              cacheExtent: 500,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: BottomSpacing.navBarOnly),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _playlistsViewMode == 'grid3' ? 3 : 2,
                childAspectRatio: _playlistsViewMode == 'grid3' ? 0.75 : 0.80,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return _buildPlaylistGridCard(context, playlist);
              },
            ),
    );
  }

  Widget _buildPlaylistTile(BuildContext context, Playlist playlist) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(playlist.itemId),
        leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          image: imageUrl != null
              ? DecorationImage(image: CachedNetworkImageProvider(imageUrl), fit: BoxFit.cover)
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.playlist_play_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        playlist.name,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        playlist.trackCount != null
            ? '${playlist.trackCount} tracks'
            : playlist.owner ?? 'Playlist',
        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
        trailing: playlist.favorite == true
            ? const Icon(Icons.favorite, color: Colors.red, size: 20)
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistDetailsScreen(
                playlist: playlist,
                provider: playlist.provider,
                itemId: playlist.itemId,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistGridCard(BuildContext context, Playlist playlist) {
    final provider = context.read<MusicAssistantProvider>();
    final imageUrl = provider.api?.getImageUrl(playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistDetailsScreen(
              playlist: playlist,
              provider: playlist.provider,
              itemId: playlist.itemId,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: colorScheme.surfaceVariant,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, __) => const SizedBox(),
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(
                            Icons.playlist_play_rounded,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.playlist_play_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            playlist.trackCount != null
                ? '${playlist.trackCount} tracks'
                : playlist.owner ?? 'Playlist',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============ TRACKS TAB (favorites only) ============
  Widget _buildTracksTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingTracks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_favoriteTracks.isEmpty) {
      return EmptyState.custom(
        icon: Icons.favorite_border,
        title: 'No favorite tracks',
        subtitle: 'Long-press a track and tap the heart to add it to favorites',
      );
    }

    // Sort tracks by artist name, then track name
    final sortedTracks = List<Track>.from(_favoriteTracks)
      ..sort((a, b) {
        final artistCompare = a.artistsString.compareTo(b.artistsString);
        if (artistCompare != 0) return artistCompare;
        return a.name.compareTo(b.name);
      });

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: _loadFavoriteTracks,
      child: ListView.builder(
        key: const PageStorageKey<String>('library_tracks_list'),
        cacheExtent: 500,
        addAutomaticKeepAlives: false, // Tiles don't need individual keep-alive
        addRepaintBoundaries: false, // We add RepaintBoundary manually to tiles
        padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: BottomSpacing.navBarOnly),
        itemCount: sortedTracks.length,
        itemBuilder: (context, index) {
          final track = sortedTracks[index];
          return _buildTrackTile(context, track);
        },
      ),
    );
  }

  Widget _buildTrackTile(BuildContext context, Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get image URL from track itself
    final imageUrl = maProvider.api?.getImageUrl(track, size: 128);

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(track.uri ?? track.itemId),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
          image: imageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: imageUrl == null
            ? Icon(Icons.music_note, color: colorScheme.onSurfaceVariant, size: 24)
            : null,
      ),
      title: Text(
        track.artistsString,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.name,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.favorite,
        color: Colors.red,
        size: 20,
      ),
      onTap: () async {
        final player = maProvider.selectedPlayer;
        if (player == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No player selected')),
          );
          return;
        }

        try {
          // Start radio from this track
          await maProvider.api?.playRadio(player.playerId, track);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start radio: $e')),
            );
          }
        }
      },
      ),
    );
  }
}
