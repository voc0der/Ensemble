import 'dart:convert';
import '../database/database.dart';
import 'debug_logger.dart';

/// Singleton service for database access throughout the app
class DatabaseService {
  static DatabaseService? _instance;
  static AppDatabase? _database;
  static final _logger = DebugLogger();

  DatabaseService._();

  /// Get the singleton instance
  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// Get the database instance
  AppDatabase get db {
    if (_database == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }

  /// Check if database is initialized
  bool get isInitialized => _database != null;

  /// Initialize the database
  Future<void> initialize() async {
    if (_database != null) {
      _logger.log('Database already initialized');
      return;
    }

    _logger.log('Initializing database...');
    _database = AppDatabase();
    _logger.log('Database initialized successfully');
  }

  /// Close the database (for cleanup)
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _logger.log('Database closed');
  }

  // ============================================
  // Profile Convenience Methods
  // ============================================

  /// Get the currently active profile
  Future<Profile?> getActiveProfile() => db.getActiveProfile();

  /// Set the active profile (creates if doesn't exist)
  Future<Profile> setActiveProfile({
    required String username,
    String? displayName,
    required String source,
  }) {
    _logger.log('Setting active profile: $username (source: $source)');
    return db.setActiveProfile(
      username: username,
      displayName: displayName,
      source: source,
    );
  }

  /// Get all profiles
  Future<List<Profile>> getAllProfiles() => db.getAllProfiles();

  // ============================================
  // Recently Played Convenience Methods
  // ============================================

  /// Add an item to recently played
  Future<void> addRecentlyPlayed({
    required String mediaId,
    required String mediaType,
    required String name,
    String? artistName,
    String? imageUrl,
    Map<String, dynamic>? metadata,
  }) {
    _logger.log('Adding to recently played: $name ($mediaType)');
    return db.addRecentlyPlayed(
      mediaId: mediaId,
      mediaType: mediaType,
      name: name,
      artistName: artistName,
      imageUrl: imageUrl,
      metadata: metadata != null ? jsonEncode(metadata) : null,
    );
  }

  /// Get recently played items
  Future<List<RecentlyPlayedData>> getRecentlyPlayed({int limit = 20}) {
    return db.getRecentlyPlayed(limit: limit);
  }

  /// Clear recently played for current profile
  Future<void> clearRecentlyPlayed() => db.clearRecentlyPlayed();

  // ============================================
  // Library Cache Convenience Methods
  // ============================================

  /// Cache an item with JSON serialization
  /// [sourceProvider] - optional provider instance ID that provided this item (for client-side filtering)
  Future<void> cacheItem<T>({
    required String itemType,
    required String itemId,
    required Map<String, dynamic> data,
    String? sourceProvider,
  }) {
    return db.cacheItem(
      itemType: itemType,
      itemId: itemId,
      data: jsonEncode(data),
      sourceProvider: sourceProvider,
    );
  }

  /// Get cached items with JSON deserialization
  Future<List<Map<String, dynamic>>> getCachedItems(String itemType) async {
    final items = await db.getCachedItems(itemType);
    return items.map((item) {
      try {
        return jsonDecode(item.data) as Map<String, dynamic>;
      } catch (e) {
        _logger.log('Error decoding cached item: $e');
        return <String, dynamic>{};
      }
    }).where((item) => item.isNotEmpty).toList();
  }

  /// Get cached items with source provider info for client-side filtering
  /// Returns list of (data, sourceProviders) tuples
  Future<List<(Map<String, dynamic>, List<String>)>> getCachedItemsWithProviders(String itemType) async {
    final items = await db.getCachedItems(itemType);
    return items.map((item) {
      try {
        final data = jsonDecode(item.data) as Map<String, dynamic>;
        List<String> providers = [];
        try {
          if (item.sourceProviders.isNotEmpty && item.sourceProviders != '[]') {
            providers = List<String>.from(
              jsonDecode(item.sourceProviders) as List,
            );
          }
        } catch (_) {}
        return (data, providers);
      } catch (e) {
        _logger.log('Error decoding cached item: $e');
        return (<String, dynamic>{}, <String>[]);
      }
    }).where((item) => item.$1.isNotEmpty).toList();
  }

  /// Get a single cached item
  Future<Map<String, dynamic>?> getCachedItem(String itemType, String itemId) async {
    final item = await db.getCachedItem(itemType, itemId);
    if (item == null) return null;
    try {
      return jsonDecode(item.data) as Map<String, dynamic>;
    } catch (e) {
      _logger.log('Error decoding cached item: $e');
      return null;
    }
  }

  /// Check if sync is needed
  Future<bool> needsSync(String syncType, {Duration maxAge = const Duration(minutes: 5)}) {
    return db.needsSync(syncType, maxAge);
  }

  /// Update sync timestamp
  Future<void> updateSyncMetadata(String syncType, int itemCount) {
    return db.updateSyncMetadata(syncType, itemCount);
  }

  /// Clear all cached data (useful for logout)
  Future<void> clearAllCache() => db.clearAllCache();

  /// Clear cached items of a specific type (e.g., 'album', 'artist')
  /// Used before re-syncing to remove stale items
  Future<void> clearCacheForType(String itemType) => db.clearCache(itemType);

  /// Mark a specific cached item as deleted
  /// Used when removing items from library for immediate database update
  Future<void> markCachedItemDeleted(String itemType, String itemId) {
    return db.markItemsDeleted(itemType, [itemId]);
  }

  // ============================================
  // Player Cache Convenience Methods
  // ============================================

  /// Save playback state for instant resume
  Future<void> savePlaybackState({
    String? playerId,
    String? playerName,
    String? currentTrackJson,
    double positionSeconds = 0.0,
    bool isPlaying = false,
  }) {
    return db.savePlaybackState(
      playerId: playerId,
      playerName: playerName,
      currentTrackJson: currentTrackJson,
      positionSeconds: positionSeconds,
      isPlaying: isPlaying,
    );
  }

  /// Get saved playback state
  Future<PlaybackStateData?> getPlaybackState() => db.getPlaybackState();

  /// Cache a player with optional track info
  Future<void> cachePlayer({
    required String playerId,
    required String playerJson,
    String? currentTrackJson,
  }) {
    return db.cachePlayer(
      playerId: playerId,
      playerJson: playerJson,
      currentTrackJson: currentTrackJson,
    );
  }

  /// Cache multiple players at once
  Future<void> cachePlayers(List<Map<String, dynamic>> players) {
    return db.cachePlayers(players);
  }

  /// Get all cached players
  Future<List<CachedPlayer>> getCachedPlayers() => db.getCachedPlayers();

  /// Update cached track for a player
  Future<void> updateCachedPlayerTrack(String playerId, String? trackJson) {
    return db.updateCachedPlayerTrack(playerId, trackJson);
  }

  /// Clear all cached players
  Future<void> clearCachedPlayers() => db.clearCachedPlayers();

  /// Save queue for a player
  Future<void> saveQueue(String playerId, List<String> itemJsonList) {
    return db.saveQueue(playerId, itemJsonList);
  }

  /// Get cached queue for a player
  Future<List<CachedQueueData>> getCachedQueue(String playerId) {
    return db.getCachedQueue(playerId);
  }

  /// Clear queue for a player
  Future<void> clearCachedQueue(String playerId) => db.clearCachedQueue(playerId);

  // ============================================
  // Home Row Cache Convenience Methods
  // ============================================

  /// Save home row data (recent albums, discover artists, etc.)
  Future<void> saveHomeRowCache(String rowType, String itemsJson) {
    return db.saveHomeRowCache(rowType, itemsJson);
  }

  /// Get cached home row data
  Future<HomeRowCacheData?> getHomeRowCache(String rowType) {
    return db.getHomeRowCache(rowType);
  }

  /// Clear all home row cache
  Future<void> clearHomeRowCache() => db.clearHomeRowCache();

  // ============================================
  // Search History Convenience Methods
  // ============================================

  /// Save a search query to history
  Future<void> saveSearchQuery(String query) => db.saveSearchQuery(query);

  /// Get recent search queries (up to 10)
  Future<List<String>> getRecentSearches() => db.getRecentSearches();

  /// Clear all search history
  Future<void> clearSearchHistory() => db.clearSearchHistory();

  // ============================================
  // Cast-to-Sendspin Mapping Methods
  // ============================================

  static const String _sendspinMappingType = 'cast_sendspin_mapping';

  /// Save a Cast UUID to Sendspin ID mapping
  Future<void> saveCastToSendspinMapping(String castId, String sendspinId) {
    _logger.log('💾 Persisting Cast->Sendspin mapping: $castId -> $sendspinId');
    return db.cacheItem(
      itemType: _sendspinMappingType,
      itemId: castId,
      data: jsonEncode({'sendspinId': sendspinId}),
    );
  }

  /// Get persisted Sendspin ID for a Cast UUID
  Future<String?> getSendspinIdForCast(String castId) async {
    final item = await db.getCachedItem(_sendspinMappingType, castId);
    if (item == null) return null;
    try {
      final data = jsonDecode(item.data) as Map<String, dynamic>;
      return data['sendspinId'] as String?;
    } catch (e) {
      _logger.log('Error decoding Sendspin mapping: $e');
      return null;
    }
  }

  /// Load all persisted Cast-to-Sendspin mappings
  Future<Map<String, String>> getAllCastToSendspinMappings() async {
    final items = await db.getCachedItems(_sendspinMappingType);
    final mappings = <String, String>{};
    for (final item in items) {
      try {
        final data = jsonDecode(item.data) as Map<String, dynamic>;
        final sendspinId = data['sendspinId'] as String?;
        if (sendspinId != null) {
          // The itemId is the Cast UUID
          mappings[item.itemId] = sendspinId;
        }
      } catch (e) {
        _logger.log('Error decoding Sendspin mapping: $e');
      }
    }
    _logger.log('📦 Loaded ${mappings.length} Cast->Sendspin mappings from database');
    return mappings;
  }
}
