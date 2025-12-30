import 'media_item.dart';

class Player {
  final String playerId;
  final String name;
  final String? provider; // e.g., 'builtin_player', 'chromecast', etc.
  final bool available;
  final bool powered;
  final String state; // 'idle', 'playing', 'paused'
  final String? currentItemId;
  final int? volumeLevel; // 0-100
  final bool? volumeMuted;
  final double? elapsedTime; // Seconds elapsed in current track
  final double? elapsedTimeLastUpdated; // Unix timestamp when elapsed_time was last updated
  final List<String>? groupMembers; // List of player IDs in sync group (includes self)
  final String? syncedTo; // Player ID this player is synced to (null if leader or not synced)
  final String? activeSource; // The currently active source for this player
  final bool isExternalSource; // True when an external source (optical, Spotify, etc.) is active
  final String? appId; // The app_id from MA - 'music_assistant' when MA is playing, else external source

  Player({
    required this.playerId,
    required this.name,
    this.provider,
    required this.available,
    required this.powered,
    required this.state,
    this.currentItemId,
    this.volumeLevel,
    this.volumeMuted,
    this.elapsedTime,
    this.elapsedTimeLastUpdated,
    this.groupMembers,
    this.syncedTo,
    this.activeSource,
    this.isExternalSource = false,
    this.appId,
  });

  /// Create a copy of this Player with some fields replaced
  Player copyWith({
    String? playerId,
    String? name,
    String? provider,
    bool? available,
    bool? powered,
    String? state,
    String? currentItemId,
    int? volumeLevel,
    bool? volumeMuted,
    double? elapsedTime,
    double? elapsedTimeLastUpdated,
    List<String>? groupMembers,
    String? syncedTo,
    String? activeSource,
    bool? isExternalSource,
    String? appId,
  }) {
    return Player(
      playerId: playerId ?? this.playerId,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      available: available ?? this.available,
      powered: powered ?? this.powered,
      state: state ?? this.state,
      currentItemId: currentItemId ?? this.currentItemId,
      volumeLevel: volumeLevel ?? this.volumeLevel,
      volumeMuted: volumeMuted ?? this.volumeMuted,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      elapsedTimeLastUpdated: elapsedTimeLastUpdated ?? this.elapsedTimeLastUpdated,
      groupMembers: groupMembers ?? this.groupMembers,
      syncedTo: syncedTo ?? this.syncedTo,
      activeSource: activeSource ?? this.activeSource,
      isExternalSource: isExternalSource ?? this.isExternalSource,
      appId: appId ?? this.appId,
    );
  }

  // Derived properties
  bool get isPlaying => state == 'playing';
  bool get isMuted => volumeMuted ?? false;
  int get volume => volumeLevel ?? 0;

  // Group properties
  // A player is grouped if it's a leader with members OR a child synced to another
  bool get isGrouped => (groupMembers != null && groupMembers!.length > 1) || syncedTo != null;
  bool get isGroupLeader => groupMembers != null && groupMembers!.length > 1 && syncedTo == null;
  bool get isGroupChild => syncedTo != null;

  // Track when this Player object was created (for local interpolation fallback)
  static final Map<String, double> _playerCreationTimes = {};

  // Calculate current elapsed time (interpolated if playing)
  double get currentElapsedTime {
    if (elapsedTime == null) {
      return 0;
    }

    if (!isPlaying) {
      return elapsedTime!;
    }

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Try server-provided timestamp first, but only if it's recent
    if (elapsedTimeLastUpdated != null) {
      final timeSinceUpdate = now - elapsedTimeLastUpdated!;

      // Only use server timestamp if it's within valid range (0-10 seconds)
      // - Negative means clock skew (client ahead of server)
      // - > 10 seconds means stale data (e.g., after player switch)
      // If outside this range, fall through to local fallback for smooth interpolation
      if (timeSinceUpdate >= 0 && timeSinceUpdate <= 10.0) {
        return elapsedTime! + timeSinceUpdate;
      }
      // Server timestamp is stale or invalid - fall through to local fallback
    }

    // Fallback: use local creation time for interpolation
    // This handles:
    // 1. Server doesn't send elapsed_time_last_updated
    // 2. Server timestamp is stale (e.g., after switching to a remote player)
    // 3. Clock skew between client and server
    //
    // Key insight: when server sends a NEW elapsed_time, we get a NEW key,
    // so interpolation naturally starts fresh. We should NEVER reset an existing
    // key's creation time, as that causes progress to jump backward.
    final creationKey = '$playerId:$elapsedTime';

    if (!_playerCreationTimes.containsKey(creationKey)) {
      // First time seeing this elapsed_time - record when we saw it
      _playerCreationTimes[creationKey] = now;
      // Clean up old entries to prevent memory leak
      if (_playerCreationTimes.length > 100) {
        final keysToRemove = _playerCreationTimes.keys.take(50).toList();
        for (final key in keysToRemove) {
          _playerCreationTimes.remove(key);
        }
      }
    }

    final creationTime = _playerCreationTimes[creationKey]!;
    final timeSinceCreation = now - creationTime;

    // Server sends updates every ~5 seconds with new elapsed_time values,
    // which creates new keys and corrects any drift. Allow unlimited
    // interpolation since new server data will naturally correct it.
    return elapsedTime! + timeSinceCreation;
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    // Extract current_item_id from current_media if available
    String? currentItemId = json['current_item_id'] as String?;
    double? elapsedTime;
    double? elapsedTimeLastUpdated;

    // Get top-level elapsed time values
    // Try multiple field names as different player types may report position differently
    final topLevelElapsedTime = (json['elapsed_time'] as num?)?.toDouble()
        ?? (json['position'] as num?)?.toDouble()
        ?? (json['media_position'] as num?)?.toDouble()
        ?? (json['current_position'] as num?)?.toDouble();
    final topLevelLastUpdated = (json['elapsed_time_last_updated'] as num?)?.toDouble()
        ?? (json['position_updated_at'] as num?)?.toDouble();

    // Extract current_item_id and elapsed time from current_media
    // current_media often has the more accurate position after seeks
    if (json.containsKey('current_media')) {
      final currentMedia = json['current_media'] as Map<String, dynamic>?;
      if (currentMedia != null) {
        currentItemId ??= currentMedia['queue_item_id'] as String?;

        // Try multiple field names for position
        final currentMediaElapsedTime = (currentMedia['elapsed_time'] as num?)?.toDouble()
            ?? (currentMedia['position'] as num?)?.toDouble()
            ?? (currentMedia['media_position'] as num?)?.toDouble();
        final currentMediaLastUpdated = (currentMedia['elapsed_time_last_updated'] as num?)?.toDouble()
            ?? (currentMedia['position_updated_at'] as num?)?.toDouble();

        // Prefer current_media elapsed_time when available - it reflects actual playback position
        // after seek operations, while top-level elapsed_time may lag behind
        if (currentMediaElapsedTime != null) {
          elapsedTime = currentMediaElapsedTime;
          elapsedTimeLastUpdated = currentMediaLastUpdated ?? topLevelLastUpdated;
        }
      }
    }

    // Fall back to top-level values if current_media didn't have elapsed time
    elapsedTime ??= topLevelElapsedTime;
    elapsedTimeLastUpdated ??= topLevelLastUpdated;

    // Parse group members - MA returns this as a list of player IDs
    final groupMembersList = json['group_members'] as List<dynamic>?;
    final groupMembers = groupMembersList?.map((e) => e.toString()).toList();

    // Parse synced_to - the player ID this player is synced to
    final syncedTo = json['synced_to'] as String?;

    // Parse active_source - the currently active source for this player
    final activeSource = json['active_source'] as String?;

    // Detect external source (optical, Spotify, AirPlay, etc.)
    // Primary indicator: app_id - if not 'music_assistant', it's an external source
    // Secondary indicators: URI patterns and media_type
    bool isExternalSource = false;

    // Check app_id first - this is the most reliable indicator for DLNA players
    // When MA is playing: app_id = 'music_assistant'
    // When external source: app_id = 'http', 'spotify', etc.
    final appId = json['app_id'] as String?;
    if (appId != null && appId.isNotEmpty && appId != 'music_assistant') {
      // app_id is set but not 'music_assistant' - external source is active
      isExternalSource = true;
    }

    // Also check current_media for additional external source indicators
    if (!isExternalSource && json.containsKey('current_media')) {
      final currentMedia = json['current_media'] as Map<String, dynamic>?;
      if (currentMedia != null) {
        final uri = currentMedia['uri'] as String?;
        final mediaType = currentMedia['media_type'] as String?;

        // External source indicators:
        // 1. URI is a simple identifier like 'optical', 'line_in', 'bluetooth', 'hdmi'
        // 2. URI starts with external protocols: 'spotify://', 'airplay://', etc.
        // 3. Media type is 'unknown' (MA doesn't recognize the source)
        if (uri != null) {
          final uriLower = uri.toLowerCase();
          // Simple external source identifiers (no :// or /)
          final isSimpleExternalId = !uri.contains('://') && !uri.contains('/') &&
              (uriLower == 'optical' || uriLower == 'line_in' || uriLower == 'bluetooth' ||
               uriLower == 'hdmi' || uriLower == 'tv' || uriLower == 'aux' ||
               uriLower == 'coaxial' || uriLower == 'toslink');
          // External streaming protocols
          final isExternalProtocol = uriLower.startsWith('spotify://') ||
              uriLower.startsWith('airplay://') ||
              uriLower.startsWith('cast://') ||
              uriLower.startsWith('bluetooth://');

          isExternalSource = isSimpleExternalId || isExternalProtocol;
        }

        // Also check media_type - 'unknown' often indicates external source
        if (!isExternalSource && mediaType == 'unknown') {
          // If media_type is unknown and URI doesn't look like MA content, it's external
          final uri = currentMedia['uri'] as String?;
          if (uri != null && !uri.startsWith('library://') && !uri.contains('://track/')) {
            isExternalSource = true;
          }
        }
      }
    }

    return Player(
      playerId: json['player_id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String?,
      available: json['available'] as bool? ?? false,
      powered: json['powered'] as bool? ?? false,
      state: json['playback_state'] as String? ?? json['state'] as String? ?? 'idle',
      currentItemId: currentItemId,
      volumeLevel: json['volume_level'] as int?,
      volumeMuted: json['volume_muted'] as bool?,
      elapsedTime: elapsedTime,
      elapsedTimeLastUpdated: elapsedTimeLastUpdated,
      groupMembers: groupMembers,
      syncedTo: syncedTo,
      activeSource: activeSource,
      isExternalSource: isExternalSource,
      appId: appId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'name': name,
      if (provider != null) 'provider': provider,
      'available': available,
      'powered': powered,
      'state': state,
      if (currentItemId != null) 'current_item_id': currentItemId,
      if (volumeLevel != null) 'volume_level': volumeLevel,
      if (volumeMuted != null) 'volume_muted': volumeMuted,
      if (elapsedTime != null) 'elapsed_time': elapsedTime,
      if (elapsedTimeLastUpdated != null) 'elapsed_time_last_updated': elapsedTimeLastUpdated,
      if (groupMembers != null) 'group_members': groupMembers,
      if (syncedTo != null) 'synced_to': syncedTo,
      if (activeSource != null) 'active_source': activeSource,
      'is_external_source': isExternalSource,
      if (appId != null) 'app_id': appId,
    };
  }
}

class StreamDetails {
  final String? streamId;
  final int sampleRate;
  final int bitDepth;
  final String contentType;

  StreamDetails({
    this.streamId,
    required this.sampleRate,
    required this.bitDepth,
    required this.contentType,
  });

  factory StreamDetails.fromJson(Map<String, dynamic> json) {
    return StreamDetails(
      streamId: json['stream_id'] as String?,
      sampleRate: json['sample_rate'] as int? ?? 44100,
      bitDepth: json['bit_depth'] as int? ?? 16,
      contentType: json['content_type'] as String? ?? 'audio/flac',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'sample_rate': sampleRate,
      'bit_depth': bitDepth,
      'content_type': contentType,
    };
  }
}

class QueueItem {
  final String queueItemId;
  final Track track;
  final StreamDetails? streamdetails;

  QueueItem({
    required this.queueItemId,
    required this.track,
    this.streamdetails,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    // Queue items may have queue_item_id, or we fall back to item_id from the track
    final queueItemId = json['queue_item_id'] as String? ??
                        json['item_id']?.toString() ??
                        '';

    // The track data is nested inside 'media_item' field (if present and not null)
    final mediaItemData = json.containsKey('media_item') && json['media_item'] != null
        ? json['media_item'] as Map<String, dynamic>
        : json;

    return QueueItem(
      queueItemId: queueItemId,
      track: Track.fromJson(mediaItemData),
      streamdetails: json['streamdetails'] != null
          ? StreamDetails.fromJson(json['streamdetails'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'queue_item_id': queueItemId,
      ...track.toJson(),
      if (streamdetails != null) 'streamdetails': streamdetails!.toJson(),
    };
  }
}

class PlayerQueue {
  final String playerId;
  final List<QueueItem> items;
  final int? currentIndex;
  final bool? shuffleEnabled;
  final String? repeatMode; // 'off', 'one', 'all'

  PlayerQueue({
    required this.playerId,
    required this.items,
    this.currentIndex,
    this.shuffleEnabled,
    this.repeatMode,
  });

  bool get shuffle => shuffleEnabled ?? false;
  bool get repeatAll => repeatMode == 'all';
  bool get repeatOne => repeatMode == 'one';
  bool get repeatOff => repeatMode == 'off' || repeatMode == null;

  factory PlayerQueue.fromJson(Map<String, dynamic> json) {
    return PlayerQueue(
      playerId: json['player_id'] as String,
      items: (json['items'] as List<dynamic>?)
              ?.map((i) => QueueItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      currentIndex: json['current_index'] as int?,
      shuffleEnabled: json['shuffle_enabled'] as bool?,
      repeatMode: json['repeat_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_id': playerId,
      'items': items.map((i) => i.toJson()).toList(),
      if (currentIndex != null) 'current_index': currentIndex,
      if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
      if (repeatMode != null) 'repeat_mode': repeatMode,
    };
  }

  QueueItem? get currentItem {
    if (currentIndex == null || items.isEmpty) return null;
    if (currentIndex! < 0 || currentIndex! >= items.length) return null;
    return items[currentIndex!];
  }
}
