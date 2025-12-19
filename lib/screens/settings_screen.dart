import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../theme/theme_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'debug_log_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _lastFmApiKeyController = TextEditingController();
  final _audioDbApiKeyController = TextEditingController();
  // Main rows (default on)
  bool _showRecentAlbums = true;
  bool _showDiscoverArtists = true;
  bool _showDiscoverAlbums = true;
  // Favorites rows (default off)
  bool _showFavoriteAlbums = false;
  bool _showFavoriteArtists = false;
  bool _showFavoriteTracks = false;
  // Audiobook home rows (default off)
  bool _showContinueListeningAudiobooks = false;
  bool _showDiscoverAudiobooks = false;
  bool _showDiscoverSeries = false;
  // Home row order
  List<String> _homeRowOrder = List.from(SettingsService.defaultHomeRowOrder);
  // Audiobook libraries
  List<Map<String, String>> _discoveredLibraries = [];
  Map<String, bool> _libraryEnabled = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final lastFmKey = await SettingsService.getLastFmApiKey();
    if (lastFmKey != null) {
      _lastFmApiKeyController.text = lastFmKey;
    }

    final audioDbKey = await SettingsService.getTheAudioDbApiKey();
    if (audioDbKey != null) {
      _audioDbApiKeyController.text = audioDbKey;
    }

    // Load home screen settings
    final showRecent = await SettingsService.getShowRecentAlbums();
    final showDiscArtists = await SettingsService.getShowDiscoverArtists();
    final showDiscAlbums = await SettingsService.getShowDiscoverAlbums();
    final showFavAlbums = await SettingsService.getShowFavoriteAlbums();
    final showFavArtists = await SettingsService.getShowFavoriteArtists();
    final showFavTracks = await SettingsService.getShowFavoriteTracks();

    // Load audiobook home row settings
    final showContinueAudiobooks = await SettingsService.getShowContinueListeningAudiobooks();
    final showDiscAudiobooks = await SettingsService.getShowDiscoverAudiobooks();
    final showDiscSeries = await SettingsService.getShowDiscoverSeries();

    // Load home row order
    final rowOrder = await SettingsService.getHomeRowOrder();

    // Load audiobook library settings
    final discovered = await SettingsService.getDiscoveredAbsLibraries() ?? [];
    final enabled = await SettingsService.getEnabledAbsLibraries();
    final libraryEnabled = <String, bool>{};
    for (final lib in discovered) {
      final path = lib['path'] ?? '';
      // null means all enabled
      libraryEnabled[path] = enabled == null || enabled.contains(path);
    }

    if (mounted) {
      setState(() {
        _showRecentAlbums = showRecent;
        _showDiscoverArtists = showDiscArtists;
        _showDiscoverAlbums = showDiscAlbums;
        _showFavoriteAlbums = showFavAlbums;
        _showFavoriteArtists = showFavArtists;
        _showFavoriteTracks = showFavTracks;
        _showContinueListeningAudiobooks = showContinueAudiobooks;
        _showDiscoverAudiobooks = showDiscAudiobooks;
        _showDiscoverSeries = showDiscSeries;
        _homeRowOrder = rowOrder;
        _discoveredLibraries = discovered;
        _libraryEnabled = libraryEnabled;
      });
    }
  }

  @override
  void dispose() {
    _lastFmApiKeyController.dispose();
    _audioDbApiKeyController.dispose();
    super.dispose();
  }

  // Helper to get row display info
  Map<String, String> _getRowInfo(String rowId) {
    switch (rowId) {
      case 'recent-albums':
        return {'title': 'Recently Played', 'subtitle': 'Show recently played albums'};
      case 'discover-artists':
        return {'title': 'Discover Artists', 'subtitle': 'Show random artists to discover'};
      case 'discover-albums':
        return {'title': 'Discover Albums', 'subtitle': 'Show random albums to discover'};
      case 'continue-listening':
        return {'title': 'Continue Listening', 'subtitle': 'Show audiobooks in progress'};
      case 'discover-audiobooks':
        return {'title': 'Discover Audiobooks', 'subtitle': 'Show random audiobooks to discover'};
      case 'discover-series':
        return {'title': 'Discover Series', 'subtitle': 'Show random audiobook series to discover'};
      case 'favorite-albums':
        return {'title': 'Favorite Albums', 'subtitle': 'Show a row of your favorite albums'};
      case 'favorite-artists':
        return {'title': 'Favorite Artists', 'subtitle': 'Show a row of your favorite artists'};
      case 'favorite-tracks':
        return {'title': 'Favorite Tracks', 'subtitle': 'Show a row of your favorite tracks'};
      default:
        return {'title': rowId, 'subtitle': ''};
    }
  }

  // Helper to get row enabled state
  bool _getRowEnabled(String rowId) {
    switch (rowId) {
      case 'recent-albums':
        return _showRecentAlbums;
      case 'discover-artists':
        return _showDiscoverArtists;
      case 'discover-albums':
        return _showDiscoverAlbums;
      case 'continue-listening':
        return _showContinueListeningAudiobooks;
      case 'discover-audiobooks':
        return _showDiscoverAudiobooks;
      case 'discover-series':
        return _showDiscoverSeries;
      case 'favorite-albums':
        return _showFavoriteAlbums;
      case 'favorite-artists':
        return _showFavoriteArtists;
      case 'favorite-tracks':
        return _showFavoriteTracks;
      default:
        return false;
    }
  }

  // Helper to set row enabled state
  void _setRowEnabled(String rowId, bool value) {
    setState(() {
      switch (rowId) {
        case 'recent-albums':
          _showRecentAlbums = value;
          SettingsService.setShowRecentAlbums(value);
          break;
        case 'discover-artists':
          _showDiscoverArtists = value;
          SettingsService.setShowDiscoverArtists(value);
          break;
        case 'discover-albums':
          _showDiscoverAlbums = value;
          SettingsService.setShowDiscoverAlbums(value);
          break;
        case 'continue-listening':
          _showContinueListeningAudiobooks = value;
          SettingsService.setShowContinueListeningAudiobooks(value);
          break;
        case 'discover-audiobooks':
          _showDiscoverAudiobooks = value;
          SettingsService.setShowDiscoverAudiobooks(value);
          break;
        case 'discover-series':
          _showDiscoverSeries = value;
          SettingsService.setShowDiscoverSeries(value);
          break;
        case 'favorite-albums':
          _showFavoriteAlbums = value;
          SettingsService.setShowFavoriteAlbums(value);
          break;
        case 'favorite-artists':
          _showFavoriteArtists = value;
          SettingsService.setShowFavoriteArtists(value);
          break;
        case 'favorite-tracks':
          _showFavoriteTracks = value;
          SettingsService.setShowFavoriteTracks(value);
          break;
      }
    });
  }

  Future<void> _disconnect() async {
    final provider = context.read<MusicAssistantProvider>();
    await provider.disconnect();

    // Clear saved server URL so login screen shows
    await SettingsService.clearServerUrl();

    if (mounted) {
      // Navigate to login screen and clear the navigation stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: colorScheme.onBackground,
        ),
        title: Text(
          'Settings',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onBackground,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugLogScreen(),
                ),
              );
            },
            color: colorScheme.onBackground,
            tooltip: 'Debug Logs',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Logo - same size as login screen (50% of screen width)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 48.0),
              child: Image.asset(
                'assets/images/ensemble_icon_transparent.png',
                width: MediaQuery.of(context).size.width * 0.5,
                fit: BoxFit.contain,
              ),
            ),

            // Connection status box - centered with border radius like theme boxes
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getStatusIcon(provider.connectionState),
                    color: _getStatusColor(provider.connectionState, colorScheme),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStatusText(provider.connectionState),
                    style: textTheme.titleMedium?.copyWith(
                      color: _getStatusColor(provider.connectionState, colorScheme),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Disconnect button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.tonalIcon(
                onPressed: _disconnect,
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Disconnect',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer.withOpacity(0.4),
                  foregroundColor: colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Theme section
            Text(
              'Theme',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Mode',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.light,
                              label: Text('Light'),
                              icon: Icon(Icons.light_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                              icon: Icon(Icons.dark_mode_rounded),
                            ),
                            ButtonSegment<ThemeMode>(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.auto_mode_rounded),
                            ),
                          ],
                          selected: {themeProvider.themeMode},
                          onSelectionChanged: (Set<ThemeMode> newSelection) {
                            themeProvider.setThemeMode(newSelection.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return colorScheme.primaryContainer;
                              }
                              return colorScheme.surfaceVariant.withOpacity(0.3);
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return colorScheme.onPrimaryContainer;
                              }
                              return colorScheme.onSurfaceVariant;
                            }),
                            side: WidgetStateProperty.all(BorderSide.none),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      'Material You',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Use system colors (Android 12+)',
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    value: themeProvider.useMaterialTheme,
                    onChanged: (value) {
                      themeProvider.setUseMaterialTheme(value);
                    },
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      'Adaptive Theme',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Extract colors from album and artist artwork',
                      style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    ),
                    value: themeProvider.adaptiveTheme,
                    onChanged: (value) {
                      themeProvider.setAdaptiveTheme(value);
                    },
                    activeColor: colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Home Screen section
            Text(
              'Home Screen',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which rows to display on the home screen',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            // Reorderable home rows list
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _homeRowOrder.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _homeRowOrder.removeAt(oldIndex);
                    _homeRowOrder.insert(newIndex, item);
                  });
                  SettingsService.setHomeRowOrder(_homeRowOrder);
                },
                itemBuilder: (context, index) {
                  final rowId = _homeRowOrder[index];
                  final rowInfo = _getRowInfo(rowId);
                  final isEnabled = _getRowEnabled(rowId);

                  return Container(
                    key: ValueKey(rowId),
                    decoration: BoxDecoration(
                      border: index < _homeRowOrder.length - 1
                          ? Border(bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2)))
                          : null,
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            child: Icon(
                              Icons.drag_handle,
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: Text(
                              rowInfo['title']!,
                              style: TextStyle(color: colorScheme.onSurface),
                            ),
                            subtitle: Text(
                              rowInfo['subtitle']!,
                              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                            ),
                            value: isEnabled,
                            onChanged: (value) => _setRowEnabled(rowId, value),
                            activeColor: colorScheme.primary,
                            contentPadding: const EdgeInsets.only(right: 8),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Metadata APIs (Optional)',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onBackground,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Artist images are automatically fetched from Deezer. Add API keys below for artist biographies and album descriptions.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _lastFmApiKeyController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Last.fm API Key',
                hintText: 'Get free key at last.fm/api',
                hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(
                  Icons.music_note_rounded,
                  color: colorScheme.onSurface.withOpacity(0.54),
                ),
                suffixIcon: _lastFmApiKeyController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _lastFmApiKeyController.clear();
                          });
                          SettingsService.setLastFmApiKey(null);
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                SettingsService.setLastFmApiKey(value.trim().isEmpty ? null : value.trim());
                setState(() {}); // Update UI to show/hide clear button
              },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _audioDbApiKeyController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'TheAudioDB API Key',
                hintText: 'Use "2" for free tier or premium key',
                hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.38)),
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(
                  Icons.audiotrack_rounded,
                  color: colorScheme.onSurface.withOpacity(0.54),
                ),
                suffixIcon: _audioDbApiKeyController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _audioDbApiKeyController.clear();
                          });
                          SettingsService.setTheAudioDbApiKey(null);
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                SettingsService.setTheAudioDbApiKey(value.trim().isEmpty ? null : value.trim());
                setState(() {}); // Update UI to show/hide clear button
              },
            ),

            const SizedBox(height: 32),

            // Audiobook Libraries section
            if (_discoveredLibraries.isNotEmpty) ...[
              Text(
                'Audiobook Libraries',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onBackground,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which Audiobookshelf libraries to include',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: _discoveredLibraries.asMap().entries.map((entry) {
                    final index = entry.key;
                    final library = entry.value;
                    final path = library['path'] ?? '';
                    final name = library['name'] ?? 'Unknown Library';
                    final isEnabled = _libraryEnabled[path] ?? true;

                    return Column(
                      children: [
                        SwitchListTile(
                          title: Text(
                            name,
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                          value: isEnabled,
                          onChanged: (value) async {
                            setState(() {
                              _libraryEnabled[path] = value;
                            });
                            await SettingsService.toggleAbsLibrary(path, value);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Pull to refresh the library to apply changes'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          activeColor: colorScheme.primary,
                        ),
                        if (index < _discoveredLibraries.length - 1)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: colorScheme.onSurface.withOpacity(0.1),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 32),
            ],

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugLogScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report_rounded),
                label: const Text('View Debug Logs'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            SizedBox(height: BottomSpacing.navBarOnly), // Space for bottom nav bar
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return Icons.check_circle_rounded;
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return Icons.sync_rounded;
      case MAConnectionState.error:
        return Icons.error_rounded;
      case MAConnectionState.disconnected:
        return Icons.cloud_off_rounded;
    }
  }

  Color _getStatusColor(MAConnectionState state, ColorScheme colorScheme) {
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return Colors.green;
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return Colors.orange;
      case MAConnectionState.error:
        return colorScheme.error;
      case MAConnectionState.disconnected:
        return colorScheme.onSurface.withOpacity(0.5);
    }
  }

  String _getStatusText(MAConnectionState state) {
    switch (state) {
      case MAConnectionState.connected:
      case MAConnectionState.authenticated:
        return 'Connected';
      case MAConnectionState.connecting:
      case MAConnectionState.authenticating:
        return 'Connecting...';
      case MAConnectionState.error:
        return 'Connection Error';
      case MAConnectionState.disconnected:
        return 'Disconnected';
    }
  }
}
