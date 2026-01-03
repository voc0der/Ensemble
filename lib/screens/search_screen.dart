import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../services/database_service.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/player_picker_sheet.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../widgets/artist_avatar.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import 'album_details_screen.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'audiobook_detail_screen.dart';
import '../l10n/app_localizations.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

// Helper enum and class for ListView.builder item types
enum _ListItemType { header, artist, album, track, playlist, audiobook, spacer }

class _ListItem {
  final _ListItemType type;
  final MediaItem? mediaItem;
  final String? headerTitle;
  final int? headerCount;
  final double? relevanceScore; // For unified view sorting

  _ListItem.header(this.headerTitle, this.headerCount)
      : type = _ListItemType.header,
        mediaItem = null,
        relevanceScore = null;

  _ListItem.artist(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.artist,
        headerTitle = null,
        headerCount = null;

  _ListItem.album(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.album,
        headerTitle = null,
        headerCount = null;

  _ListItem.track(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.track,
        headerTitle = null,
        headerCount = null;

  _ListItem.playlist(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.playlist,
        headerTitle = null,
        headerCount = null;

  _ListItem.audiobook(this.mediaItem, {this.relevanceScore})
      : type = _ListItemType.audiobook,
        headerTitle = null,
        headerCount = null;

  _ListItem.spacer()
      : type = _ListItemType.spacer,
        mediaItem = null,
        headerTitle = null,
        headerCount = null,
        relevanceScore = null;
}

class SearchScreenState extends State<SearchScreen> {
  final _logger = DebugLogger();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();
  final ScrollController _filterScrollController = ScrollController();
  Timer? _debounceTimer;
  Map<String, List<MediaItem>> _searchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
    'playlists': [],
    'audiobooks': [],
    'podcasts': [],
  };
  bool _isSearching = false;
  bool _hasSearched = false;
  String _activeFilter = 'all'; // 'all', 'artists', 'albums', 'tracks', 'playlists', 'audiobooks'
  String? _searchError;
  List<String> _recentSearches = [];
  bool _libraryOnly = false;
  String? _expandedTrackId; // Track ID for expanded quick actions
  bool _hasSearchText = false; // PERF: Track separately to avoid rebuild on every keystroke

  // PERF: Cache list items per filter to avoid rebuilding during PageView animation
  Map<String, List<_ListItem>> _cachedListItems = {};
  // PERF: Cache available filters to avoid recalculating during build
  List<String>? _cachedAvailableFilters;

  // Scroll-to-hide search bar (vertical scroll only)
  bool _isSearchBarVisible = true;
  double _lastVerticalScrollOffset = 0;
  static const double _scrollThreshold = 10.0;

  @override
  void initState() {
    super.initState();
    // Don't auto-focus - let user tap to focus
    // This prevents keyboard popup bug when SearchScreen is in widget tree but not visible
    _loadRecentSearches();
  }

  /// Get list of available filters based on current results (cached)
  List<String> _getAvailableFilters() {
    if (_cachedAvailableFilters != null) return _cachedAvailableFilters!;

    final filters = <String>['all'];
    if (_searchResults['artists']?.isNotEmpty == true) filters.add('artists');
    if (_searchResults['albums']?.isNotEmpty == true) filters.add('albums');
    if (_searchResults['tracks']?.isNotEmpty == true) filters.add('tracks');
    if (_searchResults['playlists']?.isNotEmpty == true) filters.add('playlists');
    if (_searchResults['audiobooks']?.isNotEmpty == true) filters.add('audiobooks');
    // Always show podcasts filter (placeholder until fully integrated)
    filters.add('podcasts');
    _cachedAvailableFilters = filters;
    return filters;
  }

  /// Animate to a specific filter
  void _animateToFilter(String filter) {
    final filters = _getAvailableFilters();
    final index = filters.indexOf(filter);
    if (index >= 0 && _pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Handle page change from swipe gesture
  void _onPageChanged(int pageIndex) {
    final filters = _getAvailableFilters();
    if (pageIndex >= 0 && pageIndex < filters.length) {
      setState(() {
        _activeFilter = filters[pageIndex];
      });
      _scrollFilterIntoView(pageIndex);
    }
  }

  /// Scroll filter bar to keep active filter visible
  /// Only scrolls when the filter would be obscured (off-screen)
  /// Uses post-frame callback to avoid interfering with PageView animation
  void _scrollFilterIntoView(int filterIndex) {
    if (!_filterScrollController.hasClients) return;

    // Defer scroll calculation to after the frame to avoid layout during animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_filterScrollController.hasClients) return;

      final maxScroll = _filterScrollController.position.maxScrollExtent;

      // If all filters fit on screen, don't scroll at all
      if (maxScroll <= 0) return;

      // Approximate width per filter chip (padding + text)
      const chipWidth = 80.0;
      const horizontalPadding = 16.0;

      final currentScroll = _filterScrollController.offset;
      final viewportWidth = _filterScrollController.position.viewportDimension;

      // Calculate the left and right edges of the active filter chip
      final chipLeft = (filterIndex * chipWidth);
      final chipRight = chipLeft + chipWidth;

      // Calculate what's currently visible in the viewport
      final visibleLeft = currentScroll;
      final visibleRight = currentScroll + viewportWidth - (horizontalPadding * 2);

      // Only scroll if the chip is actually obscured
      double? targetOffset;

      if (chipRight > visibleRight) {
        // Chip is cut off on the right - scroll right just enough to show it
        targetOffset = chipRight - viewportWidth + (horizontalPadding * 2);
      } else if (chipLeft < visibleLeft) {
        // Chip is cut off on the left - scroll left just enough to show it
        targetOffset = chipLeft;
      }

      // Only animate if we need to scroll
      if (targetOffset != null) {
        final clampedOffset = targetOffset.clamp(0.0, maxScroll);
        _filterScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    if (!DatabaseService.instance.isInitialized) return;
    final searches = await DatabaseService.instance.getRecentSearches();
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  void requestFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void removeFocus() {
    if (mounted) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _pageController.dispose();
    _filterScrollController.dispose();
    super.dispose();
  }

  /// Handle scroll notifications - only vertical scroll hides search bar
  bool _handleScrollNotification(ScrollNotification notification) {
    // Only respond to vertical scroll (not horizontal PageView swipe)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final currentOffset = notification.metrics.pixels;
      final delta = currentOffset - _lastVerticalScrollOffset;

      if (delta.abs() > _scrollThreshold) {
        final shouldShow = delta < 0 || currentOffset <= 0;
        if (shouldShow != _isSearchBarVisible) {
          setState(() {
            _isSearchBarVisible = shouldShow;
          });
        }
        _lastVerticalScrollOffset = currentOffset;
      }
    }
    return false;
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Timings.searchDebounce, () {
      _performSearch(query, keepFocus: true);
    });
  }

  Future<void> _performSearch(String query, {bool keepFocus = false}) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'podcasts': []};
        _hasSearched = false;
        _searchError = null;
        _cachedListItems.clear(); // PERF: Clear cache
        _cachedAvailableFilters = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final provider = context.read<MusicAssistantProvider>();
      final results = await provider.searchWithCache(query, libraryOnly: _libraryOnly);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _hasSearched = true;
          _cachedListItems.clear(); // PERF: Clear cache on new results
          _cachedAvailableFilters = null;
        });

        // Save to search history if we got results
        final hasResults = results.values.any((list) => list.isNotEmpty);
        if (hasResults && DatabaseService.instance.isInitialized) {
          DatabaseService.instance.saveSearchQuery(query);
          _loadRecentSearches(); // Refresh the list
        }

        // Keep keyboard open if user is still typing
        if (keepFocus && _focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      }
    } catch (e) {
      _logger.log('Search error: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _hasSearched = true;
          _searchError = S.of(context)!.searchFailed;
        });
        if (keepFocus && _focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // PERF: Only rebuild when connection status changes, not on every provider update
    final isConnected = context.select<MusicAssistantProvider, bool>((p) => p.isConnected);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Animated search bar - hides on scroll down
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: _isSearchBarVisible ? kToolbarHeight + 16 : 0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // Search field
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            style: TextStyle(color: colorScheme.onSurface),
                            cursorColor: colorScheme.primary,
                            textInputAction: TextInputAction.search,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              hintText: S.of(context)!.searchMusic,
                              hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                              border: InputBorder.none,
                              suffixIcon: _hasSearchText
                                  ? IconButton(
                                      icon: Icon(Icons.clear_rounded, color: colorScheme.onSurface.withOpacity(0.5)),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _hasSearchText = false;
                                          _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': [], 'podcasts': []};
                                          _hasSearched = false;
                                          _searchError = null;
                                          _cachedListItems.clear();
                                          _cachedAvailableFilters = null;
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              // PERF: Only rebuild when clear button visibility changes
                              final hasText = value.isNotEmpty;
                              if (hasText != _hasSearchText) {
                                setState(() {
                                  _hasSearchText = hasText;
                                });
                              }
                              _onSearchChanged(value);
                            },
                            onSubmitted: (query) => _performSearch(query),
                          ),
                        ),
                      ),
                      // Library-only toggle
                      Tooltip(
                        message: S.of(context)!.libraryOnly,
                        child: IconButton(
                          icon: Icon(
                            _libraryOnly ? Icons.library_music : Icons.library_music_outlined,
                            color: _libraryOnly ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.5),
                          ),
                          onPressed: () {
                            setState(() {
                              _libraryOnly = !_libraryOnly;
                            });
                            if (_searchController.text.isNotEmpty) {
                              _performSearch(_searchController.text);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Main content
            Expanded(
              child: !isConnected
                  ? DisconnectedState.simple(context)
                  : _buildSearchContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final colorScheme = Theme.of(context).colorScheme;

    // Show cached results even while searching - only show spinner if no cached results
    final hasCachedResults = _searchResults['artists']?.isNotEmpty == true ||
                             _searchResults['albums']?.isNotEmpty == true ||
                             _searchResults['tracks']?.isNotEmpty == true ||
                             _searchResults['playlists']?.isNotEmpty == true ||
                             _searchResults['audiobooks']?.isNotEmpty == true;

    if (_isSearching && !hasCachedResults) {
      return Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 80,
              color: colorScheme.onBackground.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context)!.searchForContent,
              style: TextStyle(
                color: colorScheme.onBackground.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
            // Show recent searches if available
            if (_recentSearches.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                S.of(context)!.recentSearches,
                style: TextStyle(
                  color: colorScheme.onBackground.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _recentSearches.map((query) => ActionChip(
                    label: Text(query),
                    onPressed: () {
                      _searchController.text = query;
                      _performSearch(query);
                    },
                    backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5),
                    side: BorderSide.none,
                  )).toList(),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: colorScheme.error.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _searchError!,
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _performSearch(_searchController.text),
              child: Text(S.of(context)!.retry),
            ),
          ],
        ),
      );
    }

    final artists = _searchResults['artists'] as List<MediaItem>? ?? [];
    final albums = _searchResults['albums'] as List<MediaItem>? ?? [];
    final tracks = _searchResults['tracks'] as List<MediaItem>? ?? [];
    final playlists = _searchResults['playlists'] as List<MediaItem>? ?? [];
    final audiobooks = _searchResults['audiobooks'] as List<MediaItem>? ?? [];

    final hasResults = artists.isNotEmpty || albums.isNotEmpty || tracks.isNotEmpty ||
                       playlists.isNotEmpty || audiobooks.isNotEmpty;

    if (!hasResults) {
      return EmptyState.search(context: context);
    }

    // Column layout - filter bar above results, no overlay
    return Column(
      children: [
        // Filter tabs - rounded container matching search bar width
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            height: 44, // Match library screen filter row height
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                controller: _filterScrollController,
                scrollDirection: Axis.horizontal,
                child: _buildFilterSelector(colorScheme),
              ),
            ),
          ),
        ),
        // Results with swipeable pages
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _getAvailableFilters().length,
              itemBuilder: (context, pageIndex) {
                final filters = _getAvailableFilters();
                final filterForPage = filters[pageIndex];

                // PERF: Use cached list items to avoid rebuilding during animation
                final listItems = _cachedListItems[filterForPage] ??= _buildListItemsForFilter(
                  filterForPage, artists, albums, tracks, playlists, audiobooks,
                );

                // PERF: Wrap each page in RepaintBoundary to isolate repaints during swipe
                return RepaintBoundary(
                  key: ValueKey('page_$filterForPage'),
                  child: ListView.builder(
                    // PERF: Use key to preserve scroll position per filter
                    key: PageStorageKey('list_$filterForPage'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, BottomSpacing.navBarOnly),
                    cacheExtent: 500,
                    addAutomaticKeepAlives: false,
                    // PERF: false because each tile already has RepaintBoundary
                    addRepaintBoundaries: false,
                    itemCount: listItems.length,
                    itemBuilder: (context, index) {
                      final item = listItems[index];
                      final showTypeInSubtitle = filterForPage == 'all';
                      switch (item.type) {
                        case _ListItemType.header:
                          return _buildSectionHeader(item.headerTitle!, item.headerCount!);
                        case _ListItemType.artist:
                          return _buildArtistTile(item.mediaItem! as Artist);
                        case _ListItemType.album:
                          return _buildAlbumTile(item.mediaItem! as Album, showType: showTypeInSubtitle);
                        case _ListItemType.track:
                          return _buildTrackTile(item.mediaItem! as Track, showType: showTypeInSubtitle);
                        case _ListItemType.playlist:
                          return _buildPlaylistTile(item.mediaItem! as Playlist, showType: showTypeInSubtitle);
                        case _ListItemType.audiobook:
                          return _buildAudiobookTile(item.mediaItem! as Audiobook, showType: showTypeInSubtitle);
                        case _ListItemType.spacer:
                          return const SizedBox(height: 24);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Calculate relevance score for a media item based on query match
  double _calculateRelevanceScore(MediaItem item, String query) {
    final queryLower = query.toLowerCase().trim();
    if (queryLower.isEmpty) return 0;

    double score = 0;
    final nameLower = item.name.toLowerCase();

    // Primary name matching
    if (nameLower == queryLower) {
      score = 100; // Exact match
    } else if (nameLower.startsWith(queryLower)) {
      score = 80; // Starts with query
    } else if (_matchesWordBoundary(nameLower, queryLower)) {
      score = 60; // Contains query at word boundary
    } else if (nameLower.contains(queryLower)) {
      score = 40; // Contains query anywhere
    } else {
      score = 20; // Fuzzy/partial match (MA returned it, so some relevance)
    }

    // Bonus for library items (Album has inLibrary property)
    if (item is Album && item.inLibrary) {
      score += 10;
    }

    // Bonus for favorites
    if (item.favorite == true) {
      score += 5;
    }

    // Secondary field matching (artist name for albums/tracks)
    if (item is Album) {
      final artistLower = item.artistsString.toLowerCase();
      if (artistLower == queryLower) {
        score += 15; // Artist exact match
      } else if (artistLower.contains(queryLower)) {
        score += 8; // Artist contains query
      }
    } else if (item is Track) {
      final artistLower = item.artistsString.toLowerCase();
      if (artistLower == queryLower) {
        score += 15;
      } else if (artistLower.contains(queryLower)) {
        score += 8;
      }
      // Also check album name for tracks
      if (item.album?.name != null) {
        final albumLower = item.album!.name.toLowerCase();
        if (albumLower.contains(queryLower)) {
          score += 5;
        }
      }
    }

    return score;
  }

  /// Check if query matches at a word boundary in text
  bool _matchesWordBoundary(String text, String query) {
    final words = text.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith(query)) return true;
    }
    return false;
  }

  /// Extract artists from tracks/albums that match the query but aren't in direct results
  /// This enables cross-referencing: searching "Yesterday Beatles" will include The Beatles artist
  List<Artist> _extractCrossReferencedArtists(
    String query,
    List<Artist> directArtists,
    List<Album> albums,
    List<Track> tracks,
  ) {
    if (query.isEmpty) return [];

    final queryLower = query.toLowerCase();
    final queryWords = queryLower.split(RegExp(r'\s+'));

    // Create a set of existing artist identifiers to avoid duplicates
    final existingArtistKeys = <String>{};
    for (final artist in directArtists) {
      existingArtistKeys.add('${artist.provider}:${artist.itemId}');
    }

    // Collect unique artists from tracks and albums
    final candidateArtists = <String, Artist>{};

    for (final track in tracks) {
      if (track.artists != null) {
        for (final artist in track.artists!) {
          final key = '${artist.provider}:${artist.itemId}';
          if (!existingArtistKeys.contains(key) && !candidateArtists.containsKey(key)) {
            candidateArtists[key] = artist;
          }
        }
      }
    }

    for (final album in albums) {
      if (album.artists != null) {
        for (final artist in album.artists!) {
          final key = '${artist.provider}:${artist.itemId}';
          if (!existingArtistKeys.contains(key) && !candidateArtists.containsKey(key)) {
            candidateArtists[key] = artist;
          }
        }
      }
    }

    // Filter candidates: only include if artist name contains any query word
    final crossRefArtists = <Artist>[];
    for (final artist in candidateArtists.values) {
      final artistLower = artist.name.toLowerCase();
      for (final word in queryWords) {
        if (word.length >= 3 && artistLower.contains(word)) {
          crossRefArtists.add(artist);
          break;
        }
      }
    }

    return crossRefArtists;
  }

  /// Build list items for a specific filter (used by PageView)
  List<_ListItem> _buildListItemsForFilter(
    String filter,
    List<MediaItem> artists,
    List<MediaItem> albums,
    List<MediaItem> tracks,
    List<MediaItem> playlists,
    List<MediaItem> audiobooks,
  ) {
    final items = <_ListItem>[];
    final query = _searchController.text;

    // For 'all' filter, create unified relevance-sorted list
    if (filter == 'all') {
      final scoredItems = <_ListItem>[];

      for (final artist in artists) {
        final score = _calculateRelevanceScore(artist, query);
        scoredItems.add(_ListItem.artist(artist, relevanceScore: score));
      }
      for (final album in albums) {
        final score = _calculateRelevanceScore(album, query);
        scoredItems.add(_ListItem.album(album, relevanceScore: score));
      }
      for (final track in tracks) {
        final score = _calculateRelevanceScore(track, query);
        scoredItems.add(_ListItem.track(track, relevanceScore: score));
      }
      for (final playlist in playlists) {
        final score = _calculateRelevanceScore(playlist, query);
        scoredItems.add(_ListItem.playlist(playlist, relevanceScore: score));
      }
      for (final audiobook in audiobooks) {
        final score = _calculateRelevanceScore(audiobook, query);
        scoredItems.add(_ListItem.audiobook(audiobook, relevanceScore: score));
      }

      final crossRefArtists = _extractCrossReferencedArtists(
        query,
        artists.whereType<Artist>().toList(),
        albums.whereType<Album>().toList(),
        tracks.whereType<Track>().toList(),
      );
      for (final artist in crossRefArtists) {
        scoredItems.add(_ListItem.artist(artist, relevanceScore: 25));
      }

      scoredItems.sort((a, b) => (b.relevanceScore ?? 0).compareTo(a.relevanceScore ?? 0));
      return scoredItems;
    }

    // For specific type filters
    if (filter == 'artists' && artists.isNotEmpty) {
      for (final artist in artists) {
        items.add(_ListItem.artist(artist));
      }
    }

    if (filter == 'albums' && albums.isNotEmpty) {
      for (final album in albums) {
        items.add(_ListItem.album(album));
      }
    }

    if (filter == 'tracks' && tracks.isNotEmpty) {
      for (final track in tracks) {
        items.add(_ListItem.track(track));
      }
    }

    if (filter == 'playlists' && playlists.isNotEmpty) {
      for (final playlist in playlists) {
        items.add(_ListItem.playlist(playlist));
      }
    }

    if (filter == 'audiobooks' && audiobooks.isNotEmpty) {
      for (final audiobook in audiobooks) {
        items.add(_ListItem.audiobook(audiobook));
      }
    }

    return items;
  }

  /// Build joined segmented filter selector (like library media type selector)
  Widget _buildFilterSelector(ColorScheme colorScheme) {
    final filters = _getAvailableFilters();
    final l10n = S.of(context)!;

    String getLabel(String filter) {
      switch (filter) {
        case 'all': return l10n.all;
        case 'artists': return l10n.artists;
        case 'albums': return l10n.albums;
        case 'tracks': return l10n.tracks;
        case 'playlists': return l10n.playlists;
        case 'audiobooks': return l10n.audiobooks;
        case 'podcasts': return l10n.podcasts;
        default: return filter;
      }
    }

    // No ClipRRect here - parent container handles clipping with rounded corners
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: filters.map((filter) {
        final isSelected = _activeFilter == filter;
        return Material(
          // Use theme-aware colors for light/dark mode support
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceVariant.withOpacity(0.6),
          child: InkWell(
            onTap: () {
              setState(() {
                _activeFilter = filter;
              });
              _animateToFilter(filter);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                getLabel(filter),
                style: TextStyle(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onBackground,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildArtistTile(Artist artist) {
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(artist, size: 256);

    // Use 'search' suffix to avoid hero tag conflicts with library cards
    const heroSuffix = '_search';
    final artistId = artist.uri ?? artist.itemId;

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(artistId),
        leading: Hero(
          tag: HeroTags.artistImage + artistId + heroSuffix,
          child: ArtistAvatar(
            artist: artist,
            radius: 24,
            imageSize: 128,
          ),
        ),
        title: Text(
          artist.name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          S.of(context)!.artist,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
        ),
        onTap: () {
          // Update adaptive colors before navigation
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: ArtistDetailsScreen(
                artist: artist,
                heroTagSuffix: 'search',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumTile(Album album, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(album, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleText = showType
        ? '${album.artistsString} • ${S.of(context)!.albumSingular}'
        : album.artistsString;

    // Use 'search' suffix to avoid hero tag conflicts with library cards
    const heroSuffix = '_search';
    final albumId = album.uri ?? album.itemId;

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(albumId),
        leading: Hero(
          tag: HeroTags.albumCover + albumId + heroSuffix,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Icon(Icons.album_rounded, color: colorScheme.onSurfaceVariant)
                : null,
          ),
        ),
        title: Hero(
          tag: HeroTags.albumTitle + albumId + heroSuffix,
          child: Material(
            color: Colors.transparent,
            child: Text(
              album.nameWithYear,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        subtitle: Hero(
          tag: HeroTags.artistName + albumId + heroSuffix,
          child: Material(
            color: Colors.transparent,
            child: Text(
              subtitleText,
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        onTap: () {
          // Update adaptive colors before navigation
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: album,
                heroTagSuffix: 'search',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrackTile(Track track, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = track.album != null
        ? maProvider.getImageUrl(track.album!, size: 128)
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleText = showType
        ? '${track.artistsString} • ${S.of(context)!.trackSingular}'
        : track.artistsString;
    final trackId = track.uri ?? track.itemId;
    final isExpanded = _expandedTrackId == trackId;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: ValueKey(trackId),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                image: imageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(imageUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: imageUrl == null
                  ? Icon(Icons.music_note_rounded, color: colorScheme.onSurfaceVariant)
                  : null,
            ),
            title: Text(
              track.name,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitleText,
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: track.duration != null
                ? Text(
                    _formatDuration(track.duration!),
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                  )
                : null,
            onTap: () {
              if (isExpanded) {
                setState(() => _expandedTrackId = null);
              } else {
                _playTrack(track);
              }
            },
            onLongPress: () {
              setState(() {
                _expandedTrackId = isExpanded ? null : trackId;
              });
            },
          ),
          // Expandable quick actions row
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(right: 16.0, bottom: 12.0, top: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Radio button (uses current player - 1 tap)
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton.tonal(
                            onPressed: () => _playRadio(track),
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
                        // Radio On button (pick player - 2 taps)
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton.tonal(
                            onPressed: () => _showRadioOnMenu(track),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Icon(Icons.speaker_group_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Add to queue button (uses current player - 1 tap)
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton.tonal(
                            onPressed: () => _addToQueue(track),
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
                            onPressed: () => _toggleTrackFavorite(track),
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
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
      ),
    );
  }

  Widget _buildPlaylistTile(Playlist playlist, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(playlist, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleText = showType
        ? (playlist.owner != null ? '${playlist.owner} • ${S.of(context)!.playlist}' : S.of(context)!.playlist)
        : (playlist.owner ?? S.of(context)!.playlist);

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(playlist.uri ?? playlist.itemId),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            image: imageUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(imageUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: imageUrl == null
              ? Icon(Icons.queue_music_rounded, color: colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Text(
          playlist.name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitleText,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: playlist.trackCount != null
            ? Text(
                S.of(context)!.trackCount(playlist.trackCount!),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
              )
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

  Widget _buildAudiobookTile(Audiobook audiobook, {bool showType = false}) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(audiobook, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final authorText = audiobook.authors?.map((a) => a.name).join(', ') ?? S.of(context)!.unknownAuthor;
    final subtitleText = showType
        ? '$authorText • ${S.of(context)!.audiobookSingular}'
        : authorText;

    // Use 'search' suffix to avoid hero tag conflicts with library cards
    const heroSuffix = '_search';
    final audiobookId = audiobook.uri ?? audiobook.itemId;

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(audiobookId),
        leading: Hero(
          tag: HeroTags.audiobookCover + audiobookId + heroSuffix,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Icon(Icons.headphones_rounded, color: colorScheme.onSurfaceVariant)
                : null,
          ),
        ),
        title: Hero(
          tag: HeroTags.audiobookTitle + audiobookId + heroSuffix,
          child: Material(
            color: Colors.transparent,
            child: Text(
              audiobook.name,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        subtitle: Text(
          subtitleText,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: audiobook.duration != null
            ? Text(
                _formatDuration(audiobook.duration!),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
              )
            : null,
        onTap: () {
          // Update adaptive colors before navigation
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AudiobookDetailScreen(
                audiobook: audiobook,
                heroTagSuffix: 'search',
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _playTrack(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();

    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    // Use Music Assistant to play the track on the selected player
    await maProvider.playTrack(
      maProvider.selectedPlayer!.playerId,
      track,
    );
  }

  /// Play track radio on current player (1 tap)
  Future<void> _playRadio(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.playRadio(player.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.startingRadio(track.name)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToStartRadio(e.toString()))),
        );
      }
    }
  }

  /// Show player picker for Radio On (2 taps)
  void _showRadioOnMenu(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.hidePlayer();

    showPlayerPickerSheet(
      context: context,
      title: S.of(context)!.playOn,
      players: maProvider.availablePlayers,
      selectedPlayer: maProvider.selectedPlayer,
      onPlayerSelected: (player) async {
        try {
          maProvider.selectPlayer(player);
          await maProvider.playRadio(player.playerId, track);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context)!.startingRadioOnPlayer(track.name, player.name)),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context)!.failedToStartRadio(e.toString()))),
            );
          }
        }
      },
    ).whenComplete(() {
      GlobalPlayerOverlay.showPlayer();
    });
  }

  /// Add track to queue on current player (1 tap)
  Future<void> _addToQueue(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      await maProvider.addTrackToQueue(player.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  Future<void> _toggleTrackFavorite(Track track) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final currentFavorite = track.favorite ?? false;

    try {
      bool success;

      if (currentFavorite) {
        // Remove from favorites
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
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          provider: actualProvider,
          itemId: actualItemId,
        );
      }

      if (success && mounted) {
        // Update the track's favorite state in search results
        setState(() {
          final tracks = _searchResults['tracks'] as List<Track>?;
          if (tracks != null) {
            final index = tracks.indexWhere((t) => (t.uri ?? t.itemId) == (track.uri ?? track.itemId));
            if (index != -1) {
              // Create updated track with new favorite state
              final updatedTrack = Track.fromJson({
                ...tracks[index].toJson(),
                'favorite': !currentFavorite,
              });
              tracks[index] = updatedTrack;
            }
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update favorite: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
