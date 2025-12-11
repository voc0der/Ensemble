import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
import '../widgets/track_row.dart';
import '../widgets/common/disconnected_state.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static final _logger = DebugLogger();
  Key _refreshKey = UniqueKey();
  // Main rows (default on)
  bool _showRecentAlbums = true;
  bool _showDiscoverArtists = true;
  bool _showDiscoverAlbums = true;
  // Favorites rows (default off)
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;
  // Random order for favorites (generated once per session)
  late List<int> _favoritesOrder;
  // Frame timing callback ID
  int? _frameCallbackId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Generate random order for favorites rows (0, 1, 2 shuffled)
    _favoritesOrder = [0, 1, 2]..shuffle();
    _loadSettings();
  }

  @override
  void dispose() {
    if (_frameCallbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frameCallbackId!);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload settings when app resumes (coming back from settings)
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final showRecent = await SettingsService.getShowRecentAlbums();
    final showDiscArtists = await SettingsService.getShowDiscoverArtists();
    final showDiscAlbums = await SettingsService.getShowDiscoverAlbums();
    final showFavAlbums = await SettingsService.getShowFavoriteAlbums();
    final showFavArtists = await SettingsService.getShowFavoriteArtists();
    final showFavTracks = await SettingsService.getShowFavoriteTracks();
    if (mounted) {
      setState(() {
        _showRecentAlbums = showRecent;
        _showDiscoverArtists = showDiscArtists;
        _showDiscoverAlbums = showDiscAlbums;
        _showFavoriteAlbums = showFavAlbums;
        _showFavoriteArtists = showFavArtists;
        _showFavoriteTracks = showFavTracks;
      });
    }
  }

  Future<void> _onRefresh() async {
    // Invalidate cache to force fresh data on pull-to-refresh
    final provider = context.read<MusicAssistantProvider>();
    provider.invalidateHomeCache();

    // Reload settings in case they changed
    await _loadSettings();

    if (mounted) {
      setState(() {
        _refreshKey = UniqueKey();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Reload settings on each build to catch changes from Settings screen
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: ColorFiltered(
            colorFilter: Theme.of(context).brightness == Brightness.light
                ? const ColorFilter.matrix(<double>[
                    -1,  0,  0, 0, 255,
                     0, -1,  0, 0, 255,
                     0,  0, -1, 0, 255,
                     0,  0,  0, 1,   0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
            child: Image.asset(
              'assets/images/ensemble_logo.png',
              height: 40,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        titleSpacing: 0,
        centerTitle: false,
        actions: [
          const PlayerSelector(),
        ],
      ),
      body: SafeArea(
        child: Selector<MusicAssistantProvider, bool>(
          selector: (_, p) => p.isConnected,
          builder: (context, isConnected, child) {
            final maProvider = context.read<MusicAssistantProvider>();
            return !isConnected
                ? DisconnectedState.full(
                    onSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.surface,
                    child: _buildConnectedView(context, maProvider),
                  );
          },
        ),
      ),
    );
  }


  Widget _buildConnectedView(
      BuildContext context, MusicAssistantProvider provider) {
    // Use LayoutBuilder to get available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Simple calculation: available height divided by 3 rows
        // Each row includes its title, artwork, and info
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;
        final rowHeight = availableHeight / 3;

        // Build favorites rows in random order
        final favoritesWidgets = _buildFavoritesRows(provider, rowHeight);

        // Use Android 12+ stretch overscroll effect
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              _logger.resetFrameStats();
              _logger.perf('SCROLL START', context: 'HomeScreen');
            } else if (notification is ScrollUpdateNotification) {
              _logger.startFrame();
              SchedulerBinding.instance.addPostFrameCallback((_) {
                _logger.endFrame();
              });
            } else if (notification is ScrollEndNotification) {
              _logger.perf('SCROLL END', context: 'HomeScreen');
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: const _StretchScrollBehavior(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: BottomSpacing.withMiniPlayer),
              child: Column(
                key: _refreshKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recently played albums (optional)
                  if (_showRecentAlbums)
                    AlbumRow(
                      key: const ValueKey('recent-albums'),
                      title: 'Recently Played',
                      loadAlbums: () => provider.getRecentAlbumsWithCache(),
                      rowHeight: rowHeight,
                    ),

                  // Discover Artists (optional)
                  if (_showDiscoverArtists)
                    ArtistRow(
                      key: const ValueKey('discover-artists'),
                      title: 'Discover Artists',
                      loadArtists: () => provider.getDiscoverArtistsWithCache(),
                      rowHeight: rowHeight,
                    ),

                  // Discover Albums (optional)
                  if (_showDiscoverAlbums)
                    AlbumRow(
                      key: const ValueKey('discover-albums'),
                      title: 'Discover Albums',
                      loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
                      rowHeight: rowHeight,
                    ),

                  // Favorites rows in random order
                  ...favoritesWidgets,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build favorites rows in random order (order set once per session)
  List<Widget> _buildFavoritesRows(MusicAssistantProvider provider, double rowHeight) {
    // Create list of enabled favorites with their order index
    final enabledFavorites = <MapEntry<int, Widget>>[];

    if (_showFavoriteAlbums) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[0],
        AlbumRow(
          key: const ValueKey('favorite-albums'),
          title: 'Favorite Albums',
          loadAlbums: () => provider.getFavoriteAlbums(),
          rowHeight: rowHeight,
        ),
      ));
    }

    if (_showFavoriteArtists) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[1],
        ArtistRow(
          key: const ValueKey('favorite-artists'),
          title: 'Favorite Artists',
          loadArtists: () => provider.getFavoriteArtists(),
          rowHeight: rowHeight,
        ),
      ));
    }

    if (_showFavoriteTracks) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[2],
        TrackRow(
          key: const ValueKey('favorite-tracks'),
          title: 'Favorite Tracks',
          loadTracks: () => provider.getFavoriteTracks(),
          rowHeight: rowHeight,
        ),
      ));
    }

    // Sort by the random order index
    enabledFavorites.sort((a, b) => a.key.compareTo(b.key));

    return enabledFavorites.map((e) => e.value).toList();
  }
}

/// Custom scroll behavior that uses Android 12+ stretch overscroll effect
class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
