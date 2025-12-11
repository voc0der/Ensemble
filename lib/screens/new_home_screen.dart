import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_selector.dart';
import '../widgets/album_row.dart';
import '../widgets/artist_row.dart';
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

  @override
  bool get wantKeepAlive => true;

  Future<void> _onRefresh() async {
    // Invalidate cache to force fresh data on pull-to-refresh
    final provider = context.read<MusicAssistantProvider>();
    provider.invalidateHomeCache();

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
    // Use LayoutBuilder to adapt to available screen height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height for content
        // We have 3 rows: 2 album rows and 1 artist row
        // Each row has ~40px for title/padding
        final availableHeight = constraints.maxHeight - BottomSpacing.withMiniPlayer;

        // Total spacing between rows
        const totalSpacing = 24.0; // 21 + 3
        const titleHeight = 40.0; // Approximate height for title text + padding
        const numRows = 3;

        // Calculate height available for row content (excluding titles and spacing)
        final contentHeight = availableHeight - totalSpacing - (titleHeight * numRows);

        // Distribute height proportionally:
        // Album rows get slightly more space (ratio 1.18:1:1.18 based on original 193:163:193)
        final totalRatio = 1.18 + 1.0 + 1.18; // 3.36
        final artistRowHeight = (contentHeight / totalRatio).clamp(120.0, 180.0);
        final albumRowHeight = (artistRowHeight * 1.18).clamp(140.0, 210.0);

        // Use Android 12+ stretch overscroll effect
        return ScrollConfiguration(
          behavior: const _StretchScrollBehavior(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            key: _refreshKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recently played albums (with caching)
              // Stable keys prevent widget recreation on parent rebuilds
              AlbumRow(
                key: const ValueKey('recent-albums'),
                title: 'Recently Played',
                loadAlbums: () => provider.getRecentAlbumsWithCache(),
                rowHeight: albumRowHeight,
              ),
              const SizedBox(height: 21),

              // Discover Artists (with caching)
              ArtistRow(
                key: const ValueKey('discover-artists'),
                title: 'Discover Artists',
                loadArtists: () => provider.getDiscoverArtistsWithCache(),
                rowHeight: artistRowHeight,
              ),
              const SizedBox(height: 3),

              // Discover Albums (with caching)
              AlbumRow(
                key: const ValueKey('discover-albums'),
                title: 'Discover Albums',
                loadAlbums: () => provider.getDiscoverAlbumsWithCache(),
                rowHeight: albumRowHeight,
              ),
              SizedBox(height: BottomSpacing.withMiniPlayer), // Space for bottom nav + mini player
            ],
            ),
          ),
        );
      },
    );
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
