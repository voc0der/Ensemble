import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
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
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'settings_screen.dart';
import 'audiobook_author_screen.dart';
import 'audiobook_detail_screen.dart';

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
  List<Audiobook> _audiobooks = [];
  bool _isLoadingPlaylists = true;
  bool _isLoadingTracks = false;
  bool _isLoadingAudiobooks = false;
  bool _showFavoritesOnly = false;

  // Media type selection (Music, Books, Podcasts)
  LibraryMediaType _selectedMediaType = LibraryMediaType.music;

  // View mode settings
  String _artistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _albumsViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _playlistsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _audiobooksViewMode = 'grid2'; // 'grid2', 'grid3', 'list'
  String _authorsViewMode = 'list'; // 'grid2', 'grid3', 'list'
  String _audiobooksSortOrder = 'alpha'; // 'alpha', 'year'

  // Author image cache
  final Map<String, String?> _authorImages = {};

  // Series state
  List<AudiobookSeries> _series = [];
  bool _isLoadingSeries = false;
  bool _seriesLoaded = false;

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
    final authorsMode = await SettingsService.getLibraryAuthorsViewMode();
    final audiobooksMode = await SettingsService.getLibraryAudiobooksViewMode();
    final audiobooksSortOrder = await SettingsService.getLibraryAudiobooksSortOrder();
    if (mounted) {
      setState(() {
        _artistsViewMode = artistsMode;
        _albumsViewMode = albumsMode;
        _playlistsViewMode = playlistsMode;
        _authorsViewMode = authorsMode;
        _audiobooksViewMode = audiobooksMode;
        _audiobooksSortOrder = audiobooksSortOrder;
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

  void _cycleAuthorsViewMode() {
    String newMode;
    switch (_authorsViewMode) {
      case 'list':
        newMode = 'grid2';
        break;
      case 'grid2':
        newMode = 'grid3';
        break;
      default:
        newMode = 'list';
    }
    setState(() => _authorsViewMode = newMode);
    SettingsService.setLibraryAuthorsViewMode(newMode);
  }

  void _cycleAudiobooksViewMode() {
    String newMode;
    switch (_audiobooksViewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() => _audiobooksViewMode = newMode);
    SettingsService.setLibraryAudiobooksViewMode(newMode);
  }

  void _toggleAudiobooksSortOrder() {
    final newOrder = _audiobooksSortOrder == 'alpha' ? 'year' : 'alpha';
    setState(() => _audiobooksSortOrder = newOrder);
    SettingsService.setLibraryAudiobooksSortOrder(newOrder);
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

    // Handle books media type
    if (_selectedMediaType == LibraryMediaType.books) {
      switch (tabIndex) {
        case 0:
          return _authorsViewMode;
        case 1:
          return _audiobooksViewMode;
        case 2:
          return 'grid2'; // Series - default grid view
        default:
          return 'list';
      }
    }

    // Handle music media type
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

    // Handle books media type
    if (_selectedMediaType == LibraryMediaType.books) {
      switch (tabIndex) {
        case 0:
          _cycleAuthorsViewMode();
          break;
        case 1:
          _cycleAudiobooksViewMode();
          break;
        case 2:
          // Series - could add view toggle later
          break;
      }
      return;
    }

    // Handle music media type
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
    _logger.log('📚 _changeMediaType called: $type (current: $_selectedMediaType)');
    if (_selectedMediaType == type) {
      _logger.log('📚 Same type, skipping');
      return;
    }
    setState(() {
      _selectedMediaType = type;
      _recreateTabController();
    });
    // Load audiobooks when switching to books tab
    if (type == LibraryMediaType.books) {
      _logger.log('📚 Switched to Books, _audiobooks.isEmpty=${_audiobooks.isEmpty}');
      if (_audiobooks.isEmpty) {
        _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null);
      }
      // Load series from Music Assistant
      if (!_seriesLoaded) {
        _loadSeries();
      }
    }
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

  final _logger = DebugLogger();

  Future<void> _loadAudiobooks({bool? favoriteOnly}) async {
    _logger.log('📚 _loadAudiobooks called, favoriteOnly=$favoriteOnly');
    if (_isLoadingAudiobooks) {
      _logger.log('📚 Already loading, skipping');
      return;
    }

    setState(() {
      _isLoadingAudiobooks = true;
    });

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api != null) {
      _logger.log('📚 Calling API getAudiobooks...');
      final audiobooks = await maProvider.api!.getAudiobooks(
        limit: 10000,  // Large limit to get all audiobooks
        favoriteOnly: favoriteOnly,
      );
      _logger.log('📚 API returned ${audiobooks.length} audiobooks');
      if (audiobooks.isNotEmpty) {
        _logger.log('📚 First audiobook: ${audiobooks.first.name} by ${audiobooks.first.authorsString}');
      }
      if (mounted) {
        setState(() {
          _audiobooks = audiobooks;
          _isLoadingAudiobooks = false;
        });
        _logger.log('📚 State updated, _audiobooks.length = ${_audiobooks.length}');
        // Fetch author images in background
        _fetchAuthorImages(audiobooks);
      }
    } else {
      _logger.log('📚 API is null!');
      if (mounted) {
        setState(() {
          _isLoadingAudiobooks = false;
        });
      }
    }
  }

  Future<void> _fetchAuthorImages(List<Audiobook> audiobooks) async {
    // Get unique authors
    final authors = <String>{};
    for (final book in audiobooks) {
      authors.add(book.authorsString);
    }

    // Fetch images for authors not already cached
    for (final authorName in authors) {
      if (!_authorImages.containsKey(authorName)) {
        // Mark as loading to avoid duplicate requests
        _authorImages[authorName] = null;
        // Fetch in background
        MetadataService.getAuthorImageUrl(authorName).then((imageUrl) {
          if (mounted && imageUrl != null) {
            setState(() {
              _authorImages[authorName] = imageUrl;
            });
          }
        });
      }
    }
  }

  /// Load audiobook series from Music Assistant
  Future<void> _loadSeries() async {
    if (_isLoadingSeries) return;

    setState(() {
      _isLoadingSeries = true;
    });

    try {
      final maProvider = context.read<MusicAssistantProvider>();
      if (maProvider.api != null) {
        final series = await maProvider.api!.getAudiobookSeries();
        _logger.log('📚 Loaded ${series.length} series');

        if (mounted) {
          setState(() {
            _series = series;
            _isLoadingSeries = false;
            _seriesLoaded = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingSeries = false;
          });
        }
      }
    } catch (e) {
      _logger.log('📚 Error loading series: $e');
      if (mounted) {
        setState(() {
          _isLoadingSeries = false;
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
            // Top left: Media type segmented selector
            title: _buildMediaTypeSelector(colorScheme),
            leadingWidth: 16,
            leading: const SizedBox(),
            centerTitle: false,
            // Top right: Device selector
            actions: const [PlayerSelector()],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Stack(
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
                      // Tabs centered
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
                      // Favorites + Layout buttons on the right
                      IconButton(
                        icon: Icon(
                          _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                          color: _showFavoritesOnly ? Colors.red : colorScheme.onSurface.withOpacity(0.7),
                          size: 20,
                        ),
                        onPressed: () => _toggleFavoritesMode(!_showFavoritesOnly),
                        tooltip: _showFavoritesOnly ? 'Show all' : 'Show favorites only',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: Icon(
                          _getViewModeIcon(_getCurrentViewMode()),
                          color: colorScheme.onSurface.withOpacity(0.7),
                          size: 20,
                        ),
                        onPressed: _cycleCurrentViewMode,
                        tooltip: 'Change view',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 8),
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

  // ============ MEDIA TYPE SELECTOR ============
  Widget _buildMediaTypeSelector(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMediaTypeSegment(
            type: LibraryMediaType.music,
            icon: MdiIcons.musicNote,
            colorScheme: colorScheme,
          ),
          _buildMediaTypeSegment(
            type: LibraryMediaType.books,
            icon: MdiIcons.bookOutline,
            colorScheme: colorScheme,
          ),
          _buildMediaTypeSegment(
            type: LibraryMediaType.podcasts,
            icon: MdiIcons.podcast,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTypeSegment({
    required LibraryMediaType type,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _selectedMediaType == type;
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceVariant.withOpacity(0.5),
      child: InkWell(
        onTap: () => _changeMediaType(type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Icon(
            icon,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant.withOpacity(0.7),
            size: 20,
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

  // ============ BOOKS TABS ============
  Widget _buildBooksAuthorsTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    final audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : _audiobooks;

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          icon: Icons.favorite_border,
          title: 'No favorite audiobooks',
          subtitle: 'Tap the heart on an audiobook to add it to favorites',
        );
      }
      return EmptyState.custom(
        icon: MdiIcons.bookOutline,
        title: 'No audiobooks',
        subtitle: 'Add audiobooks to your library to see them here',
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // Group audiobooks by author
    final authorMap = <String, List<Audiobook>>{};
    for (final book in audiobooks) {
      final authorName = book.authorsString;
      authorMap.putIfAbsent(authorName, () => []).add(book);
    }

    // Sort authors alphabetically
    final sortedAuthors = authorMap.keys.toList()..sort();

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: CustomScrollView(
        key: const PageStorageKey<String>('books_authors_list'),
        slivers: [
          // Header with view mode toggle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Text(
                    '${sortedAuthors.length} ${sortedAuthors.length == 1 ? 'Author' : 'Authors'}',
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _getViewModeIcon(_authorsViewMode),
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    onPressed: _cycleAuthorsViewMode,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
          // Authors list/grid
          _buildAuthorsSliver(sortedAuthors, authorMap),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  Widget _buildAuthorsSliver(List<String> authors, Map<String, List<Audiobook>> authorMap) {
    if (_authorsViewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAuthorListTile(authors[index], authorMap[authors[index]]!),
            childCount: authors.length,
          ),
        ),
      );
    }

    final crossAxisCount = _authorsViewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _authorsViewMode == 'grid3' ? 0.85 : 0.90;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAuthorCard(authors[index], authorMap[authors[index]]!),
          childCount: authors.length,
        ),
      ),
    );
  }

  Widget _buildAuthorListTile(String authorName, List<Audiobook> books) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
        child: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          radius: 24,
          child: authorImageUrl != null
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: authorImageUrl,
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    placeholder: (_, __) => Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    errorWidget: (_, __, ___) => Text(
                      authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                )
              : Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
        ),
      ),
      title: Text(
        authorName,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${books.length} ${books.length == 1 ? 'audiobook' : 'audiobooks'}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix'),
    );
  }

  Widget _buildAuthorCard(String authorName, List<Audiobook> books) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final authorImageUrl = _authorImages[authorName];
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return InkWell(
      onTap: () => _navigateToAuthor(authorName, books, heroTagSuffix: 'library$heroSuffix'),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Hero(
              tag: HeroTags.authorImage + authorName + '_library$heroSuffix',
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: authorImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: authorImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => Center(
                            child: Text(
                              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: _authorsViewMode == 'grid3' ? 32 : 40,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: _authorsViewMode == 'grid3' ? 32 : 40,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: _authorsViewMode == 'grid3' ? 32 : 40,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            authorName,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            '${books.length} ${books.length == 1 ? 'book' : 'books'}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _navigateToAuthor(String authorName, List<Audiobook> books, {String? heroTagSuffix}) {
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookAuthorScreen(
          authorName: authorName,
          audiobooks: books,
          heroTagSuffix: heroTagSuffix,
        ),
      ),
    );
  }

  Widget _buildAudiobookListTile(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Hero(
        tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 56,
            height: 56,
            color: colorScheme.surfaceContainerHighest,
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox(),
                    errorWidget: (_, __, ___) => Icon(
                      MdiIcons.bookOutline,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    MdiIcons.bookOutline,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
      title: Hero(
        tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
        child: Material(
          color: Colors.transparent,
          child: Text(
            book.name,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      subtitle: Text(
        book.authorsString,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: book.progress > 0
          ? SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: book.progress,
                strokeWidth: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            )
          : null,
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix'),
    );
  }

  void _navigateToAudiobook(Audiobook book, {String? heroTagSuffix}) {
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookDetailScreen(
          audiobook: book,
          heroTagSuffix: heroTagSuffix,
        ),
      ),
    );
  }

  Widget _buildAllBooksTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();

    if (_isLoadingAudiobooks) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }

    // Filter by favorites if enabled
    var audiobooks = _showFavoritesOnly
        ? _audiobooks.where((a) => a.favorite == true).toList()
        : List<Audiobook>.from(_audiobooks);

    if (audiobooks.isEmpty) {
      if (_showFavoritesOnly) {
        return EmptyState.custom(
          icon: Icons.favorite_border,
          title: 'No favorite audiobooks',
          subtitle: 'Tap the heart on an audiobook to add it to favorites',
        );
      }
      return EmptyState.custom(
        icon: MdiIcons.bookOutline,
        title: 'No audiobooks',
        subtitle: 'Add audiobooks to your library to see them here',
        onRefresh: () => _loadAudiobooks(),
      );
    }

    // Sort audiobooks
    if (_audiobooksSortOrder == 'year') {
      audiobooks.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      audiobooks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _loadAudiobooks(favoriteOnly: _showFavoritesOnly ? true : null),
      child: CustomScrollView(
        key: PageStorageKey<String>('all_books_${_showFavoritesOnly ? 'fav' : 'all'}_$_audiobooksViewMode'),
        slivers: [
          // Header with controls
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Text(
                    '${audiobooks.length} ${audiobooks.length == 1 ? 'Audiobook' : 'Audiobooks'}',
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const Spacer(),
                  // Sort toggle
                  IconButton(
                    icon: Icon(
                      _audiobooksSortOrder == 'alpha' ? Icons.sort_by_alpha : Icons.calendar_today,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    tooltip: _audiobooksSortOrder == 'alpha' ? 'Sort by year' : 'Sort alphabetically',
                    onPressed: _toggleAudiobooksSortOrder,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  // View mode toggle
                  IconButton(
                    icon: Icon(
                      _getViewModeIcon(_audiobooksViewMode),
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    onPressed: _cycleAudiobooksViewMode,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),
          // Books list/grid
          _buildAudiobooksSliver(audiobooks, maProvider),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

  Widget _buildAudiobooksSliver(List<Audiobook> audiobooks, MusicAssistantProvider maProvider) {
    if (_audiobooksViewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAudiobookListTile(context, audiobooks[index], maProvider),
            childCount: audiobooks.length,
          ),
        ),
      );
    }

    final crossAxisCount = _audiobooksViewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _audiobooksViewMode == 'grid3' ? 0.65 : 0.70;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAudiobookCard(context, audiobooks[index], maProvider),
          childCount: audiobooks.length,
        ),
      ),
    );
  }

  Widget _buildAudiobookCard(BuildContext context, Audiobook book, MusicAssistantProvider maProvider) {
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = _showFavoritesOnly ? '_fav' : '';

    return GestureDetector(
      onTap: () => _navigateToAudiobook(book, heroTagSuffix: 'library$heroSuffix'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_library$heroSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      color: colorScheme.surfaceVariant,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox(),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                MdiIcons.bookOutline,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
                // Progress indicator overlay
                if (book.progress > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: book.progress,
                        backgroundColor: Colors.black38,
                        color: colorScheme.primary,
                        minHeight: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_library$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                book.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.authorsString,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesTab(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maProvider = context.read<MusicAssistantProvider>();

    // Loading state
    if (_isLoadingSeries) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading series...',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (_series.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSeries,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
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
                        'No Series Found',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _seriesLoaded
                            ? 'No series available from your audiobook library.\nPull to refresh.'
                            : 'Pull down to load series\nfrom Music Assistant',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                        onPressed: _loadSeries,
                        child: const Text('Load Series'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Series grid
    return RefreshIndicator(
      onRefresh: _loadSeries,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _series.length,
        itemBuilder: (context, index) {
          final series = _series[index];
          return _buildSeriesCard(context, series, maProvider);
        },
      ),
    );
  }

  Widget _buildSeriesCard(BuildContext context, AudiobookSeries series, MusicAssistantProvider maProvider) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          // TODO: Navigate to series detail screen
          _logger.log('📚 Tapped series: ${series.name}, path: ${series.id}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Series: ${series.name}')),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: colorScheme.surfaceContainerHighest,
                child: series.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: series.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _buildSeriesPlaceholder(colorScheme),
                        errorWidget: (_, __, ___) => _buildSeriesPlaceholder(colorScheme),
                      )
                    : _buildSeriesPlaceholder(colorScheme),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.name,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (series.bookCount != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${series.bookCount} book${series.bookCount == 1 ? '' : 's'}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesPlaceholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 48,
        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
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
