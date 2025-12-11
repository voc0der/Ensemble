import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';
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

class _NewHomeScreenState extends State<NewHomeScreen> with AutomaticKeepAliveClientMixin {
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Generate random order for favorites rows (0, 1, 2 shuffled)
    _favoritesOrder = [0, 1, 2]..shuffle();
    _loadSettings();
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
    // Count enabled main rows for dynamic height calculation
    final enabledMainRows = [_showRecentAlbums, _showDiscoverArtists, _showDiscoverAlbums]
        .where((enabled) => enabled).length;

    // Use LayoutBuilder to adapt to available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height for the main rows
        // Account for bottom nav + mini player space
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;

        // Calculate spacing and heights based on enabled rows
        final numRows = enabledMainRows > 0 ? enabledMainRows : 1;
        final totalSpacing = (numRows - 1) * 8.0; // 8px between each row
        const titleHeight = 44.0; // Height for title text + padding per row (increased for top padding)

        // Calculate height available for row content (excluding titles and spacing)
        final contentHeight = availableHeight - totalSpacing - (titleHeight * numRows);

        // Distribute height based on row types
        // Album rows get slightly more space than artist rows (ratio 1.18:1)
        double albumRowHeight;
        double artistRowHeight;

        if (enabledMainRows == 0) {
          albumRowHeight = 180.0;
          artistRowHeight = 160.0;
        } else {
          // Count album vs artist rows for proportional distribution
          final albumRows = (_showRecentAlbums ? 1 : 0) + (_showDiscoverAlbums ? 1 : 0);
          final artistRows = _showDiscoverArtists ? 1 : 0;
          final totalRatio = (albumRows * 1.18) + (artistRows * 1.0);

          if (totalRatio > 0) {
            final unitHeight = contentHeight / totalRatio;
            artistRowHeight = unitHeight.clamp(120.0, 180.0);
            albumRowHeight = (unitHeight * 1.18).clamp(140.0, 210.0);
          } else {
            albumRowHeight = 180.0;
            artistRowHeight = 160.0;
          }
        }

        // Build favorites rows in random order
        final favoritesWidgets = _buildFavoritesRows(provider);

        // Use Android 12+ stretch overscroll effect
        return ScrollConfiguration(
          behavior: const _StretchScrollBehavior(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            key: _refreshKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recently played albums (optional)
              if (_showRecentAlbums) ...[
                AlbumRow(
                  key: const ValueKey('recent-albums'),
                  title: 'Recently Played',
                  loadAlbums: () => provider.getRecentAlbumsWithCache(),
                  rowHeight: albumRowHeight,
                ),
                if (_showDiscoverArtists || _showDiscoverAlbums) const SizedBox(height: 8),
              ],

              // Discover Artists (optional)
              if (_showDiscoverArtists) ...[
                ArtistRow(
                  key: const ValueKey('discover-artists'),
                  title: 'Discover Artists',
                  loadArtists: () => provider.getDiscoverArtistsWithCache(),
                  rowHeight: artistRowHeight,
                ),
                if (_showDiscoverAlbums) const SizedBox(height: 8),
              ],

              // Discover Albums (optional)
              if (_showDiscoverAlbums)
                AlbumRow(
                  key: const ValueKey('discover-albums'),
                  title: 'Discover Albums',
                  loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
                  rowHeight: albumRowHeight,
                ),

              // Favorites rows in random order
              ...favoritesWidgets,

              // Only add bottom spacing if favorites are shown (they scroll below)
              // The main rows are calculated to fit exactly without this
              if (_showFavoriteAlbums || _showFavoriteArtists || _showFavoriteTracks)
                SizedBox(height: BottomSpacing.withMiniPlayer),
            ],
            ),
          ),
        );
      },
    );
  }

  /// Build favorites rows in random order (order set once per session)
  List<Widget> _buildFavoritesRows(MusicAssistantProvider provider) {
    final widgets = <Widget>[];

    // Create list of enabled favorites with their order index
    final enabledFavorites = <MapEntry<int, Widget>>[];

    if (_showFavoriteAlbums) {
      enabledFavorites.add(MapEntry(
        _favoritesOrder[0],
        AlbumRow(
          key: const ValueKey('favorite-albums'),
          title: 'Favorite Albums',
          loadAlbums: () => provider.getFavoriteAlbums(),
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
        ),
      ));
    }

    // Sort by the random order index
    enabledFavorites.sort((a, b) => a.key.compareTo(b.key));

    // Add widgets with spacing
    for (final entry in enabledFavorites) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(entry.value);
    }

    return widgets;
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
