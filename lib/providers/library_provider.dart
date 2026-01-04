import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../services/music_assistant_api.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/cache_service.dart';
import '../constants/timings.dart';

/// Provider for managing library data (artists, albums, tracks, playlists)
class LibraryProvider with ChangeNotifier {
  final DebugLogger _logger = DebugLogger();
  final CacheService _cacheService;

  MusicAssistantAPI? _api;

  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;
  String? _error;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // Getters
  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  LibraryProvider(this._cacheService);

  /// Initialize with API reference after connection
  void initialize(MusicAssistantAPI api) {
    _api = api;
  }

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {
      'artists': [],
      'albums': [],
      'tracks': [],
    };
  }

  // ============================================================================
  // HOME SCREEN DATA
  // ============================================================================

  /// Get recently played albums with caching
  Future<List<Album>> getRecentAlbumsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isRecentAlbumsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached recent albums');
      return _cacheService.getCachedRecentAlbums()!;
    }

    if (_api == null) return _cacheService.getCachedRecentAlbums() ?? [];

    try {
      _logger.log('🔄 Fetching fresh recent albums...');
      final albums = await _api!.getRecentAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedRecentAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch recent albums: $e');
      return _cacheService.getCachedRecentAlbums() ?? [];
    }
  }

  /// Get discover artists (random) with caching
  Future<List<Artist>> getDiscoverArtistsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverArtistsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover artists');
      return _cacheService.getCachedDiscoverArtists()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverArtists() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover artists...');
      final artists = await _api!.getRandomArtists(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedDiscoverArtists(artists);
      return artists;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover artists: $e');
      return _cacheService.getCachedDiscoverArtists() ?? [];
    }
  }

  /// Get discover albums (random) with caching
  Future<List<Album>> getDiscoverAlbumsWithCache({bool forceRefresh = false}) async {
    if (_cacheService.isDiscoverAlbumsCacheValid(forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached discover albums');
      return _cacheService.getCachedDiscoverAlbums()!;
    }

    if (_api == null) return _cacheService.getCachedDiscoverAlbums() ?? [];

    try {
      _logger.log('🔄 Fetching fresh discover albums...');
      final albums = await _api!.getRandomAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedDiscoverAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch discover albums: $e');
      return _cacheService.getCachedDiscoverAlbums() ?? [];
    }
  }

  /// Invalidate home screen cache (call on pull-to-refresh)
  void invalidateHomeCache() {
    _cacheService.invalidateHomeCache();
  }

  // ============================================================================
  // LIBRARY DATA
  // ============================================================================

  Future<void> loadLibrary() async {
    if (_api == null) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final results = await Future.wait([
        _api!.getArtists(limit: LibraryConstants.maxLibraryItems, albumArtistsOnly: false),
        _api!.getAlbums(limit: LibraryConstants.maxLibraryItems),
        _api!.getTracks(limit: LibraryConstants.maxLibraryItems),
      ]);

      _artists = results[0] as List<Artist>;
      _albums = results[1] as List<Album>;
      _tracks = results[2] as List<Track>;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (_api == null) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        albumArtistsOnly: false, // Show ALL library artists, not just those with albums
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load artists');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbums({int? limit, int? offset, String? search, String? artistId}) async {
    if (_api == null) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _albums = await _api!.getAlbums(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
        artistId: artistId,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load albums');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================================================================
  // DETAIL SCREEN DATA
  // ============================================================================

  /// Get album tracks with caching
  Future<List<Track>> getAlbumTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isAlbumTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached album tracks for $cacheKey');
      return _cacheService.getCachedAlbumTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh album tracks for $cacheKey...');
      final tracks = await _api!.getAlbumTracks(provider, itemId);
      _cacheService.setCachedAlbumTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch album tracks: $e');
      return _cacheService.getCachedAlbumTracks(cacheKey) ?? [];
    }
  }

  /// Get playlist tracks with caching
  Future<List<Track>> getPlaylistTracksWithCache(String provider, String itemId, {bool forceRefresh = false}) async {
    final cacheKey = '${provider}_$itemId';

    if (_cacheService.isPlaylistTracksCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached playlist tracks for $cacheKey');
      return _cacheService.getCachedPlaylistTracks(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching fresh playlist tracks for $cacheKey...');
      final tracks = await _api!.getPlaylistTracks(provider, itemId);
      _cacheService.setCachedPlaylistTracks(cacheKey, tracks);
      return tracks;
    } catch (e) {
      _logger.log('❌ Failed to fetch playlist tracks: $e');
      return _cacheService.getCachedPlaylistTracks(cacheKey) ?? [];
    }
  }

  /// Get artist albums with caching
  Future<List<Album>> getArtistAlbumsWithCache(String artistName, {bool forceRefresh = false}) async {
    final cacheKey = artistName.toLowerCase();

    if (_cacheService.isArtistAlbumsCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached artist albums for "$artistName"');
      return _cacheService.getCachedArtistAlbums(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching albums for artist "$artistName"...');

      final libraryAlbums = await _api!.getAlbums();
      final artistAlbums = libraryAlbums.where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final searchResults = await _api!.search(artistName);
      final searchAlbums = searchResults['albums'] as List<MediaItem>? ?? [];
      final providerAlbums = searchAlbums.whereType<Album>().where((album) {
        final albumArtists = album.artists;
        if (albumArtists == null || albumArtists.isEmpty) return false;
        return albumArtists.any((a) => a.name.toLowerCase() == artistName.toLowerCase());
      }).toList();

      final allAlbums = <Album>[];
      final seenNames = <String>{};

      for (final album in [...artistAlbums, ...providerAlbums]) {
        final key = album.name.toLowerCase();
        if (!seenNames.contains(key)) {
          seenNames.add(key);
          allAlbums.add(album);
        }
      }

      _cacheService.setCachedArtistAlbums(cacheKey, allAlbums);
      return allAlbums;
    } catch (e) {
      _logger.log('❌ Failed to fetch artist albums: $e');
      return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];
    }
  }

  /// Invalidate album tracks cache
  void invalidateAlbumTracksCache(String albumId) {
    _cacheService.invalidateAlbumTracksCache(albumId);
  }

  /// Invalidate playlist tracks cache
  void invalidatePlaylistTracksCache(String playlistId) {
    _cacheService.invalidatePlaylistTracksCache(playlistId);
  }

  // ============================================================================
  // SEARCH
  // ============================================================================

  /// Search with caching
  Future<Map<String, List<MediaItem>>> searchWithCache(String query, {bool forceRefresh = false}) async {
    final cacheKey = query.toLowerCase().trim();
    if (cacheKey.isEmpty) return {'artists': [], 'albums': [], 'tracks': []};

    if (_cacheService.isSearchCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached search results for "$query"');
      return _cacheService.getCachedSearchResults(cacheKey)!;
    }

    if (_api == null) {
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      _logger.log('🔄 Searching for "$query"...');
      final results = await _api!.search(query);

      final cachedResults = <String, List<MediaItem>>{
        'artists': results['artists'] ?? [],
        'albums': results['albums'] ?? [],
        'tracks': results['tracks'] ?? [],
      };

      _cacheService.setCachedSearchResults(cacheKey, cachedResults);
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (_api == null) return {'artists': [], 'albums': [], 'tracks': []};

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (_api == null) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  void clearState() {
    _artists = [];
    _albums = [];
    _tracks = [];
    _isLoading = false;
    _error = null;
    clearSearchState();
    notifyListeners();
  }
}
