import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import 'database_service.dart';
import 'debug_logger.dart';
import 'music_assistant_api.dart';

/// Sync status for UI indicators
enum SyncStatus {
  idle,
  syncing,
  completed,
  error,
}

/// Service for background library synchronization
/// Loads from database cache first, then syncs from MA API in background
class SyncService with ChangeNotifier {
  static SyncService? _instance;
  static final _logger = DebugLogger();

  SyncService._();

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  DatabaseService get _db => DatabaseService.instance;

  // Sync state
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

  // Cached data (loaded from DB, updated after sync)
  List<Album> _cachedAlbums = [];
  List<Artist> _cachedArtists = [];

  // Getters
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isSyncing => _isSyncing;
  List<Album> get cachedAlbums => _cachedAlbums;
  List<Artist> get cachedArtists => _cachedArtists;
  bool get hasCache => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty;

  /// Load library data from database cache (instant)
  /// Call this on app startup for immediate data
  Future<void> loadFromCache() async {
    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping cache load');
      return;
    }

    try {
      _logger.log('📦 Loading library from database cache...');

      // Load albums from cache
      final albumData = await _db.getCachedItems('album');
      _cachedAlbums = albumData.map((data) {
        try {
          return Album.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached album: $e');
          return null;
        }
      }).whereType<Album>().toList();

      // Load artists from cache
      final artistData = await _db.getCachedItems('artist');
      _cachedArtists = artistData.map((data) {
        try {
          return Artist.fromJson(data);
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached artist: $e');
          return null;
        }
      }).whereType<Artist>().toList();

      _logger.log('📦 Loaded ${_cachedAlbums.length} albums, ${_cachedArtists.length} artists from cache');
      notifyListeners();
    } catch (e) {
      _logger.log('❌ Failed to load from cache: $e');
    }
  }

  /// Sync library data from MA API in background
  /// Updates database cache and notifies listeners when complete
  Future<void> syncFromApi(MusicAssistantAPI api, {bool force = false}) async {
    if (_isSyncing) {
      _logger.log('🔄 Sync already in progress, skipping');
      return;
    }

    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping sync');
      return;
    }

    // Check if sync is needed (default: every 5 minutes)
    if (!force) {
      final albumsNeedSync = await _db.needsSync('albums', maxAge: const Duration(minutes: 5));
      final artistsNeedSync = await _db.needsSync('artists', maxAge: const Duration(minutes: 5));

      if (!albumsNeedSync && !artistsNeedSync) {
        _logger.log('✅ Cache is fresh, skipping sync');
        return;
      }
    }

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      _logger.log('🔄 Starting background library sync...');

      // Fetch fresh data from MA API
      final results = await Future.wait([
        api.getAlbums(limit: 1000),
        api.getArtists(limit: 1000),
      ]);

      final albums = results[0] as List<Album>;
      final artists = results[1] as List<Artist>;

      _logger.log('📥 Fetched ${albums.length} albums, ${artists.length} artists from MA');

      // Save to database cache
      await _saveAlbumsToCache(albums);
      await _saveArtistsToCache(artists);

      // Update sync metadata
      await _db.updateSyncMetadata('albums', albums.length);
      await _db.updateSyncMetadata('artists', artists.length);

      // Update in-memory cache
      _cachedAlbums = albums;
      _cachedArtists = artists;
      _lastSyncTime = DateTime.now();
      _status = SyncStatus.completed;

      _logger.log('✅ Library sync complete');
    } catch (e) {
      _logger.log('❌ Library sync failed: $e');
      _status = SyncStatus.error;
      _lastError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Save albums to database cache
  Future<void> _saveAlbumsToCache(List<Album> albums) async {
    for (final album in albums) {
      try {
        await _db.cacheItem(
          itemType: 'album',
          itemId: album.itemId,
          data: album.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache album ${album.name}: $e');
      }
    }
    _logger.log('💾 Saved ${albums.length} albums to cache');
  }

  /// Save artists to database cache
  Future<void> _saveArtistsToCache(List<Artist> artists) async {
    for (final artist in artists) {
      try {
        await _db.cacheItem(
          itemType: 'artist',
          itemId: artist.itemId,
          data: artist.toJson(),
        );
      } catch (e) {
        _logger.log('⚠️ Failed to cache artist ${artist.name}: $e');
      }
    }
    _logger.log('💾 Saved ${artists.length} artists to cache');
  }

  /// Force a fresh sync (for pull-to-refresh)
  Future<void> forceSync(MusicAssistantAPI api) async {
    await syncFromApi(api, force: true);
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    if (!_db.isInitialized) return;

    await _db.clearAllCache();
    _cachedAlbums = [];
    _cachedArtists = [];
    _lastSyncTime = null;
    _status = SyncStatus.idle;
    notifyListeners();
    _logger.log('🗑️ Library cache cleared');
  }

  /// Get albums (from cache or empty if not loaded)
  List<Album> getAlbums() => _cachedAlbums;

  /// Get artists (from cache or empty if not loaded)
  List<Artist> getArtists() => _cachedArtists;

  /// Check if we have data available (from cache or sync)
  bool get hasData => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty;
}
