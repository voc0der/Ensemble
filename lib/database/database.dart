import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// User profiles - auto-created from MA login or manual entry
class Profiles extends Table {
  /// MA username or manually entered name (primary key)
  TextColumn get username => text()();

  /// Display name from MA or same as username
  TextColumn get displayName => text().nullable()();

  /// How the profile was created: 'ma_auth' or 'manual'
  TextColumn get source => text().withDefault(const Constant('ma_auth'))();

  /// When the profile was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Whether this is the currently active profile
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {username};
}

/// Recently played items - scoped by profile
@TableIndex(name: 'idx_recently_played_profile', columns: {#profileUsername})
@TableIndex(name: 'idx_recently_played_profile_played', columns: {#profileUsername, #playedAt})
class RecentlyPlayed extends Table {
  /// Auto-incrementing ID
  IntColumn get id => integer().autoIncrement()();

  /// Profile this belongs to
  TextColumn get profileUsername => text().references(Profiles, #username)();

  /// Media item ID from Music Assistant
  TextColumn get mediaId => text()();

  /// Type: 'track', 'album', 'artist', 'playlist', 'audiobook'
  TextColumn get mediaType => text()();

  /// Display name of the item
  TextColumn get name => text()();

  /// Artist/author name (for display)
  TextColumn get artistName => text().nullable()();

  /// Image URL for the item
  TextColumn get imageUrl => text().nullable()();

  /// Additional metadata as JSON (e.g., album name for tracks)
  TextColumn get metadata => text().nullable()();

  /// When this was played
  DateTimeColumn get playedAt => dateTime()();
}

/// Cached library items for fast startup
@TableIndex(name: 'idx_library_cache_type', columns: {#itemType})
@TableIndex(name: 'idx_library_cache_type_deleted', columns: {#itemType, #isDeleted})
class LibraryCache extends Table {
  /// Composite key: provider + item_id
  TextColumn get cacheKey => text()();

  /// Type: 'album', 'artist', 'track', 'playlist', 'audiobook', 'audiobook_author'
  TextColumn get itemType => text()();

  /// The item ID from Music Assistant
  TextColumn get itemId => text()();

  /// Serialized item data as JSON
  TextColumn get data => text()();

  /// When this was last synced from MA
  DateTimeColumn get lastSynced => dateTime()();

  /// Whether this item was deleted on the server
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Provider instance IDs that provided this item (JSON array)
  /// Used for client-side filtering by source provider
  TextColumn get sourceProviders => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

/// Sync metadata - tracks last sync times per data type
class SyncMetadata extends Table {
  /// What was synced: 'albums', 'artists', 'audiobooks', etc.
  TextColumn get syncType => text()();

  /// When the last successful sync completed
  DateTimeColumn get lastSyncedAt => dateTime()();

  /// Number of items synced
  IntColumn get itemCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {syncType};
}

/// Persisted playback state - survives app restarts and disconnects
class PlaybackState extends Table {
  /// Always 'current' - single row table
  TextColumn get id => text().withDefault(const Constant('current'))();

  /// Selected player ID
  TextColumn get playerId => text().nullable()();

  /// Selected player name (for display if player unavailable)
  TextColumn get playerName => text().nullable()();

  /// Current track as JSON
  TextColumn get currentTrackJson => text().nullable()();

  /// Current position in seconds
  RealColumn get positionSeconds => real().withDefault(const Constant(0.0))();

  /// Whether playback was active
  BoolColumn get isPlaying => boolean().withDefault(const Constant(false))();

  /// When this state was saved
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached player list - for instant display on app resume
class CachedPlayers extends Table {
  /// Player ID from Music Assistant
  TextColumn get playerId => text()();

  /// Player data as JSON
  TextColumn get playerJson => text()();

  /// Current track for this player as JSON (for mini player display)
  TextColumn get currentTrackJson => text().nullable()();

  /// When this was last updated
  DateTimeColumn get lastUpdated => dateTime()();

  @override
  Set<Column> get primaryKey => {playerId};
}

/// Cached queue items for selected player
@TableIndex(name: 'idx_cached_queue_player', columns: {#playerId})
@TableIndex(name: 'idx_cached_queue_player_position', columns: {#playerId, #position})
class CachedQueue extends Table {
  /// Auto-incrementing ID for ordering
  IntColumn get id => integer().autoIncrement()();

  /// Player ID this queue belongs to
  TextColumn get playerId => text()();

  /// Queue item as JSON
  TextColumn get itemJson => text()();

  /// Position in queue
  IntColumn get position => integer()();
}

/// Cached home row data for instant display on startup
class HomeRowCache extends Table {
  /// Row type: 'recent_albums', 'discover_artists', 'discover_albums'
  TextColumn get rowType => text()();

  /// Serialized list of items as JSON array
  TextColumn get itemsJson => text()();

  /// When this was last updated
  DateTimeColumn get lastUpdated => dateTime()();

  @override
  Set<Column> get primaryKey => {rowType};
}

/// Search history for quick access to recent searches
class SearchHistory extends Table {
  /// Auto-incrementing ID
  IntColumn get id => integer().autoIncrement()();

  /// The search query
  TextColumn get query => text()();

  /// When the search was performed
  DateTimeColumn get searchedAt => dateTime()();
}

@DriftDatabase(tables: [Profiles, RecentlyPlayed, LibraryCache, SyncMetadata, PlaybackState, CachedPlayers, CachedQueue, HomeRowCache, SearchHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration from v1 to v2: Add playback state, cached players, cached queue tables
        if (from < 2) {
          await m.createTable(playbackState);
          await m.createTable(cachedPlayers);
          await m.createTable(cachedQueue);
        }
        // Migration from v2 to v3: Add home row cache table
        if (from < 3) {
          await m.createTable(homeRowCache);
        }
        // Migration from v3 to v4: Add search history table
        if (from < 4) {
          await m.createTable(searchHistory);
        }
        // Migration from v4 to v5: Add indexes for query performance
        if (from < 5) {
          // RecentlyPlayed indexes
          await customStatement('CREATE INDEX IF NOT EXISTS idx_recently_played_profile ON recently_played (profile_username)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_recently_played_profile_played ON recently_played (profile_username, played_at)');
          // LibraryCache indexes
          await customStatement('CREATE INDEX IF NOT EXISTS idx_library_cache_type ON library_cache (item_type)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_library_cache_type_deleted ON library_cache (item_type, is_deleted)');
          // CachedQueue indexes
          await customStatement('CREATE INDEX IF NOT EXISTS idx_cached_queue_player ON cached_queue (player_id)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_cached_queue_player_position ON cached_queue (player_id, position)');
        }
        // Migration from v5 to v6: Add source_providers column for client-side filtering
        if (from < 6) {
          await customStatement("ALTER TABLE library_cache ADD COLUMN source_providers TEXT NOT NULL DEFAULT '[]'");
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'ensemble_db');
  }

  // ============================================
  // Profile Operations
  // ============================================

  /// Get the currently active profile
  Future<Profile?> getActiveProfile() async {
    return (select(profiles)..where((p) => p.isActive.equals(true)))
        .getSingleOrNull();
  }

  /// Get a profile by username
  Future<Profile?> getProfile(String username) async {
    return (select(profiles)..where((p) => p.username.equals(username)))
        .getSingleOrNull();
  }

  /// Create or update a profile and set it as active
  Future<Profile> setActiveProfile({
    required String username,
    String? displayName,
    required String source,
  }) async {
    return transaction(() async {
      // Deactivate all profiles
      await (update(profiles)..where((p) => p.isActive.equals(true)))
          .write(const ProfilesCompanion(isActive: Value(false)));

      // Check if profile exists
      final existing = await getProfile(username);

      if (existing != null) {
        // Update and activate existing profile
        await (update(profiles)..where((p) => p.username.equals(username)))
            .write(ProfilesCompanion(
              displayName: Value(displayName ?? existing.displayName),
              isActive: const Value(true),
            ));
      } else {
        // Create new profile
        await into(profiles).insert(ProfilesCompanion.insert(
          username: username,
          displayName: Value(displayName),
          source: Value(source),
          isActive: const Value(true),
        ));
      }

      return (await getProfile(username))!;
    });
  }

  /// Get all profiles
  Future<List<Profile>> getAllProfiles() async {
    return select(profiles).get();
  }

  // ============================================
  // Recently Played Operations
  // ============================================

  /// Add an item to recently played for the active profile
  Future<void> addRecentlyPlayed({
    required String mediaId,
    required String mediaType,
    required String name,
    String? artistName,
    String? imageUrl,
    String? metadata,
  }) async {
    final profile = await getActiveProfile();
    if (profile == null) return;

    await transaction(() async {
      // Remove existing entry for this item (to move it to top)
      await (delete(recentlyPlayed)
        ..where((r) => r.profileUsername.equals(profile.username))
        ..where((r) => r.mediaId.equals(mediaId))
        ..where((r) => r.mediaType.equals(mediaType)))
        .go();

      // Add new entry
      await into(recentlyPlayed).insert(RecentlyPlayedCompanion.insert(
        profileUsername: profile.username,
        mediaId: mediaId,
        mediaType: mediaType,
        name: name,
        artistName: Value(artistName),
        imageUrl: Value(imageUrl),
        metadata: Value(metadata),
        playedAt: DateTime.now(),
      ));

      // Keep only last 50 items per profile
      final allItems = await (select(recentlyPlayed)
        ..where((r) => r.profileUsername.equals(profile.username))
        ..orderBy([(r) => OrderingTerm.desc(r.playedAt)]))
        .get();

      if (allItems.length > 50) {
        final toDelete = allItems.sublist(50);
        for (final item in toDelete) {
          await (delete(recentlyPlayed)..where((r) => r.id.equals(item.id))).go();
        }
      }
    });
  }

  /// Get recently played items for the active profile
  Future<List<RecentlyPlayedData>> getRecentlyPlayed({int limit = 20}) async {
    final profile = await getActiveProfile();
    if (profile == null) return [];

    return (select(recentlyPlayed)
      ..where((r) => r.profileUsername.equals(profile.username))
      ..orderBy([(r) => OrderingTerm.desc(r.playedAt)])
      ..limit(limit))
      .get();
  }

  /// Clear recently played for the active profile
  Future<void> clearRecentlyPlayed() async {
    final profile = await getActiveProfile();
    if (profile == null) return;

    await (delete(recentlyPlayed)
      ..where((r) => r.profileUsername.equals(profile.username)))
      .go();
  }

  // ============================================
  // Library Cache Operations
  // ============================================

  /// Cache a library item
  /// [sourceProvider] - the provider instance ID that provided this item (for filtering)
  Future<void> cacheItem({
    required String itemType,
    required String itemId,
    required String data,
    String? sourceProvider,
  }) async {
    final cacheKey = '${itemType}_$itemId';

    // If sourceProvider is specified, we need to merge with existing providers
    if (sourceProvider != null) {
      final existing = await getCachedItem(itemType, itemId);
      List<String> providers = [];
      if (existing != null) {
        try {
          final existingProviders = existing.sourceProviders;
          if (existingProviders.isNotEmpty && existingProviders != '[]') {
            providers = List<String>.from(
              (await Future.value(existingProviders))
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .replaceAll('"', '')
                  .split(',')
                  .where((s) => s.trim().isNotEmpty)
                  .map((s) => s.trim()),
            );
          }
        } catch (_) {}
      }
      if (!providers.contains(sourceProvider)) {
        providers.add(sourceProvider);
      }
      final sourceProvidersJson = '[${providers.map((p) => '"$p"').join(',')}]';

      await into(libraryCache).insertOnConflictUpdate(LibraryCacheCompanion.insert(
        cacheKey: cacheKey,
        itemType: itemType,
        itemId: itemId,
        data: data,
        lastSynced: DateTime.now(),
        sourceProviders: Value(sourceProvidersJson),
      ));
    } else {
      await into(libraryCache).insertOnConflictUpdate(LibraryCacheCompanion.insert(
        cacheKey: cacheKey,
        itemType: itemType,
        itemId: itemId,
        data: data,
        lastSynced: DateTime.now(),
      ));
    }
  }

  /// Get cached items by type
  Future<List<LibraryCacheData>> getCachedItems(String itemType) async {
    return (select(libraryCache)
      ..where((c) => c.itemType.equals(itemType))
      ..where((c) => c.isDeleted.equals(false)))
      .get();
  }

  /// Get a single cached item
  Future<LibraryCacheData?> getCachedItem(String itemType, String itemId) async {
    final cacheKey = '${itemType}_$itemId';
    return (select(libraryCache)..where((c) => c.cacheKey.equals(cacheKey)))
        .getSingleOrNull();
  }

  /// Mark items as deleted (soft delete)
  Future<void> markItemsDeleted(String itemType, List<String> itemIds) async {
    for (final itemId in itemIds) {
      final cacheKey = '${itemType}_$itemId';
      await (update(libraryCache)..where((c) => c.cacheKey.equals(cacheKey)))
          .write(const LibraryCacheCompanion(isDeleted: Value(true)));
    }
  }

  /// Clear all cached items of a type
  Future<void> clearCache(String itemType) async {
    await (delete(libraryCache)..where((c) => c.itemType.equals(itemType))).go();
  }

  /// Clear entire cache
  Future<void> clearAllCache() async {
    await delete(libraryCache).go();
  }

  // ============================================
  // Sync Metadata Operations
  // ============================================

  /// Update sync metadata for a type
  Future<void> updateSyncMetadata(String syncType, int itemCount) async {
    await into(syncMetadata).insertOnConflictUpdate(SyncMetadataCompanion.insert(
      syncType: syncType,
      lastSyncedAt: DateTime.now(),
      itemCount: Value(itemCount),
    ));
  }

  /// Get last sync time for a type
  Future<DateTime?> getLastSyncTime(String syncType) async {
    final meta = await (select(syncMetadata)
      ..where((s) => s.syncType.equals(syncType)))
      .getSingleOrNull();
    return meta?.lastSyncedAt;
  }

  /// Check if sync is needed (older than duration)
  Future<bool> needsSync(String syncType, Duration maxAge) async {
    final lastSync = await getLastSyncTime(syncType);
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > maxAge;
  }

  // ============================================
  // Playback State Operations
  // ============================================

  /// Save current playback state
  Future<void> savePlaybackState({
    String? playerId,
    String? playerName,
    String? currentTrackJson,
    double positionSeconds = 0.0,
    bool isPlaying = false,
  }) async {
    await into(playbackState).insertOnConflictUpdate(PlaybackStateCompanion.insert(
      id: const Value('current'),
      playerId: Value(playerId),
      playerName: Value(playerName),
      currentTrackJson: Value(currentTrackJson),
      positionSeconds: Value(positionSeconds),
      isPlaying: Value(isPlaying),
      savedAt: DateTime.now(),
    ));
  }

  /// Get saved playback state
  Future<PlaybackStateData?> getPlaybackState() async {
    return (select(playbackState)..where((p) => p.id.equals('current')))
        .getSingleOrNull();
  }

  /// Clear playback state
  Future<void> clearPlaybackState() async {
    await delete(playbackState).go();
  }

  // ============================================
  // Cached Players Operations
  // ============================================

  /// Cache a player with its current track
  Future<void> cachePlayer({
    required String playerId,
    required String playerJson,
    String? currentTrackJson,
  }) async {
    await into(cachedPlayers).insertOnConflictUpdate(CachedPlayersCompanion.insert(
      playerId: playerId,
      playerJson: playerJson,
      currentTrackJson: Value(currentTrackJson),
      lastUpdated: DateTime.now(),
    ));
  }

  /// Cache multiple players at once
  Future<void> cachePlayers(List<Map<String, dynamic>> players) async {
    await transaction(() async {
      for (final player in players) {
        await into(cachedPlayers).insertOnConflictUpdate(CachedPlayersCompanion.insert(
          playerId: player['playerId'] as String,
          playerJson: player['playerJson'] as String,
          currentTrackJson: Value(player['currentTrackJson'] as String?),
          lastUpdated: DateTime.now(),
        ));
      }
    });
  }

  /// Get all cached players
  Future<List<CachedPlayer>> getCachedPlayers() async {
    return (select(cachedPlayers)
      ..orderBy([(p) => OrderingTerm.desc(p.lastUpdated)]))
      .get();
  }

  /// Get a specific cached player
  Future<CachedPlayer?> getCachedPlayer(String playerId) async {
    return (select(cachedPlayers)..where((p) => p.playerId.equals(playerId)))
        .getSingleOrNull();
  }

  /// Update cached track for a player
  Future<void> updateCachedPlayerTrack(String playerId, String? trackJson) async {
    await (update(cachedPlayers)..where((p) => p.playerId.equals(playerId)))
        .write(CachedPlayersCompanion(
          currentTrackJson: Value(trackJson),
          lastUpdated: Value(DateTime.now()),
        ));
  }

  /// Clear all cached players
  Future<void> clearCachedPlayers() async {
    await delete(cachedPlayers).go();
  }

  // ============================================
  // Cached Queue Operations
  // ============================================

  /// Save queue for a player
  Future<void> saveQueue(String playerId, List<String> itemJsonList) async {
    await transaction(() async {
      // Clear existing queue for this player
      await (delete(cachedQueue)..where((q) => q.playerId.equals(playerId))).go();

      // Insert new queue items
      for (var i = 0; i < itemJsonList.length; i++) {
        await into(cachedQueue).insert(CachedQueueCompanion.insert(
          playerId: playerId,
          itemJson: itemJsonList[i],
          position: i,
        ));
      }
    });
  }

  /// Get cached queue for a player
  Future<List<CachedQueueData>> getCachedQueue(String playerId) async {
    return (select(cachedQueue)
      ..where((q) => q.playerId.equals(playerId))
      ..orderBy([(q) => OrderingTerm.asc(q.position)]))
      .get();
  }

  /// Clear queue for a player
  Future<void> clearCachedQueue(String playerId) async {
    await (delete(cachedQueue)..where((q) => q.playerId.equals(playerId))).go();
  }

  /// Clear all cached queues
  Future<void> clearAllCachedQueues() async {
    await delete(cachedQueue).go();
  }

  // ============================================
  // Home Row Cache Operations
  // ============================================

  /// Save home row data
  Future<void> saveHomeRowCache(String rowType, String itemsJson) async {
    await into(homeRowCache).insertOnConflictUpdate(
      HomeRowCacheCompanion(
        rowType: Value(rowType),
        itemsJson: Value(itemsJson),
        lastUpdated: Value(DateTime.now()),
      ),
    );
  }

  /// Get cached home row data
  Future<HomeRowCacheData?> getHomeRowCache(String rowType) async {
    return (select(homeRowCache)..where((h) => h.rowType.equals(rowType)))
        .getSingleOrNull();
  }

  /// Clear all home row cache
  Future<void> clearHomeRowCache() async {
    await delete(homeRowCache).go();
  }

  // ============================================
  // Search History Operations
  // ============================================

  /// Save a search query to history (deduplicates and limits to 10)
  Future<void> saveSearchQuery(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    await transaction(() async {
      // Delete existing entry with same query (case-insensitive)
      await (delete(searchHistory)
            ..where((s) => s.query.lower().equals(trimmedQuery.toLowerCase())))
          .go();

      // Insert the new search
      await into(searchHistory).insert(SearchHistoryCompanion.insert(
        query: trimmedQuery,
        searchedAt: DateTime.now(),
      ));

      // Keep only the 10 most recent searches
      final allSearches = await (select(searchHistory)
            ..orderBy([(s) => OrderingTerm.desc(s.searchedAt)]))
          .get();

      if (allSearches.length > 10) {
        final toDelete = allSearches.skip(10).map((s) => s.id).toList();
        await (delete(searchHistory)..where((s) => s.id.isIn(toDelete))).go();
      }
    });
  }

  /// Get recent search queries (up to 10, most recent first)
  Future<List<String>> getRecentSearches() async {
    final searches = await (select(searchHistory)
          ..orderBy([(s) => OrderingTerm.desc(s.searchedAt)])
          ..limit(10))
        .get();
    return searches.map((s) => s.query).toList();
  }

  /// Clear all search history
  Future<void> clearSearchHistory() async {
    await delete(searchHistory).go();
  }
}
