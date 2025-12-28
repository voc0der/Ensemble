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
import '../widgets/common/empty_state.dart';
import '../widgets/common/disconnected_state.dart';
import '../widgets/artist_avatar.dart';
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
  Timer? _debounceTimer;
  Map<String, List<MediaItem>> _searchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
    'playlists': [],
    'audiobooks': [],
  };
  bool _isSearching = false;
  bool _hasSearched = false;
  String _activeFilter = 'all'; // 'all', 'artists', 'albums', 'tracks', 'playlists', 'audiobooks'
  String? _searchError;
  List<String> _recentSearches = [];
  bool _libraryOnly = false;
  String? _expandedTrackId; // Track ID for expanded quick actions

  @override
  void initState() {
    super.initState();
    // Don't auto-focus - let user tap to focus
    // This prevents keyboard popup bug when SearchScreen is in widget tree but not visible
    _loadRecentSearches();
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
    super.dispose();
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
        _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': []};
        _hasSearched = false;
        _searchError = null;
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
    final maProvider = context.watch<MusicAssistantProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          style: TextStyle(color: colorScheme.onSurface),
          cursorColor: colorScheme.primary,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: S.of(context)!.searchMusic,
            hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: colorScheme.onSurface.withOpacity(0.5)),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults = {'artists': [], 'albums': [], 'tracks': [], 'playlists': [], 'audiobooks': []};
                        _hasSearched = false;
                        _searchError = null;
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {}); // Update clear button visibility
            _onSearchChanged(value);
          },
          onSubmitted: (query) => _performSearch(query),
        ),
        actions: [
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
                // Re-search if there's a query
                if (_searchController.text.isNotEmpty) {
                  _performSearch(_searchController.text);
                }
              },
            ),
          ),
        ],
      ),
      body: !maProvider.isConnected
          ? DisconnectedState.simple(context)
          : _buildSearchContent(),
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

    return Column(
      children: [
        // Filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildFilterChip(S.of(context)!.all, 'all'),
              const SizedBox(width: 8),
              if (artists.isNotEmpty) ...[
                _buildFilterChip(S.of(context)!.artists, 'artists'),
                const SizedBox(width: 8),
              ],
              if (albums.isNotEmpty) ...[
                _buildFilterChip(S.of(context)!.albums, 'albums'),
                const SizedBox(width: 8),
              ],
              if (tracks.isNotEmpty) ...[
                _buildFilterChip(S.of(context)!.tracks, 'tracks'),
                const SizedBox(width: 8),
              ],
              if (playlists.isNotEmpty) ...[
                _buildFilterChip(S.of(context)!.playlists, 'playlists'),
                const SizedBox(width: 8),
              ],
              if (audiobooks.isNotEmpty) ...[
                _buildFilterChip(S.of(context)!.audiobooks, 'audiobooks'),
              ],
            ],
          ),
        ),

        // Results
        Expanded(
          child: Builder(
            builder: (context) {
              final listItems = _buildListItems(artists, albums, tracks, playlists, audiobooks);
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 8, 16, BottomSpacing.navBarOnly),
                cacheExtent: 500, // Prebuild items off-screen for smoother scrolling
                addAutomaticKeepAlives: false, // Tiles don't need individual keep-alive
                addRepaintBoundaries: false, // We add RepaintBoundary manually to tiles
                itemCount: listItems.length,
                itemBuilder: (context, index) {
                  final item = listItems[index];
                  final showTypeInSubtitle = _activeFilter == 'all';
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
              );
            },
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

  List<_ListItem> _buildListItems(
    List<MediaItem> artists,
    List<MediaItem> albums,
    List<MediaItem> tracks,
    List<MediaItem> playlists,
    List<MediaItem> audiobooks,
  ) {
    final items = <_ListItem>[];
    final query = _searchController.text;

    // For 'all' filter, create unified relevance-sorted list
    if (_activeFilter == 'all') {
      final scoredItems = <_ListItem>[];

      // Score and add all items
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

      // Smart cross-referencing: Add artists from matched tracks/albums
      // if the artist name matches the query but wasn't in direct results
      final crossRefArtists = _extractCrossReferencedArtists(
        query,
        artists.cast<Artist>(),
        albums.cast<Album>(),
        tracks.cast<Track>(),
      );
      for (final artist in crossRefArtists) {
        // Give cross-referenced artists a lower score (25) since they're indirect matches
        scoredItems.add(_ListItem.artist(artist, relevanceScore: 25));
      }

      // Sort by relevance score descending
      scoredItems.sort((a, b) => (b.relevanceScore ?? 0).compareTo(a.relevanceScore ?? 0));

      return scoredItems;
    }

    // For specific type filters, use sectioned view (no headers needed for single type)
    if (_activeFilter == 'artists' && artists.isNotEmpty) {
      for (final artist in artists) {
        items.add(_ListItem.artist(artist));
      }
    }

    if (_activeFilter == 'albums' && albums.isNotEmpty) {
      for (final album in albums) {
        items.add(_ListItem.album(album));
      }
    }

    if (_activeFilter == 'tracks' && tracks.isNotEmpty) {
      for (final track in tracks) {
        items.add(_ListItem.track(track));
      }
    }

    if (_activeFilter == 'playlists' && playlists.isNotEmpty) {
      for (final playlist in playlists) {
        items.add(_ListItem.playlist(playlist));
      }
    }

    if (_activeFilter == 'audiobooks' && audiobooks.isNotEmpty) {
      for (final audiobook in audiobooks) {
        items.add(_ListItem.audiobook(audiobook));
      }
    }

    return items;
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _activeFilter == value;
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (selected) {
        setState(() {
          _activeFilter = value;
        });
      },
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
      selectedColor: colorScheme.primaryContainer,
      side: BorderSide.none,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
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

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(artist.uri ?? artist.itemId),
      leading: ArtistAvatar(
        artist: artist,
        radius: 24,
        imageSize: 128,
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArtistDetailsScreen(
                artist: artist,
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

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(album.uri ?? album.itemId),
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
            ? Icon(Icons.album_rounded, color: colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(
        album.nameWithYear,
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlbumDetailsScreen(
                album: album,
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
                        // Radio button
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: FilledButton.tonal(
                            onPressed: () => _showRadioMenu(track),
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
                            onPressed: () => _showAddToQueueMenu(track),
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

    return RepaintBoundary(
      child: ListTile(
        key: ValueKey(audiobook.uri ?? audiobook.itemId),
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
              ? Icon(Icons.headphones_rounded, color: colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Text(
          audiobook.name,
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
        trailing: audiobook.duration != null
            ? Text(
                _formatDuration(audiobook.duration!),
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
              )
            : null,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AudiobookDetailScreen(
                audiobook: audiobook,
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

  void _showRadioMenu(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

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
            const SizedBox(height: 16),
            Text(
              S.of(context)!.playOn,
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          maProvider.selectPlayer(player);
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
      GlobalPlayerOverlay.showPlayer();
    });
  }

  void _showAddToQueueMenu(Track track) {
    final maProvider = context.read<MusicAssistantProvider>();
    final players = maProvider.availablePlayers;

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
            const SizedBox(height: 16),
            Text(
              S.of(context)!.addToQueueOn,
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(player.name),
                      onTap: () async {
                        Navigator.pop(context);
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
      GlobalPlayerOverlay.showPlayer();
    });
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
