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
      // Store images metadata for instant artwork display
      final images = album.metadata?['images'];
      await _db.addRecentlyPlayed(
        mediaId: album.itemId,
        mediaType: 'album',
        name: album.name,
        artistName: album.artistsString,
        metadata: {
          'provider': album.provider,
          'uri': album.uri,
          if (images != null) 'images': images,
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

  /// Record an audiobook being played
  Future<void> recordAudiobookPlayed(Audiobook audiobook) async {
    if (!_db.isInitialized) return;

    try {
      await _db.addRecentlyPlayed(
        mediaId: audiobook.itemId,
        mediaType: 'audiobook',
        name: audiobook.name,
        artistName: audiobook.authorsString,
        metadata: {
          'provider': audiobook.provider,
          'uri': audiobook.uri,
          'narrators': audiobook.narratorsString,
          'duration': audiobook.duration?.inSeconds,
          'resumePositionMs': audiobook.resumePositionMs,
        },
      );
      _logger.log('📝 Recorded audiobook play: ${audiobook.name}');
    } catch (e) {
      _logger.log('⚠️ Failed to record audiobook play: $e');
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

        // Build metadata with images if available (for instant artwork display)
        Map<String, dynamic>? albumMetadata;
        if (metadata?['images'] != null) {
          albumMetadata = {'images': metadata!['images']};
        }

        albums.add(Album(
          itemId: item.mediaId,
          provider: metadata?['provider'] ?? 'library',
          name: item.name,
          uri: metadata?['uri'],
          // Create minimal artist info from stored name
          artists: item.artistName != null
              ? [Artist(itemId: '', provider: '', name: item.artistName!)]
              : null,
          metadata: albumMetadata,
        ));

        if (albums.length >= limit) break;
      }

      return albums;
    } catch (e) {
      _logger.log('⚠️ Failed to get recent albums: $e');
      return [];
    }
  }

  /// Get recently played audiobooks for the current profile
  /// Returns Audiobook objects reconstructed from local data
  Future<List<Audiobook>> getRecentAudiobooks({int limit = 20}) async {
    if (!_db.isInitialized) return [];

    try {
      final items = await _db.getRecentlyPlayed(limit: limit * 2); // Get more to filter

      // Filter for audiobooks and convert to Audiobook objects
      final audiobooks = <Audiobook>[];
      final seenIds = <String>{};

      for (final item in items) {
        if (item.mediaType != 'audiobook') continue;
        if (seenIds.contains(item.mediaId)) continue;
        seenIds.add(item.mediaId);

        Map<String, dynamic>? metadata;
        if (item.metadata != null) {
          try {
            metadata = jsonDecode(item.metadata!) as Map<String, dynamic>;
          } catch (_) {}
        }

        audiobooks.add(Audiobook(
          itemId: item.mediaId,
          provider: metadata?['provider'] ?? 'library',
          name: item.name,
          uri: metadata?['uri'],
          // Create minimal author info from stored name
          authors: item.artistName != null
              ? [Artist(itemId: '', provider: '', name: item.artistName!)]
              : null,
          duration: metadata?['duration'] != null
              ? Duration(seconds: metadata!['duration'] as int)
              : null,
          resumePositionMs: metadata?['resumePositionMs'] as int?,
        ));

        if (audiobooks.length >= limit) break;
      }

      return audiobooks;
    } catch (e) {
      _logger.log('⚠️ Failed to get recent audiobooks: $e');
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
