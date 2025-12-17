import 'dart:convert';
import 'database_service.dart';
import 'debug_logger.dart';
import '../database/database.dart';
import '../models/media_item.dart';

/// Service for tracking recently played items locally, per-profile
/// This supplements MA's server-side tracking with instant local data
class RecentlyPlayedService {
  static RecentlyPlayedService? _instance;
  static final _logger = DebugLogger();

  RecentlyPlayedService._();

  /// Get the singleton instance
  static RecentlyPlayedService get instance {
    _instance ??= RecentlyPlayedService._();
    return _instance!;
  }

  DatabaseService get _db => DatabaseService.instance;

  /// Record an album being played
  Future<void> recordAlbumPlayed(Album album) async {
    if (!_db.isInitialized) return;

    try {
      await _db.addRecentlyPlayed(
        mediaId: album.itemId,
        mediaType: 'album',
        name: album.name,
        artistName: album.artistsString,
        imageUrl: album.imageUrl,
        metadata: {
          'provider': album.provider,
          'uri': album.uri,
        },
      );
      _logger.log('📝 Recorded album play: ${album.name}');
    } catch (e) {
      _logger.log('⚠️ Failed to record album play: $e');
    }
  }

  /// Record an artist being played (e.g., artist radio)
  Future<void> recordArtistPlayed(Artist artist) async {
    if (!_db.isInitialized) return;

    try {
      await _db.addRecentlyPlayed(
        mediaId: artist.itemId,
        mediaType: 'artist',
        name: artist.name,
        imageUrl: artist.imageUrl,
        metadata: {
          'provider': artist.provider,
          'uri': artist.uri,
        },
      );
      _logger.log('📝 Recorded artist play: ${artist.name}');
    } catch (e) {
      _logger.log('⚠️ Failed to record artist play: $e');
    }
  }

  /// Record a track being played
  Future<void> recordTrackPlayed(Track track) async {
    if (!_db.isInitialized) return;

    try {
      await _db.addRecentlyPlayed(
        mediaId: track.itemId,
        mediaType: 'track',
        name: track.name,
        artistName: track.artistsString,
        imageUrl: track.imageUrl,
        metadata: {
          'provider': track.provider,
          'uri': track.uri,
          'albumName': track.album?.name,
        },
      );
      _logger.log('📝 Recorded track play: ${track.name}');
    } catch (e) {
      _logger.log('⚠️ Failed to record track play: $e');
    }
  }

  /// Record a playlist being played
  Future<void> recordPlaylistPlayed(Playlist playlist) async {
    if (!_db.isInitialized) return;

    try {
      await _db.addRecentlyPlayed(
        mediaId: playlist.itemId,
        mediaType: 'playlist',
        name: playlist.name,
        imageUrl: playlist.imageUrl,
        metadata: {
          'provider': playlist.provider,
          'uri': playlist.uri,
        },
      );
      _logger.log('📝 Recorded playlist play: ${playlist.name}');
    } catch (e) {
      _logger.log('⚠️ Failed to record playlist play: $e');
    }
  }

  /// Get recently played albums for the current profile
  /// Returns Album objects reconstructed from local data
  Future<List<Album>> getRecentAlbums({int limit = 20}) async {
    if (!_db.isInitialized) return [];

    try {
      final items = await _db.getRecentlyPlayed(limit: limit * 2); // Get more to filter

      // Filter for albums and convert to Album objects
      final albums = <Album>[];
      final seenIds = <String>{};

      for (final item in items) {
        if (item.mediaType != 'album') continue;
        if (seenIds.contains(item.mediaId)) continue;
        seenIds.add(item.mediaId);

        Map<String, dynamic>? metadata;
        if (item.metadata != null) {
          try {
            metadata = jsonDecode(item.metadata!) as Map<String, dynamic>;
          } catch (_) {}
        }

        albums.add(Album(
          itemId: item.mediaId,
          provider: metadata?['provider'] ?? 'library',
          name: item.name,
          imageUrl: item.imageUrl,
          uri: metadata?['uri'],
          // Create minimal artist info from stored name
          artists: item.artistName != null
              ? [Artist(itemId: '', provider: '', name: item.artistName!)]
              : null,
        ));

        if (albums.length >= limit) break;
      }

      return albums;
    } catch (e) {
      _logger.log('⚠️ Failed to get recent albums: $e');
      return [];
    }
  }

  /// Get all recently played items for the current profile
  Future<List<RecentlyPlayedData>> getRecentlyPlayed({int limit = 20}) async {
    if (!_db.isInitialized) return [];
    return _db.getRecentlyPlayed(limit: limit);
  }

  /// Check if we have local recently played data
  Future<bool> hasLocalData() async {
    if (!_db.isInitialized) return false;
    final items = await _db.getRecentlyPlayed(limit: 1);
    return items.isNotEmpty;
  }

  /// Clear recently played for current profile
  Future<void> clear() async {
    if (!_db.isInitialized) return;
    await _db.clearRecentlyPlayed();
    _logger.log('🗑️ Cleared recently played');
  }
}
