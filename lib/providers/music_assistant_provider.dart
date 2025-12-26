import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../models/media_item.dart';
import '../models/player.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/auth/auth_manager.dart';
import '../services/device_id_service.dart';
import '../services/cache_service.dart';
import '../services/recently_played_service.dart';
import '../services/sync_service.dart';
import '../services/local_player_service.dart';
import '../services/metadata_service.dart';
import '../services/position_tracker.dart';
import '../services/sendspin_service.dart';
import '../services/pcm_audio_player.dart';
import '../services/offline_action_queue.dart';
import '../constants/timings.dart';
import '../services/database_service.dart';
import '../main.dart' show audioHandler;

/// Main provider that coordinates connection, player, and library state.
///
/// This is a facade that delegates to internal services while maintaining
/// backward compatibility with existing code that uses MusicAssistantProvider.
///
/// Architecture:
/// - CacheService: Handles all caching (non-notifying)
/// - Connection logic: WebSocket, auth, reconnection
/// - Player logic: Player selection, controls, local player
/// - Library logic: Artists, albums, tracks, search
class MusicAssistantProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthManager _authManager = AuthManager();
  final DebugLogger _logger = DebugLogger();
  final CacheService _cacheService = CacheService();
  final PositionTracker _positionTracker = PositionTracker();

  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;
  String? _error;

  // Library state
  List<Artist> _artists = [];
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _isLoading = false;

  // Player state
  Player? _selectedPlayer;
  List<Player> _availablePlayers = [];
  Map<String, String> _castToSendspinIdMap = {}; // Maps regular Cast IDs to Sendspin IDs for grouping
  Track? _currentTrack;
  Audiobook? _currentAudiobook; // Currently playing audiobook context (with chapters)
  Timer? _playerStateTimer;
  Timer? _notificationPositionTimer; // Updates notification position every second for remote players

  // Local player state
  bool _isLocalPlayerPowered = true;
  int _localPlayerVolume = 100; // Tracked MA volume for builtin player (0-100)
  bool _builtinPlayerAvailable = true; // False on MA 2.7.0b20+ (uses Sendspin instead)
  StreamSubscription? _localPlayerEventSubscription;
  StreamSubscription? _playerUpdatedEventSubscription;
  StreamSubscription? _playerAddedEventSubscription;
  Timer? _localPlayerStateReportTimer;
  TrackMetadata? _pendingTrackMetadata;
  TrackMetadata? _currentNotificationMetadata;
  Completer<void>? _registrationInProgress;

  // Local player service
  late final LocalPlayerService _localPlayer;

  // Sendspin service (MA 2.7.0b20+ replacement for builtin_player)
  SendspinService? _sendspinService;
  bool _sendspinConnected = false;

  // PCM audio player for raw Sendspin audio streaming
  PcmAudioPlayer? _pcmAudioPlayer;

  // Search state persistence
  String _lastSearchQuery = '';
  Map<String, List<MediaItem>> _lastSearchResults = {
    'artists': [],
    'albums': [],
    'tracks': [],
  };

  // ============================================================================
  // GETTERS
  // ============================================================================

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected ||
                          _connectionState == MAConnectionState.authenticated;

  List<Artist> get artists => _artists;
  List<Album> get albums => _albums;
  List<Track> get tracks => _tracks;
  bool get isLoading => _isLoading;

  /// Whether library is syncing in background
  bool get isSyncing => SyncService.instance.isSyncing;

  /// Current sync status
  SyncStatus get syncStatus => SyncService.instance.status;

  /// Selected player - loads from cache if not yet set
  Player? get selectedPlayer {
    if (_selectedPlayer == null && _cacheService.getCachedSelectedPlayer() != null) {
      _selectedPlayer = _cacheService.getCachedSelectedPlayer();
    }
    return _selectedPlayer;
  }

  /// Available players - loads from cache for instant UI display
  List<Player> get availablePlayers {
    if (_availablePlayers.isEmpty && _cacheService.hasCachedPlayers) {
      _availablePlayers = _cacheService.getCachedPlayers()!;
      _logger.log('⚡ Loaded ${_availablePlayers.length} players from cache (lazy)');
    }
    return _availablePlayers;
  }

  Track? get currentTrack => _currentTrack;

  /// Whether we have cached players available (for instant UI display on app resume)
  bool get hasCachedPlayers => _cacheService.hasCachedPlayers;

  /// Currently playing audiobook context (with chapters) - set when playing an audiobook
  Audiobook? get currentAudiobook => _currentAudiobook;

  /// Whether we're currently playing an audiobook
  bool get isPlayingAudiobook => _currentAudiobook != null;

  String get lastSearchQuery => _lastSearchQuery;
  Map<String, List<MediaItem>> get lastSearchResults => _lastSearchResults;

  MusicAssistantAPI? get api => _api;
  AuthManager get authManager => _authManager;

  /// Position tracker for playback progress - single source of truth
  PositionTracker get positionTracker => _positionTracker;

  /// Whether Sendspin (PCM streaming) is connected for builtin player
  bool get isSendspinConnected => _sendspinConnected;

  /// Whether PCM audio is currently playing via Sendspin
  bool get isPcmPlaying => _sendspinConnected && _pcmAudioPlayer != null && _pcmAudioPlayer!.isPlaying;

  /// Get current PCM audio format info (when using Sendspin)
  /// Returns null if not using Sendspin PCM streaming
  String? get currentAudioFormat {
    if (!_sendspinConnected || _pcmAudioPlayer == null) return null;
    return '48kHz • Stereo • 16-bit PCM';
  }

  /// Get the current playback source description
  String get playbackSource {
    if (_sendspinConnected && _pcmAudioPlayer != null) {
      return 'Sendspin (Local PCM)';
    }
    return 'Music Assistant';
  }

  /// Get cached track for a player (used for smooth swipe transitions)
  /// For grouped child players, returns the leader's track
  Track? getCachedTrackForPlayer(String playerId) {
    // If player is a group child, get the leader's track instead
    final player = _availablePlayers.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => Player(
        playerId: playerId,
        name: '',
        available: false,
        powered: false,
        state: 'idle',
      ),
    );

    final effectivePlayerId = (player.isGroupChild && player.syncedTo != null)
        ? player.syncedTo!
        : playerId;

    return _cacheService.getCachedTrackForPlayer(effectivePlayerId);
  }

  /// Get artwork URL for a player from cache
  String? getCachedArtworkUrl(String playerId, {int size = 512}) {
    final track = getCachedTrackForPlayer(playerId);
    if (track == null) return null;
    return getImageUrl(track, size: size);
  }

  /// Number of pending offline actions
  int get pendingOfflineActionsCount => OfflineActionQueue.instance.pendingCount;

  /// Whether there are pending offline actions
  bool get hasPendingOfflineActions => OfflineActionQueue.instance.hasPendingActions;

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  MusicAssistantProvider() {
    _localPlayer = LocalPlayerService(_authManager);
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();

    // Load cached players from database for instant display (before connecting)
    await _loadPlayersFromDatabase();

    // Load cached library from SyncService for instant favorites display
    await _loadLibraryFromCache();

    // Load cached home rows from database for instant discover/recent display
    await _cacheService.loadHomeRowsFromDatabase();

    // Initialize offline action queue
    await OfflineActionQueue.instance.initialize();

    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      await _restoreAuthCredentials();
      await connectToServer(_serverUrl!);
      await _initializeLocalPlayback();
    }
  }

  /// Load cached players from database for instant UI display
  Future<void> _loadPlayersFromDatabase() async {
    try {
      if (!DatabaseService.instance.isInitialized) {
        await DatabaseService.instance.initialize();
      }

      final cachedPlayers = await DatabaseService.instance.getCachedPlayers();
      if (cachedPlayers.isEmpty) {
        _logger.log('📦 No cached players in database');
        return;
      }

      final players = <Player>[];
      for (final cached in cachedPlayers) {
        try {
          final playerData = jsonDecode(cached.playerJson) as Map<String, dynamic>;
          players.add(Player.fromJson(playerData));
        } catch (e) {
          _logger.log('⚠️ Error parsing cached player: $e');
        }
      }

      if (players.isNotEmpty) {
        _availablePlayers = players;
        _cacheService.setCachedPlayers(players);

        // Restore selected player from settings
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();
        if (lastSelectedPlayerId != null) {
          try {
            _selectedPlayer = players.firstWhere((p) => p.playerId == lastSelectedPlayerId);
            _cacheService.setCachedSelectedPlayer(_selectedPlayer);
            _logger.log('📦 Restored selected player from database: ${_selectedPlayer?.name}');
          } catch (_) {
            // Player not in cached list
          }
        }

        _logger.log('📦 Loaded ${players.length} players from database (instant)');
        notifyListeners();

        // Also load saved playback state for instant track display
        if (_selectedPlayer != null) {
          await _loadPlaybackStateFromDatabase();
        }
      }
    } catch (e) {
      _logger.log('⚠️ Error loading players from database: $e');
    }
  }

  /// Load saved playback state (currentTrack) from database for instant display
  Future<void> _loadPlaybackStateFromDatabase() async {
    try {
      final playbackState = await DatabaseService.instance.getPlaybackState();
      if (playbackState == null) {
        _logger.log('📦 No saved playback state in database');
        return;
      }

      // Only restore if it matches the current player
      if (playbackState.playerId != _selectedPlayer?.playerId) {
        _logger.log('📦 Saved playback state is for different player, skipping');
        return;
      }

      if (playbackState.currentTrackJson != null) {
        try {
          final trackData = jsonDecode(playbackState.currentTrackJson!) as Map<String, dynamic>;
          _currentTrack = Track.fromJson(trackData);
          _logger.log('📦 Restored currentTrack from database: ${_currentTrack?.name}');
          notifyListeners();
        } catch (e) {
          _logger.log('⚠️ Error parsing cached track: $e');
        }
      }
    } catch (e) {
      _logger.log('⚠️ Error loading playback state: $e');
    }
  }

  /// Load library data from SyncService cache for instant favorites display
  Future<void> _loadLibraryFromCache() async {
    try {
      final syncService = SyncService.instance;

      // Ensure SyncService has loaded from database
      if (!syncService.hasCache) {
        await syncService.loadFromCache();
      }

      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        // Note: tracks are loaded separately via API, not cached in SyncService
        _logger.log('📦 Pre-loaded library for favorites: ${_albums.length} albums, ${_artists.length} artists');
        notifyListeners();
      }
    } catch (e) {
      _logger.log('⚠️ Error loading library from cache: $e');
    }
  }

  /// Persist current playback state to database (fire-and-forget)
  void _persistPlaybackState() {
    if (_selectedPlayer == null) return;

    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        await DatabaseService.instance.savePlaybackState(
          playerId: _selectedPlayer!.playerId,
          playerName: _selectedPlayer!.name,
          currentTrackJson: _currentTrack != null ? jsonEncode(_currentTrack!.toJson()) : null,
          isPlaying: _selectedPlayer!.state == 'playing',
        );
        _logger.log('💾 Persisted playback state to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting playback state: $e');
      }
    }();
  }

  /// Persist players to database for app restart persistence
  void _persistPlayersToDatabase(List<Player> players) {
    // Run async but don't await - this is fire-and-forget persistence
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        final playerMaps = players.map((p) => {
          'playerId': p.playerId,
          'playerJson': jsonEncode(p.toJson()),
          'currentTrackJson': null as String?, // Will be updated separately when track changes
        }).toList();

        await DatabaseService.instance.cachePlayers(playerMaps);
        _logger.log('💾 Persisted ${players.length} players to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting players to database: $e');
      }
    }();
  }

  Future<void> _restoreAuthCredentials() async {
    final savedCredentials = await SettingsService.getAuthCredentials();
    if (savedCredentials != null) {
      _logger.log('🔐 Restoring saved auth credentials...');
      _authManager.deserializeCredentials(savedCredentials);
      _logger.log('🔐 Auth credentials restored: ${_authManager.currentStrategy?.name ?? "none"}');
    }
  }

  // ============================================================================
  // CONNECTION
  // ============================================================================

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Dispose the old API to stop any pending reconnects
      _api?.dispose();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      _api!.connectionState.listen(
        (state) async {
          _connectionState = state;
          notifyListeners();

          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            if (_api!.authRequired && !_api!.isAuthenticated) {
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await _handleMaAuthentication();
              if (!authenticated) {
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              // After authentication succeeds, authenticated state will trigger initialization
              // Don't call _initializeAfterConnection() here - wait for authenticated state
              return;
            }

            // No auth required, initialize immediately
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.authenticated) {
            _logger.log('✅ MA authentication successful');
            // Now safe to initialize since we're authenticated
            await _initializeAfterConnection();
          } else if (state == MAConnectionState.disconnected) {
            // DON'T clear players or caches on disconnect!
            // Keep showing cached data for instant UI display on reconnect
            // Player list and state will be refreshed when connection is restored
            _logger.log('📡 Disconnected - keeping cached players and data for instant resume');
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
      );

      _localPlayerEventSubscription?.cancel();
      _localPlayerEventSubscription = _api!.builtinPlayerEvents.listen(
        _handleLocalPlayerEvent,
        onError: (error) => _logger.log('Builtin player event stream error: $error'),
      );

      _playerUpdatedEventSubscription?.cancel();
      _playerUpdatedEventSubscription = _api!.playerUpdatedEvents.listen(
        _handlePlayerUpdatedEvent,
        onError: (error) => _logger.log('Player updated event stream error: $error'),
      );

      _playerAddedEventSubscription?.cancel();
      _playerAddedEventSubscription = _api!.playerAddedEvents.listen(
        _handlePlayerAddedEvent,
        onError: (error) => _logger.log('Player added event stream error: $error'),
      );

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Connect to server');
      _error = errorInfo.userMessage;
      _connectionState = MAConnectionState.error;
      _logger.log('Connection error: ${errorInfo.technicalMessage}');
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> _handleMaAuthentication() async {
    if (_api == null) return false;

    try {
      final storedToken = await SettingsService.getMaAuthToken();
      if (storedToken != null) {
        _logger.log('🔐 Trying stored MA token...');
        final success = await _api!.authenticateWithToken(storedToken);
        if (success) {
          _logger.log('✅ MA authentication with stored token successful');
          await _fetchAndSetUserProfileName();
          return true;
        }
        _logger.log('⚠️ Stored MA token invalid, clearing...');
        await SettingsService.clearMaAuthToken();
      }

      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        _logger.log('🔐 Trying stored credentials...');
        final accessToken = await _api!.loginWithCredentials(username, password);

        if (accessToken != null) {
          _logger.log('✅ MA login with stored credentials successful');

          final longLivedToken = await _api!.createLongLivedToken();
          if (longLivedToken != null) {
            await SettingsService.setMaAuthToken(longLivedToken);
            _logger.log('✅ Saved new long-lived MA token');
          } else {
            await SettingsService.setMaAuthToken(accessToken);
          }

          await _fetchAndSetUserProfileName();
          return true;
        }
      }

      _logger.log('❌ MA authentication failed - no valid token or credentials');
      return false;
    } catch (e) {
      _logger.log('❌ MA authentication error: $e');
      return false;
    }
  }

  Future<void> _fetchAndSetUserProfileName() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) return;

      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;

      final profileName = (displayName != null && displayName.isNotEmpty) ? displayName : username;

      if (profileName != null && profileName.isNotEmpty) {
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user profile (non-fatal): $e');
    }
  }

  Future<void> _initializeAfterConnection() async {
    if (_api == null) return;

    try {
      _logger.log('🚀 Initializing after connection...');

      await _api!.fetchState();

      if (_api!.authRequired) {
        await _fetchAndSetUserProfileName();
      }

      await _tryAdoptGhostPlayer();
      await _registerLocalPlayer();
      await _loadAndSelectPlayers();

      loadLibrary();

      // Process any queued offline actions now that we're connected
      await _processOfflineQueue();

      _logger.log('✅ Post-connection initialization complete');
    } catch (e) {
      _logger.log('❌ Error during post-connection initialization: $e');
      _error = 'Failed to initialize after connection';
      notifyListeners();
    }
  }

  /// Process queued offline actions (favorites, playlist modifications, etc.)
  Future<void> _processOfflineQueue() async {
    if (_api == null || !isConnected) return;

    final queue = OfflineActionQueue.instance;
    if (!queue.hasPendingActions) return;

    _logger.log('📋 Processing ${queue.pendingCount} offline actions...');

    await queue.processQueue((action) async {
      try {
        switch (action.type) {
          case OfflineActionTypes.toggleFavorite:
            return await _executeToggleFavorite(action.params);
          case OfflineActionTypes.addToPlaylist:
            return await _executeAddToPlaylist(action.params);
          case OfflineActionTypes.removeFromPlaylist:
            return await _executeRemoveFromPlaylist(action.params);
          default:
            _logger.log('⚠️ Unknown offline action type: ${action.type}');
            return false;
        }
      } catch (e) {
        _logger.log('❌ Error executing offline action ${action.type}: $e');
        return false;
      }
    });
  }

  /// Execute a queued toggle favorite action
  Future<bool> _executeToggleFavorite(Map<String, dynamic> params) async {
    if (_api == null) return false;

    final mediaType = params['mediaType'] as String;
    final add = params['add'] as bool;

    if (add) {
      final itemId = params['itemId'] as String;
      final provider = params['provider'] as String;
      await _api!.addToFavorites(mediaType, itemId, provider);
    } else {
      final libraryItemId = params['libraryItemId'] as int;
      await _api!.removeFromFavorites(mediaType, libraryItemId);
    }
    return true;
  }

  /// Execute a queued add to playlist action
  Future<bool> _executeAddToPlaylist(Map<String, dynamic> params) async {
    // TODO: Implement when playlist modification is added
    return false;
  }

  /// Execute a queued remove from playlist action
  Future<bool> _executeRemoveFromPlaylist(Map<String, dynamic> params) async {
    // TODO: Implement when playlist modification is added
    return false;
  }

  // ============================================================================
  // FAVORITE MANAGEMENT (WITH OFFLINE SUPPORT)
  // ============================================================================

  /// Add item to favorites with offline queuing support
  /// Returns true if action was executed or queued successfully
  Future<bool> addToFavorites({
    required String mediaType,
    required String itemId,
    required String provider,
  }) async {
    if (isConnected && _api != null) {
      // Online - execute immediately
      try {
        await _api!.addToFavorites(mediaType, itemId, provider);
        return true;
      } catch (e) {
        _logger.log('❌ Failed to add to favorites: $e');
        return false;
      }
    } else {
      // Offline - queue the action
      await OfflineActionQueue.instance.queueAction(
        OfflineActionTypes.toggleFavorite,
        {
          'mediaType': mediaType,
          'add': true,
          'itemId': itemId,
          'provider': provider,
        },
      );
      _logger.log('📋 Queued add to favorites (offline): $mediaType');
      return true;
    }
  }

  /// Remove item from favorites with offline queuing support
  /// Returns true if action was executed or queued successfully
  Future<bool> removeFromFavorites({
    required String mediaType,
    required int libraryItemId,
  }) async {
    if (isConnected && _api != null) {
      // Online - execute immediately
      try {
        await _api!.removeFromFavorites(mediaType, libraryItemId);
        return true;
      } catch (e) {
        _logger.log('❌ Failed to remove from favorites: $e');
        return false;
      }
    } else {
      // Offline - queue the action
      await OfflineActionQueue.instance.queueAction(
        OfflineActionTypes.toggleFavorite,
        {
          'mediaType': mediaType,
          'add': false,
          'libraryItemId': libraryItemId,
        },
      );
      _logger.log('📋 Queued remove from favorites (offline): $mediaType');
      return true;
    }
  }

  Future<void> disconnect() async {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
    _notificationPositionTimer?.cancel();
    _notificationPositionTimer = null;
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _playerAddedEventSubscription?.cancel();
    _positionTracker.clear();
    // Disconnect Sendspin and PCM player if connected
    if (_sendspinConnected) {
      await _pcmAudioPlayer?.disconnect();
      await _sendspinService?.disconnect();
      _sendspinConnected = false;
    }
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    // DON'T clear caches or player state - keep for instant reconnect
    _logger.log('📡 Explicit disconnect - keeping cached data for instant resume');
    notifyListeners();
  }

  /// Clear all caches and state (for logout or server change)
  void clearAllOnLogout() {
    _availablePlayers = [];
    _selectedPlayer = null;
    _artists = [];
    _albums = [];
    _tracks = [];
    _currentTrack = null;
    _cacheService.clearAll();
    _logger.log('🗑️ Cleared all data on logout');
    notifyListeners();
  }

  Future<void> checkAndReconnect() async {
    _logger.log('🔄 checkAndReconnect called - state: $_connectionState');

    if (_serverUrl == null) {
      _logger.log('🔄 No server URL saved, skipping reconnect');
      return;
    }

    // IMMEDIATELY load cached players for instant UI display
    // This makes mini player and device button appear instantly on app resume
    if (_availablePlayers.isEmpty && _cacheService.hasCachedPlayers) {
      _availablePlayers = _cacheService.getCachedPlayers()!;
      _selectedPlayer = _cacheService.getCachedSelectedPlayer();
      // Also try to restore from settings if cache doesn't have selected player
      if (_selectedPlayer == null && _availablePlayers.isNotEmpty) {
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();
        if (lastSelectedPlayerId != null) {
          try {
            _selectedPlayer = _availablePlayers.firstWhere(
              (p) => p.playerId == lastSelectedPlayerId,
            );
          } catch (e) {
            _selectedPlayer = _availablePlayers.first;
          }
        } else {
          _selectedPlayer = _availablePlayers.first;
        }
      }
      _logger.log('⚡ Loaded ${_availablePlayers.length} cached players instantly');
      notifyListeners(); // Update UI immediately with cached data
    }

    if (_connectionState != MAConnectionState.connected &&
        _connectionState != MAConnectionState.authenticated) {
      _logger.log('🔄 Not connected, attempting reconnect to $_serverUrl');
      try {
        await connectToServer(_serverUrl!);
        _logger.log('🔄 Reconnection successful');
      } catch (e) {
        _logger.log('🔄 Reconnection failed: $e');
      }
    } else {
      _logger.log('🔄 Already connected, verifying connection...');
      try {
        await refreshPlayers();
        await _updatePlayerState();
        // Note: _preloadAdjacentPlayers is already called in refreshPlayers() -> _loadAndSelectPlayers()
        _logger.log('🔄 Connection verified, players and state refreshed');
      } catch (e) {
        _logger.log('🔄 Connection verification failed, reconnecting: $e');
        try {
          await connectToServer(_serverUrl!);
        } catch (reconnectError) {
          _logger.log('🔄 Reconnection failed: $reconnectError');
        }
      }
    }
  }

  // ============================================================================
  // LOCAL PLAYER
  // ============================================================================

  Future<void> _initializeLocalPlayback() async {
    await _localPlayer.initialize();
    _isLocalPlayerPowered = true;

    // Wire up notification button callbacks
    audioHandler.onSkipToNext = () {
      _logger.log('🎵 Notification: Skip to next pressed');
      nextTrackSelectedPlayer();
    };
    audioHandler.onSkipToPrevious = () {
      _logger.log('🎵 Notification: Skip to previous pressed');
      previousTrackSelectedPlayer();
    };
    audioHandler.onPlay = () {
      _logger.log('🎵 Notification: Play pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onPause = () {
      _logger.log('🎵 Notification: Pause pressed');
      playPauseSelectedPlayer();
    };
    audioHandler.onSwitchPlayer = () {
      _logger.log('🎵 Notification: Switch player pressed');
      selectNextPlayer();
    };

    // Player registration is now handled in _initializeAfterConnection()
    // which runs after authentication completes (when auth is required)
  }

  Future<bool> _tryAdoptGhostPlayer() async {
    if (_api == null) return false;

    try {
      final isFresh = await DeviceIdService.isFreshInstallation();
      if (!isFresh) return false;

      final ownerName = await SettingsService.getOwnerName();
      if (ownerName == null || ownerName.isEmpty) return false;

      _logger.log('👻 Fresh install detected, searching for adoptable ghost for "$ownerName"...');
      final adoptableId = await _api!.findAdoptableGhostPlayer(ownerName);
      if (adoptableId == null) return false;

      _logger.log('👻 Found adoptable ghost: $adoptableId');
      await DeviceIdService.adoptPlayerId(adoptableId);
      _logger.log('✅ Successfully adopted ghost player');
      return true;
    } catch (e) {
      _logger.log('⚠️ Ghost adoption failed (non-fatal): $e');
      return false;
    }
  }

  /// Parse server version into components for version comparisons
  /// Returns null if version cannot be parsed
  ({int major, int minor, int patch, int? beta})? _parseServerVersion() {
    final serverInfo = _api?.serverInfo;
    if (serverInfo == null) return null;

    final versionStr = serverInfo['server_version'] as String?;
    if (versionStr == null) return null;

    // Parse version like "2.8.0b2" or "2.7.0b20" or "2.7.1"
    // Format: MAJOR.MINOR.PATCH[bBETA]
    final versionRegex = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:b(\d+))?');
    final match = versionRegex.firstMatch(versionStr);
    if (match == null) return null;

    return (
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      beta: match.group(4) != null ? int.parse(match.group(4)!) : null,
    );
  }

  /// Check if server version is >= 2.7.0b20 (uses Sendspin instead of builtin_player)
  bool _serverUsesSendspin() {
    final version = _parseServerVersion();
    if (version == null) return false;

    final (:major, :minor, :patch, :beta) = version;

    // Compare with 2.7.0b20
    if (major > 2) return true;
    if (major < 2) return false;
    // major == 2
    if (minor > 7) return true;
    if (minor < 7) return false;
    // minor == 7
    if (patch > 0) return true;
    if (patch < 0) return false;
    // patch == 0, so version is 2.7.0 - need beta >= 20
    if (beta == null) return true; // 2.7.0 release is newer than 2.7.0b20
    return beta >= 20;
  }

  /// Check if server version is >= 2.8.0 (has built-in /sendspin proxy endpoint)
  /// The /sendspin proxy was added in MA 2.8.0 (PR #2840)
  /// MA 2.7.x does NOT have this proxy - users must expose port 8927 directly
  /// or manually configure reverse proxy routing to port 8927
  bool _serverHasSendspinProxy() {
    final version = _parseServerVersion();
    if (version == null) return false;

    final (:major, :minor, :patch, :beta) = version;

    // Compare with 2.8.0
    if (major > 2) return true;
    if (major < 2) return false;
    // major == 2
    if (minor > 8) return true;
    if (minor < 8) return false;
    // minor == 8, any 2.8.x version has the proxy
    return true;
  }

  /// Get the server version string for logging
  String _getServerVersionString() {
    final serverInfo = _api?.serverInfo;
    return serverInfo?['server_version'] as String? ?? 'unknown';
  }

  Future<void> _registerLocalPlayer() async {
    if (_api == null) return;

    if (_registrationInProgress != null) {
      _logger.log('⏳ Registration already in progress, waiting...');
      return _registrationInProgress!.future;
    }

    _registrationInProgress = Completer<void>();

    try {
      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('🆔 Using player ID: $playerId');

      await SettingsService.setBuiltinPlayerId(playerId);

      final name = await SettingsService.getLocalPlayerName();

      // Check if server uses Sendspin (MA 2.7.0b20+) - skip builtin_player entirely
      if (_serverUsesSendspin()) {
        _logger.log('📡 Server uses Sendspin (MA 2.7.0b20+), skipping builtin_player');
        _builtinPlayerAvailable = false;

        final sendspinSuccess = await _connectViaSendspin();
        if (sendspinSuccess) {
          _logger.log('✅ Connected via Sendspin - local player available');
          _startReportingLocalPlayerState();
        } else {
          _logger.log('⚠️ Sendspin connection failed - local player unavailable');
        }

        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return;
      }

      final existingPlayers = await _api!.getPlayers();
      final existingPlayer = existingPlayers.where((p) => p.playerId == playerId).firstOrNull;

      if (existingPlayer != null && existingPlayer.available) {
        _logger.log('✅ Player already registered and available: $playerId');
        _startReportingLocalPlayerState();
        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return;
      } else if (existingPlayer != null && !existingPlayer.available) {
        _logger.log('⚠️ Player exists but unavailable (stale), re-registering: $playerId');
      } else {
        _logger.log('🆔 Player not found in MA, registering as new');
      }

      _logger.log('🎵 Registering player with MA: id=$playerId, name=$name');
      await _api!.registerBuiltinPlayer(playerId, name);

      _logger.log('✅ Player registration complete');
      _startReportingLocalPlayerState();

      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.complete();
      }
      _registrationInProgress = null;
    } catch (e) {
      // Check if this is because builtin_player API is not available (MA 2.7.0b20+)
      final errorStr = e.toString();
      if (errorStr.contains('Invalid command') && errorStr.contains('builtin_player')) {
        _logger.log('⚠️ Builtin player API not available (MA 2.7.0b20+ uses Sendspin)');
        _builtinPlayerAvailable = false;

        // Try to connect via Sendspin instead
        _logger.log('🔄 Attempting Sendspin connection...');
        final sendspinSuccess = await _connectViaSendspin();

        if (sendspinSuccess) {
          _logger.log('✅ Connected via Sendspin - local player available');
          _startReportingLocalPlayerState();
        } else {
          _logger.log('⚠️ Sendspin connection failed - local player unavailable');
          _logger.log('ℹ️ Use other players (Chromecast, etc) or ensure /sendspin route is configured');
        }

        if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
          _registrationInProgress!.complete();
        }
        _registrationInProgress = null;
        return; // Non-fatal, continue
      }

      _logger.log('❌ Player registration failed: $e');
      if (_registrationInProgress != null && !_registrationInProgress!.isCompleted) {
        _registrationInProgress!.completeError(e);
      }
      _registrationInProgress = null;
      rethrow;
    }
  }

  /// Connect to Music Assistant via Sendspin protocol (MA 2.7.0b20+)
  /// This is the replacement for builtin_player when that API is not available.
  ///
  /// Connection strategy depends on MA version and network:
  /// - MA 2.8.0+: Has built-in /sendspin proxy, works with any reverse proxy setup
  /// - MA 2.7.x: NO proxy, must either:
  ///   - Use local IP with port 8927 exposed, OR
  ///   - Manually configure reverse proxy to route /sendspin to port 8927
  Future<bool> _connectViaSendspin() async {
    if (_api == null || _serverUrl == null) return false;

    try {
      final serverVersion = _getServerVersionString();
      final hasProxy = _serverHasSendspinProxy();
      _logger.log('Sendspin: Server version $serverVersion, has proxy: $hasProxy');

      // Initialize Sendspin service
      _sendspinService?.dispose();
      _sendspinService = SendspinService(_serverUrl!);

      // Set auth token for proxy authentication (MA 2.8.0+ or manually configured proxy)
      final authToken = await SettingsService.getMaAuthToken();
      if (authToken != null) {
        _sendspinService!.setAuthToken(authToken);
        _logger.log('Sendspin: Auth token set for proxy authentication');
      }

      // Initialize PCM audio player for raw audio streaming
      _pcmAudioPlayer?.dispose();
      _pcmAudioPlayer = PcmAudioPlayer();
      final pcmInitialized = await _pcmAudioPlayer!.initialize();
      if (pcmInitialized) {
        _logger.log('✅ PCM audio player initialized for Sendspin');
        // Connect PCM player to Sendspin audio stream
        await _pcmAudioPlayer!.connectToStream(_sendspinService!.audioDataStream);
      } else {
        _logger.log('⚠️ PCM audio player initialization failed');
      }

      // Wire up callbacks
      _sendspinService!.onPlay = _handleSendspinPlay;
      _sendspinService!.onPause = _handleSendspinPause;
      _sendspinService!.onStop = _handleSendspinStop;
      _sendspinService!.onSeek = _handleSendspinSeek;
      _sendspinService!.onVolume = _handleSendspinVolume;
      _sendspinService!.onStreamStart = _handleSendspinStreamStart;
      _sendspinService!.onStreamEnd = _handleSendspinStreamEnd;

      final playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _logger.log('Sendspin: Player ID: $playerId');

      // Parse server URL to determine connection strategy
      final serverUri = Uri.parse(_serverUrl!.startsWith('http')
          ? _serverUrl!
          : 'https://$_serverUrl');
      final isLocalIp = _isLocalNetworkHost(serverUri.host);
      final isHttps = serverUri.scheme == 'https' ||
                      (!_serverUrl!.contains('://') && !isLocalIp);

      // Strategy 1: For local IPs, connect directly to Sendspin port 8927
      if (isLocalIp) {
        final localSendspinUrl = 'ws://${serverUri.host}:8927/sendspin';
        _logger.log('Sendspin: Local network detected, trying direct connection: $localSendspinUrl');
        final connected = await _sendspinService!.connectWithUrl(localSendspinUrl);
        if (connected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via local network (port 8927)');
          return true;
        }
        _logger.log('⚠️ Sendspin: Local connection to port 8927 failed');

        // For local IPs, also try the proxy path in case user has a local reverse proxy
        _logger.log('Sendspin: Trying local proxy fallback...');
        final localProxyUrl = 'ws://${serverUri.host}:${serverUri.hasPort ? serverUri.port : 8095}/sendspin';
        final proxyConnected = await _sendspinService!.connectWithUrl(localProxyUrl);
        if (proxyConnected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via local proxy');
          return true;
        }
      }

      // Strategy 2: For external/HTTPS servers, use the proxy at /sendspin
      if (isHttps || !isLocalIp) {
        if (hasProxy) {
          _logger.log('Sendspin: MA 2.8.0+ detected, using built-in /sendspin proxy');
        } else {
          _logger.log('Sendspin: MA 2.7.x detected, trying /sendspin (requires manual proxy config)');
        }

        final connected = await _sendspinService!.connect();
        if (connected) {
          _sendspinConnected = true;
          _logger.log('✅ Sendspin: Connected via external proxy');
          return true;
        }
        _logger.log('⚠️ Sendspin: External proxy connection failed');
      }

      // All strategies failed - provide version-specific guidance
      _logger.log('❌ Sendspin: All connection strategies failed');
      _logSendspinTroubleshooting(isLocalIp, hasProxy, serverVersion);

      return false;
    } catch (e) {
      _logger.log('❌ Sendspin connection error: $e');
      return false;
    }
  }

  /// Log troubleshooting guidance based on setup
  void _logSendspinTroubleshooting(bool isLocalIp, bool hasProxy, String serverVersion) {
    if (isLocalIp) {
      _logger.log('ℹ️ LOCAL IP SETUP: Add port 8927 to your Docker compose:');
      _logger.log('   ports:');
      _logger.log('     - "8095:8095"');
      _logger.log('     - "8927:8927"  # Required for Sendspin');
    } else if (!hasProxy) {
      // MA 2.7.x without built-in proxy
      _logger.log('ℹ️ MA $serverVersion does not have built-in /sendspin proxy');
      _logger.log('ℹ️ OPTIONS:');
      _logger.log('   1. Upgrade to Music Assistant 2.8.0+ (recommended)');
      _logger.log('   2. Or add reverse proxy config for /sendspin → port 8927');
      _logger.log('   Traefik: PathPrefix(`/sendspin`) → service port 8927');
      _logger.log('   Nginx: location /sendspin { proxy_pass http://ma:8927; }');
    } else {
      // MA 2.8.0+ but still failing
      _logger.log('ℹ️ MA $serverVersion should have /sendspin proxy');
      _logger.log('ℹ️ Check that your reverse proxy forwards WebSocket connections');
      _logger.log('   Ensure Upgrade and Connection headers are passed through');
    }
  }

  /// Handle Sendspin play command
  void _handleSendspinPlay(String streamUrl, Map<String, dynamic> trackInfo) async {
    _logger.log('🎵 Sendspin: Play command received');

    try {
      // Build full URL if needed
      String fullUrl = streamUrl;
      if (!streamUrl.startsWith('http') && _serverUrl != null) {
        var baseUrl = _serverUrl!;
        if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
          baseUrl = 'https://$baseUrl';
        }
        baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final path = streamUrl.startsWith('/') ? streamUrl : '/$streamUrl';
        fullUrl = '$baseUrl$path';
      }

      // Extract metadata from track info
      final trackName = trackInfo['title'] as String? ?? trackInfo['name'] as String? ?? 'Unknown Track';
      final artistName = trackInfo['artist'] as String? ?? 'Unknown Artist';
      final albumName = trackInfo['album'] as String?;
      var artworkUrl = trackInfo['image_url'] as String? ?? trackInfo['artwork_url'] as String?;
      final durationSecs = trackInfo['duration'] as int?;

      if (artworkUrl != null && artworkUrl.startsWith('http://')) {
        artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
      }

      final metadata = TrackMetadata(
        title: trackName,
        artist: artistName,
        album: albumName,
        artworkUrl: artworkUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      _localPlayer.setCurrentTrackMetadata(metadata);
      _currentNotificationMetadata = metadata;

      await _localPlayer.playUrl(fullUrl);

      // Report state back to MA
      _sendspinService?.reportState(playing: true, paused: false);
    } catch (e) {
      _logger.log('❌ Sendspin: Error handling play command: $e');
    }
  }

  /// Handle Sendspin pause command
  void _handleSendspinPause() async {
    _logger.log('⏸️ Sendspin: Pause command received');
    // Pause both players - PCM for raw streaming, local for URL-based
    await _pcmAudioPlayer?.pause();
    await _localPlayer.pause();
    _sendspinService?.reportState(playing: false, paused: true);
  }

  /// Handle Sendspin stop command
  void _handleSendspinStop() async {
    _logger.log('⏹️ Sendspin: Stop command received');
    // Stop both players - PCM for raw streaming, local for URL-based
    await _pcmAudioPlayer?.stop();
    await _localPlayer.stop();
    _sendspinService?.reportState(playing: false, paused: false);
  }

  /// Handle Sendspin seek command
  void _handleSendspinSeek(int positionSeconds) async {
    _logger.log('⏩ Sendspin: Seek to $positionSeconds seconds');
    await _localPlayer.seek(Duration(seconds: positionSeconds));
    _sendspinService?.reportState(position: positionSeconds);
  }

  /// Handle Sendspin volume command
  void _handleSendspinVolume(int volumeLevel) async {
    _logger.log('🔊 Sendspin: Set volume to $volumeLevel');
    _localPlayerVolume = volumeLevel;
    await FlutterVolumeController.setVolume(volumeLevel / 100.0);
    _sendspinService?.reportState(volume: volumeLevel);
  }

  /// Handle Sendspin stream start - server is about to send PCM audio data
  /// This is called when audio streaming begins, before any audio frames arrive.
  /// We use this to:
  /// 1. Ensure PCM player is ready
  /// 2. Start the foreground service to prevent background throttling
  /// 3. Reset position for new track and start position timer
  void _handleSendspinStreamStart(Map<String, dynamic>? trackInfo) async {
    _logger.log('🎵 Sendspin: Stream starting');

    // Ensure PCM player is initialized and ready
    if (_pcmAudioPlayer == null || _pcmAudioPlayer!.state == PcmPlayerState.idle) {
      _logger.log('🎵 Sendspin: Reinitializing PCM player for stream');
      _pcmAudioPlayer?.dispose();
      _pcmAudioPlayer = PcmAudioPlayer();
      final initialized = await _pcmAudioPlayer!.initialize();
      if (initialized) {
        await _pcmAudioPlayer!.connectToStream(_sendspinService!.audioDataStream);
      } else {
        _logger.log('⚠️ Sendspin: Failed to initialize PCM player');
        return;
      }
    }

    // CRITICAL: Reset paused state when stream starts
    // This clears _isPausePending and sets state to playing
    // so that _onAudioData will process incoming audio
    await _pcmAudioPlayer!.play();

    // Reset position for new stream (new track)
    _pcmAudioPlayer!.resetPosition();

    // Extract track info for notification
    String? title = trackInfo?['title'] as String? ?? trackInfo?['name'] as String?;
    String? artist = trackInfo?['artist'] as String?;
    String? album = trackInfo?['album'] as String?;
    String? artworkUrl = trackInfo?['image_url'] as String? ?? trackInfo?['artwork_url'] as String?;
    int? durationSecs = trackInfo?['duration'] as int?;

    // If no track info in stream/start, try to get from cached notification metadata
    if (title == null && _currentNotificationMetadata != null) {
      title = _currentNotificationMetadata!.title;
      artist = _currentNotificationMetadata!.artist;
      album = _currentNotificationMetadata!.album;
      artworkUrl = _currentNotificationMetadata!.artworkUrl;
      durationSecs = _currentNotificationMetadata!.duration?.inSeconds;
    }

    // Keep the foreground service active to prevent Android from throttling
    // the PCM audio playback when the app goes to background.
    // We use setRemotePlaybackState to maintain the notification without
    // actually playing audio through just_audio.
    final mediaItem = audio_service.MediaItem(
      id: 'sendspin_pcm_stream',
      title: title ?? 'Playing via Sendspin',
      artist: artist ?? 'Music Assistant',
      album: album,
      artUri: artworkUrl != null ? Uri.parse(artworkUrl) : null,
      duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
    );

    // Initialize notification with position 0
    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: true,
      position: Duration.zero,
      duration: mediaItem.duration,
    );

    // Start notification position timer for Sendspin PCM
    _manageNotificationPositionTimer();

    _logger.log('🎵 Sendspin: Foreground service activated for PCM streaming');
  }

  /// Handle Sendspin stream end - server stopped sending PCM audio data
  /// This is called when audio streaming ends (pause, stop, track end, etc.)
  void _handleSendspinStreamEnd() async {
    // Capture current position before stopping
    final lastPosition = _pcmAudioPlayer?.elapsedTime ?? Duration.zero;
    _logger.log('🎵 Sendspin: Stream ended at position ${lastPosition.inSeconds}s');

    // Stop notification position timer
    _notificationPositionTimer?.cancel();

    // Pause PCM playback (preserves position) instead of stop (resets position)
    await _pcmAudioPlayer?.pause();

    // Update foreground service to show paused/stopped state with last position
    // Don't completely clear it - keep showing the notification
    // in case user wants to resume
    final metadata = _currentNotificationMetadata;
    final mediaItem = audio_service.MediaItem(
      id: 'sendspin_pcm_stream',
      title: metadata?.title ?? 'Music Assistant',
      artist: metadata?.artist ?? 'Paused',
      album: metadata?.album,
      artUri: metadata?.artworkUrl != null ? Uri.parse(metadata!.artworkUrl!) : null,
      duration: metadata?.duration,
    );

    // Show paused state with preserved position
    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: false,
      position: lastPosition,
      duration: mediaItem.duration,
    );
  }

  void _startReportingLocalPlayerState() {
    _localPlayerStateReportTimer?.cancel();
    _localPlayerStateReportTimer = Timer.periodic(Timings.localPlayerReportInterval, (_) async {
      try {
        await _reportLocalPlayerState();
      } catch (e) {
        _logger.log('Error reporting local player state (will retry): $e');
      }
    });
  }

  Future<void> _reportLocalPlayerState() async {
    if (_api == null) return;

    // Don't try to report state if not authenticated - avoids spamming errors
    if (_api!.currentConnectionState != MAConnectionState.authenticated) return;

    final playerId = await SettingsService.getBuiltinPlayerId();
    if (playerId == null) return;

    final isPlaying = _localPlayer.isPlaying;
    final position = _localPlayer.position.inSeconds;
    // Use tracked MA volume instead of just_audio player volume
    // just_audio volume is for local playback, MA volume is for server sync
    final volume = _localPlayerVolume;
    final isPaused = !isPlaying && position > 0;

    // Report via Sendspin if connected (MA 2.7.0b20+)
    if (_sendspinConnected && _sendspinService != null) {
      _sendspinService!.reportState(
        powered: _isLocalPlayerPowered,
        playing: isPlaying,
        paused: isPaused,
        position: position,
        volume: volume,
        muted: _localPlayerVolume == 0,
      );
      return;
    }

    // Otherwise use builtin_player API (older MA versions)
    if (!_builtinPlayerAvailable) return;

    await _api!.updateBuiltinPlayerState(
      playerId,
      powered: _isLocalPlayerPowered,
      playing: isPlaying,
      paused: isPaused,
      position: position,
      volume: volume,
      muted: _localPlayerVolume == 0,
    );
  }

  Future<void> _handleLocalPlayerEvent(Map<String, dynamic> event) async {
    _logger.log('📥 Local player event received: ${event['type'] ?? event['command']}');

    try {
      final eventPlayerId = event['player_id'] as String?;
      final myPlayerId = await SettingsService.getBuiltinPlayerId();

      if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
        _logger.log('🚫 Ignoring event for different player: $eventPlayerId (my player: $myPlayerId)');
        return;
      }

      final command = (event['type'] as String?) ?? (event['command'] as String?);

      switch (command) {
        case 'play_media':
          final urlPath = event['media_url'] as String? ?? event['url'] as String?;

          _logger.log('🎵 play_media: urlPath=$urlPath, _serverUrl=$_serverUrl');

          if (urlPath != null && _serverUrl != null) {
            String fullUrl;
            if (urlPath.startsWith('http')) {
              fullUrl = urlPath;
            } else {
              var baseUrl = _serverUrl!;
              if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                baseUrl = 'https://$baseUrl';
              }
              baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
              final path = urlPath.startsWith('/') ? urlPath : '/$urlPath';
              fullUrl = '$baseUrl$path';
            }

            TrackMetadata metadata;
            if (_pendingTrackMetadata != null) {
              metadata = _pendingTrackMetadata!;
              _logger.log('🎵 Using metadata from player_updated: ${metadata.title} by ${metadata.artist}');
            } else {
              final trackName = event['track_name'] as String? ?? event['name'] as String? ?? 'Unknown Track';
              final artistName = event['artist_name'] as String? ?? event['artist'] as String? ?? 'Unknown Artist';
              final albumName = event['album_name'] as String? ?? event['album'] as String?;
              var artworkUrl = event['image_url'] as String? ?? event['artwork_url'] as String?;
              final durationSecs = event['duration'] as int?;

              if (artworkUrl != null && artworkUrl.startsWith('http://')) {
                artworkUrl = artworkUrl.replaceFirst('http://', 'https://');
              }

              metadata = TrackMetadata(
                title: trackName,
                artist: artistName,
                album: albumName,
                artworkUrl: artworkUrl,
                duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
              );
            }

            _localPlayer.setCurrentTrackMetadata(metadata);
            _currentNotificationMetadata = metadata;

            await _localPlayer.playUrl(fullUrl);
          }
          break;

        case 'stop':
          await _localPlayer.stop();
          break;

        case 'pause':
          await _localPlayer.pause();
          break;

        case 'play':
          await _localPlayer.play();
          break;

        case 'seek':
          final position = event['position'] as int?;
          if (position != null) {
            await _localPlayer.seek(Duration(seconds: position));
          }
          break;

        case 'volume_set':
        case 'set_volume':
          final volume = event['volume_level'] as int? ?? event['volume'] as int?;
          if (volume != null) {
            _localPlayerVolume = volume;
            await FlutterVolumeController.setVolume(volume / 100.0);
          }
          break;

        case 'power_on':
        case 'power_off':
        case 'power':
          _logger.log('🔋 POWER COMMAND RECEIVED: $command');

          bool? newPowerState;
          if (command == 'power_on') {
            newPowerState = true;
          } else if (command == 'power_off') {
            newPowerState = false;
          } else {
            newPowerState = event['powered'] as bool?;
          }

          if (newPowerState != null) {
            _isLocalPlayerPowered = newPowerState;
            _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');
            if (!_isLocalPlayerPowered) {
              _logger.log('🔋 Stopping playback because powered off');
              await _localPlayer.stop();
            }
          }
          break;
      }

      await _reportLocalPlayerState();
    } catch (e) {
      _logger.log('Error handling local player event: $e');
    }
  }

  /// Handle player_added event - refresh player list when new players join
  Future<void> _handlePlayerAddedEvent(Map<String, dynamic> event) async {
    try {
      final playerId = event['player_id'] as String?;
      final playerName = event['name'] as String?;
      _logger.log('🆕 Player added: $playerName ($playerId)');

      // Refresh the player list to include the new player
      await _loadAndSelectPlayers(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      _logger.log('Error handling player added event: $e');
    }
  }

  Future<void> _handlePlayerUpdatedEvent(Map<String, dynamic> event) async {
    try {
      final playerId = event['player_id'] as String?;
      if (playerId == null) return;

      if (_selectedPlayer != null && playerId == _selectedPlayer!.playerId) {
        _updatePlayerState();
      }

      final currentMedia = event['current_media'] as Map<String, dynamic>?;
      final playerName = event['name'] as String? ?? playerId;

      if (currentMedia != null) {
        final mediaType = currentMedia['media_type'] as String?;

        // Clear audiobook context when switching to music (track) playback
        if (mediaType == 'track' && _currentAudiobook != null) {
          _logger.log('📚 Media type changed to track - clearing audiobook context');
          clearCurrentAudiobook();
        }

        if (mediaType != 'flow_stream') {
          final durationSecs = (currentMedia['duration'] as num?)?.toInt();
          final albumName = currentMedia['album'] as String?;
          final imageUrl = currentMedia['image_url'] as String?;

          Map<String, dynamic>? metadata;
          if (imageUrl != null) {
            var finalImageUrl = imageUrl;
            if (_serverUrl != null) {
              try {
                final imgUri = Uri.parse(imageUrl);
                final queryString = imgUri.query;
                var baseUrl = _serverUrl!;
                if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
                  baseUrl = 'https://$baseUrl';
                }
                if (baseUrl.endsWith('/')) {
                  baseUrl = baseUrl.substring(0, baseUrl.length - 1);
                }
                finalImageUrl = '$baseUrl/imageproxy?$queryString';
              } catch (e) {
                // Use original URL
              }
            }
            metadata = {
              'images': [
                {'path': finalImageUrl, 'provider': 'direct'}
              ]
            };
          }

          // Parse artist from title if artist is missing but title contains " - "
          var trackTitle = currentMedia['title'] as String? ?? 'Unknown Track';
          var artistName = currentMedia['artist'] as String?;

          if ((artistName == null || artistName == 'Unknown Artist') && trackTitle.contains(' - ')) {
            final parts = trackTitle.split(' - ');
            if (parts.length >= 2) {
              artistName = parts[0].trim();
              trackTitle = parts.sublist(1).join(' - ').trim();
            }
          }
          artistName ??= 'Unknown Artist';

          final trackFromEvent = Track(
            itemId: currentMedia['queue_item_id'] as String? ?? '',
            provider: 'library',
            name: trackTitle,
            uri: currentMedia['uri'] as String?,
            duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
            artists: [Artist(itemId: '', provider: 'library', name: artistName)],
            album: albumName != null ? Album(itemId: '', provider: 'library', name: albumName) : null,
            metadata: metadata,
          );

          // Only cache if we don't already have better data from queue
          final existingTrack = _cacheService.getCachedTrackForPlayer(playerId);
          final existingHasProperArtist = existingTrack != null &&
              existingTrack.artistsString != 'Unknown Artist' &&
              !existingTrack.name.contains(' - ');
          final existingHasImage = existingTrack?.metadata?['images'] != null;
          final newHasImage = metadata != null;

          // Keep existing if it has proper artist OR has image that new one lacks
          final keepExisting = existingHasProperArtist || (existingHasImage && !newHasImage);

          if (!keepExisting) {
            _cacheService.setCachedTrackForPlayer(playerId, trackFromEvent);
            _logger.log('📋 Cached track for $playerName from player_updated: ${trackFromEvent.name}');
          } else {
            _logger.log('📋 Skipped caching for $playerName - already have better data (artist: $existingHasProperArtist, image: $existingHasImage)');
          }

          // For selected player, _updatePlayerState() is already called above which fetches queue data
          // Only update _currentTrack here if we don't have it yet (initial load)
          if (_selectedPlayer != null && playerId == _selectedPlayer!.playerId && _currentTrack == null) {
            _currentTrack = trackFromEvent;
          }

          notifyListeners();
        }
      }

      // Handle notification metadata for local player
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId == null) return;

      if (playerId != builtinPlayerId) return;

      if (currentMedia == null) return;

      final title = currentMedia['title'] as String? ?? 'Unknown Track';
      final artist = currentMedia['artist'] as String? ?? 'Unknown Artist';
      final album = currentMedia['album'] as String?;
      var imageUrl = currentMedia['image_url'] as String?;
      final durationSecs = (currentMedia['duration'] as num?)?.toInt();

      if (imageUrl != null && _serverUrl != null) {
        try {
          final imgUri = Uri.parse(imageUrl);
          final queryString = imgUri.query;
          var baseUrl = _serverUrl!;
          if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
            baseUrl = 'https://$baseUrl';
          }
          if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length - 1);
          }
          imageUrl = '$baseUrl/imageproxy?$queryString';
        } catch (e) {
          if (imageUrl != null && imageUrl.startsWith('http://')) {
            imageUrl = imageUrl.replaceFirst('http://', 'https://');
          }
        }
      }

      final newMetadata = TrackMetadata(
        title: title,
        artist: artist,
        album: album,
        artworkUrl: imageUrl,
        duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      );

      final mediaType = currentMedia['media_type'] as String?;
      if (mediaType == 'flow_stream') return;

      _pendingTrackMetadata = newMetadata;
      _logger.log('📋 Captured track metadata from player_updated: $title by $artist');

      final notificationNeedsUpdate = _currentNotificationMetadata != null &&
          (_currentNotificationMetadata!.title != title ||
           _currentNotificationMetadata!.artist != artist);

      if (_localPlayer.isPlaying && notificationNeedsUpdate) {
        _logger.log('📋 Notification has stale metadata - updating to: $title by $artist');
        await _localPlayer.updateNotificationWhilePlaying(newMetadata);
        _currentNotificationMetadata = newMetadata;
      }
    } catch (e) {
      _logger.log('Error handling player_updated event: $e');
    }
  }

  // ============================================================================
  // SEARCH STATE
  // ============================================================================

  void saveSearchState(String query, Map<String, List<MediaItem>> results) {
    _lastSearchQuery = query;
    _lastSearchResults = results;
  }

  void clearSearchState() {
    _lastSearchQuery = '';
    _lastSearchResults = {'artists': [], 'albums': [], 'tracks': []};
  }

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  Future<List<Album>> getRecentAlbumsWithCache({bool forceRefresh = false}) async {
    // Always fetch from API to ensure we have full album data with images
    // Local/cached data is used by getCachedRecentAlbums() for instant display
    if (_api == null) {
      // Fallback when offline: try memory cache, then local database
      final cached = _cacheService.getCachedRecentAlbums();
      if (cached != null && cached.isNotEmpty) return cached;
      return RecentlyPlayedService.instance.getRecentAlbums(
        limit: LibraryConstants.defaultRecentLimit,
      );
    }

    try {
      _logger.log('🔄 Fetching fresh recent albums from MA...');
      final albums = await _api!.getRecentAlbums(limit: LibraryConstants.defaultRecentLimit);
      _cacheService.setCachedRecentAlbums(albums);
      return albums;
    } catch (e) {
      _logger.log('❌ Failed to fetch recent albums: $e');
      // Fallback on error: try memory cache, then local database
      final cached = _cacheService.getCachedRecentAlbums();
      if (cached != null && cached.isNotEmpty) return cached;
      return RecentlyPlayedService.instance.getRecentAlbums(
        limit: LibraryConstants.defaultRecentLimit,
      );
    }
  }

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

  void invalidateHomeCache() {
    _cacheService.invalidateHomeCache();
  }

  /// Get cached recent albums synchronously (for instant display)
  List<Album>? getCachedRecentAlbums() => _cacheService.getCachedRecentAlbums();

  /// Get cached discover artists synchronously (for instant display)
  List<Artist>? getCachedDiscoverArtists() => _cacheService.getCachedDiscoverArtists();

  /// Get cached discover albums synchronously (for instant display)
  List<Album>? getCachedDiscoverAlbums() => _cacheService.getCachedDiscoverAlbums();

  /// Force a full library sync (for pull-to-refresh)
  Future<void> forceLibrarySync() async {
    if (_api == null) return;

    _logger.log('🔄 Forcing full library sync...');
    await SyncService.instance.forceSync(_api!);

    // Update local lists from sync result
    _albums = SyncService.instance.cachedAlbums;
    _artists = SyncService.instance.cachedArtists;

    // Also refresh tracks from API
    try {
      _tracks = await _api!.getTracks(limit: LibraryConstants.maxLibraryItems);
    } catch (e) {
      _logger.log('⚠️ Failed to refresh tracks: $e');
    }

    notifyListeners();
    _logger.log('✅ Force sync complete');
  }

  // ============================================================================
  // FAVORITES FOR HOME SCREEN
  // ============================================================================

  /// Get favorite albums from the library
  Future<List<Album>> getFavoriteAlbums() async {
    // Filter from loaded library - favorites are already loaded
    return _albums.where((a) => a.favorite == true).toList();
  }

  /// Get favorite artists from the library
  Future<List<Artist>> getFavoriteArtists() async {
    // Filter from loaded library - favorites are already loaded
    return _artists.where((a) => a.favorite == true).toList();
  }

  /// Get favorite tracks from the library
  Future<List<Track>> getFavoriteTracks() async {
    // Filter from loaded library - favorites are already loaded
    return _tracks.where((t) => t.favorite == true).toList();
  }

  // ============================================================================
  // AUDIOBOOK HOME SCREEN ROWS
  // ============================================================================

  /// Get audiobooks that have progress (continue listening)
  Future<List<Audiobook>> getInProgressAudiobooks() async {
    if (_api == null) return [];

    try {
      _logger.log('📚 Fetching in-progress audiobooks...');
      final allAudiobooks = await _api!.getAudiobooks();
      // Filter to only those with progress, sorted by most recent/highest progress
      final inProgress = allAudiobooks
          .where((a) => a.progress > 0 && a.progress < 1.0) // Has progress but not complete
          .toList()
        ..sort((a, b) => b.progress.compareTo(a.progress)); // Sort by progress descending
      _logger.log('📚 Found ${inProgress.length} in-progress audiobooks');
      return inProgress.take(20).toList(); // Limit to 20 for home row
    } catch (e) {
      _logger.log('❌ Failed to fetch in-progress audiobooks: $e');
      return [];
    }
  }

  /// Get random audiobooks for discovery
  Future<List<Audiobook>> getDiscoverAudiobooks() async {
    if (_api == null) return [];

    try {
      _logger.log('📚 Fetching discover audiobooks...');
      final allAudiobooks = await _api!.getAudiobooks();
      // Shuffle and take a subset
      final shuffled = List<Audiobook>.from(allAudiobooks)..shuffle();
      _logger.log('📚 Found ${allAudiobooks.length} total audiobooks, returning random selection');
      return shuffled.take(20).toList();
    } catch (e) {
      _logger.log('❌ Failed to fetch discover audiobooks: $e');
      return [];
    }
  }

  /// Get random series for discovery
  Future<List<AudiobookSeries>> getDiscoverSeries() async {
    if (_api == null) return [];

    try {
      _logger.log('📚 Fetching discover series...');
      final allSeries = await _api!.getAudiobookSeries();
      // Shuffle and take a subset
      final shuffled = List<AudiobookSeries>.from(allSeries)..shuffle();
      _logger.log('📚 Found ${allSeries.length} total series, returning random selection');
      return shuffled.take(20).toList();
    } catch (e) {
      _logger.log('❌ Failed to fetch discover series: $e');
      return [];
    }
  }

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

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

  Future<List<Album>> getArtistAlbumsWithCache(String artistName, {bool forceRefresh = false}) async {
    final cacheKey = artistName.toLowerCase();

    if (_cacheService.isArtistAlbumsCacheValid(cacheKey, forceRefresh: forceRefresh)) {
      _logger.log('📦 Using cached artist albums for "$artistName"');
      return _cacheService.getCachedArtistAlbums(cacheKey)!;
    }

    if (_api == null) return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];

    try {
      _logger.log('🔄 Fetching albums for artist "$artistName"...');

      // Fetch all library albums (with high limit to get full library)
      final libraryAlbums = await _api!.getAlbums(limit: LibraryConstants.maxLibraryItems);
      _logger.log('📚 Fetched ${libraryAlbums.length} total library albums');
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
      _logger.log('✅ Cached ${allAlbums.length} albums for artist "$artistName"');
      return allAlbums;
    } catch (e) {
      _logger.log('❌ Failed to fetch artist albums: $e');
      return _cacheService.getCachedArtistAlbums(cacheKey) ?? [];
    }
  }

  void invalidateAlbumTracksCache(String albumId) {
    _cacheService.invalidateAlbumTracksCache(albumId);
  }

  void invalidatePlaylistTracksCache(String playlistId) {
    _cacheService.invalidatePlaylistTracksCache(playlistId);
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

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
      _logger.log('✅ Cached search results for "$query"');
      return cachedResults;
    } catch (e) {
      _logger.log('❌ Search failed: $e');
      return _cacheService.getCachedSearchResults(cacheKey) ?? {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  void clearAllDetailCaches() {
    _cacheService.clearAllDetailCaches();
  }

  /// Get cached album tracks (for instant display before background refresh)
  List<Track>? getCachedAlbumTracks(String cacheKey) {
    return _cacheService.getCachedAlbumTracks(cacheKey);
  }

  /// Get cached playlist tracks (for instant display before background refresh)
  List<Track>? getCachedPlaylistTracks(String cacheKey) {
    return _cacheService.getCachedPlaylistTracks(cacheKey);
  }

  /// Get cached artist albums (for instant display before background refresh)
  List<Album>? getCachedArtistAlbums(String artistName) {
    return _cacheService.getCachedArtistAlbums(artistName.toLowerCase());
  }

  // ============================================================================
  // PLAYER SELECTION
  // ============================================================================

  Future<List<Player>> getAllPlayersUnfiltered() async {
    return await getPlayers();
  }

  Future<String?> getCurrentPlayerId() async {
    return await SettingsService.getBuiltinPlayerId();
  }

  Future<void> _loadAndSelectPlayers({bool forceRefresh = false}) async {
    try {
      if (!forceRefresh &&
          _cacheService.isPlayersCacheValid() &&
          _availablePlayers.isNotEmpty) {
        return;
      }

      final allPlayers = await getPlayers();
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      _logger.log('🎛️ getPlayers returned ${allPlayers.length} players:');

      int filteredCount = 0;

      _availablePlayers = allPlayers.where((player) {
        final nameLower = player.name.toLowerCase();

        if (nameLower.contains('music assistant mobile')) {
          filteredCount++;
          return false;
        }

        // Filter out MA Web UI's built-in player (provider is 'builtin_player' and starts with 'ma_')
        // Note: We check BOTH conditions to avoid filtering snapcast/other players that may have 'ma_' prefix
        if (player.provider == 'builtin_player' && player.playerId.startsWith('ma_')) {
          _logger.log('🚫 Filtering out MA Web UI player: ${player.name} (provider: ${player.provider}, id: ${player.playerId})');
          filteredCount++;
          return false;
        }

        // Also filter "This Device" named players without proper provider
        if (nameLower == 'this device') {
          _logger.log('🚫 Filtering out "This Device" player: ${player.name}');
          filteredCount++;
          return false;
        }

        if (player.playerId.startsWith('ensemble_')) {
          if (builtinPlayerId == null || player.playerId != builtinPlayerId) {
            _logger.log('🚫 Filtering out other device\'s player: ${player.name}');
            filteredCount++;
            return false;
          }
        }

        if (!player.available) {
          if (builtinPlayerId != null && player.playerId == builtinPlayerId) {
            return true;
          }
          filteredCount++;
          return false;
        }

        return true;
      }).toList();

      // Smart Sendspin/Cast player switching:
      // - When grouped: show Sendspin version (renamed), hide original Cast
      // - When ungrouped: show original Cast, hide Sendspin version
      // This gives power control and proper queue behavior when not syncing
      final sendspinSuffix = ' (Sendspin)';
      final sendspinPlayers = _availablePlayers
          .where((p) => p.name.endsWith(sendspinSuffix))
          .toList();

      // NOTE: Don't clear _castToSendspinIdMap - we want to remember mappings
      // even when the Sendspin player is temporarily unavailable (e.g., device off)
      // This allows syncing to work when the device powers back on

      if (sendspinPlayers.isNotEmpty) {
        // Build maps for Sendspin players and their grouped status
        final sendspinByBaseName = <String, Player>{};
        final groupedSendspinBaseNames = <String>{};

        for (final player in sendspinPlayers) {
          final baseName = player.name.substring(0, player.name.length - sendspinSuffix.length);
          sendspinByBaseName[baseName] = player;

          // Find the corresponding regular Cast player and store the ID mapping
          final regularCastPlayer = _availablePlayers.where(
            (p) => p.name == baseName && !p.name.endsWith(sendspinSuffix)
          ).firstOrNull;
          if (regularCastPlayer != null) {
            _castToSendspinIdMap[regularCastPlayer.playerId] = player.playerId;
            _logger.log('🔗 Mapped Cast ID ${regularCastPlayer.playerId} -> Sendspin ID ${player.playerId}');
          }

          if (player.isGrouped) {
            groupedSendspinBaseNames.add(baseName);
            _logger.log('🔊 Sendspin player "$baseName" is grouped - will prefer Sendspin version');
          } else {
            _logger.log('🔊 Sendspin player "$baseName" is ungrouped - will prefer original Cast');
          }
        }

        // Filter players based on grouped status
        _availablePlayers = _availablePlayers.where((player) {
          final isSendspin = player.name.endsWith(sendspinSuffix);

          if (isSendspin) {
            final baseName = player.name.substring(0, player.name.length - sendspinSuffix.length);
            // Keep Sendspin only if grouped
            if (player.isGrouped) {
              return true;
            } else {
              _logger.log('🚫 Hiding ungrouped Sendspin player: ${player.name}');
              filteredCount++;
              return false;
            }
          } else {
            // For regular players, hide if Sendspin version exists AND is grouped
            if (groupedSendspinBaseNames.contains(player.name)) {
              _logger.log('🚫 Preferring grouped Sendspin version over: ${player.name}');
              filteredCount++;
              return false;
            }
            return true;
          }
        }).toList();

        // Rename remaining Sendspin players to remove the suffix
        _availablePlayers = _availablePlayers.map((player) {
          if (player.name.endsWith(sendspinSuffix)) {
            final cleanName = player.name.substring(0, player.name.length - sendspinSuffix.length);
            _logger.log('✨ Renaming "${player.name}" to "$cleanName"');
            return player.copyWith(name: cleanName);
          }
          return player;
        }).toList();
      }

      // Sort players - check if smart sort is enabled
      final smartSort = await SettingsService.getSmartSortPlayers();
      if (smartSort) {
        // Smart sort: local player first, then playing, then on, then off
        _availablePlayers.sort((a, b) {
          // Local player always first
          final aIsLocal = builtinPlayerId != null && a.playerId == builtinPlayerId;
          final bIsLocal = builtinPlayerId != null && b.playerId == builtinPlayerId;
          if (aIsLocal && !bIsLocal) return -1;
          if (bIsLocal && !aIsLocal) return 1;

          // Then by status: playing > on > off
          int statusPriority(Player p) {
            if (p.state == 'playing') return 0;
            if (p.powered && p.state != 'off') return 1;
            return 2;
          }
          final aPriority = statusPriority(a);
          final bPriority = statusPriority(b);
          if (aPriority != bPriority) return aPriority.compareTo(bPriority);

          // Within same status, sort alphabetically
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      } else {
        // Default alphabetical sort
        _availablePlayers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      // Cache players for instant display on app resume
      _cacheService.setCachedPlayers(_availablePlayers);

      // Persist players to database for app restart persistence
      _persistPlayersToDatabase(_availablePlayers);

      _logger.log('🎛️ After filtering: ${_availablePlayers.length} players available');

      if (_availablePlayers.isNotEmpty) {
        Player? playerToSelect;
        final preferLocalPlayer = await SettingsService.getPreferLocalPlayer();
        final lastSelectedPlayerId = await SettingsService.getLastSelectedPlayerId();

        // If "Prefer Local Player" is ON, always try to select local player first
        // This takes priority even over the currently selected player
        if (preferLocalPlayer && builtinPlayerId != null) {
          try {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.playerId == builtinPlayerId && p.available,
            );
            _logger.log('📱 Auto-selected local player (preferred): ${playerToSelect?.name}');
          } catch (e) {
            // Local player not available yet, will fall through to other options
          }
        }

        // Keep currently selected player if still available (and not overridden by prefer local)
        // But allow switching to a playing player when preferLocalPlayer is OFF
        if (playerToSelect == null && _selectedPlayer != null) {
          final stillAvailable = _availablePlayers.any(
            (p) => p.playerId == _selectedPlayer!.playerId && p.available,
          );
          if (stillAvailable) {
            // If preferLocalPlayer is OFF, check if we should switch to a playing player
            if (!preferLocalPlayer) {
              final currentPlayerState = _availablePlayers
                  .firstWhere((p) => p.playerId == _selectedPlayer!.playerId)
                  .state;
              final currentIsPlaying = currentPlayerState == 'playing';
              final playingPlayers = _availablePlayers.where(
                (p) => p.state == 'playing' && p.available,
              ).toList();

              // Switch to playing player only if current isn't playing and exactly one other is
              if (!currentIsPlaying && playingPlayers.length == 1) {
                playerToSelect = playingPlayers.first;
                _logger.log('🎵 Switched to playing player: ${playerToSelect?.name}');
              }
            }

            // Keep current selection if no switch happened
            if (playerToSelect == null) {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == _selectedPlayer!.playerId,
              );
            }
          }
        }

        if (playerToSelect == null) {
          // Smart auto-selection priority:
          // If "Prefer Local Player" is OFF: Single playing player -> Local player -> Last selected -> First available

          if (!preferLocalPlayer) {
            // Priority 1 (normal): Single playing player (skip if multiple are playing)
            final playingPlayers = _availablePlayers.where(
              (p) => p.state == 'playing' && p.available,
            ).toList();
            if (playingPlayers.length == 1) {
              playerToSelect = playingPlayers.first;
              _logger.log('🎵 Auto-selected playing player: ${playerToSelect?.name}');
            }

            // Priority 2: Local player
            if (playerToSelect == null && builtinPlayerId != null) {
              try {
                playerToSelect = _availablePlayers.firstWhere(
                  (p) => p.playerId == builtinPlayerId && p.available,
                );
                _logger.log('📱 Auto-selected local player: ${playerToSelect?.name}');
              } catch (e) {}
            }
          }

          // Priority 3: Last manually selected player
          if (playerToSelect == null && lastSelectedPlayerId != null) {
            try {
              playerToSelect = _availablePlayers.firstWhere(
                (p) => p.playerId == lastSelectedPlayerId && p.available,
              );
              _logger.log('🔄 Auto-selected last used player: ${playerToSelect?.name}');
            } catch (e) {}
          }

          // Priority 4: First available player
          if (playerToSelect == null) {
            playerToSelect = _availablePlayers.firstWhere(
              (p) => p.available,
              orElse: () => _availablePlayers.first,
            );
          }
        }

        selectPlayer(playerToSelect);
      }

      // Preload track data and images in background for swipe gestures
      // Don't await - UI should show immediately with cached data
      unawaited(_preloadAdjacentPlayers(preloadAll: true));
    } catch (e) {
      ErrorHandler.logError('Load and select players', e);
    }
  }

  void selectPlayer(Player player, {bool skipNotify = false}) async {
    _selectedPlayer = player;

    // Cache for instant display on app resume
    _cacheService.setCachedSelectedPlayer(player);
    SettingsService.setLastSelectedPlayerId(player.playerId);

    // Immediately set currentTrack from cache to avoid flash during player switch
    // This ensures the UI shows the correct track info immediately, before
    // the async _updatePlayerState() completes.
    // IMPORTANT: Always set from cache, even if null - this prevents showing
    // stale track info when switching to a non-playing player.
    // For grouped child players, this returns the leader's track
    _currentTrack = getCachedTrackForPlayer(player.playerId);

    // Initialize position tracker for this player
    _positionTracker.onPlayerSelected(player.playerId);
    _positionTracker.updateFromServer(
      playerId: player.playerId,
      position: player.elapsedTime ?? 0.0,
      isPlaying: player.state == 'playing',
      duration: _currentTrack?.duration,
      serverTimestamp: player.elapsedTimeLastUpdated,
    );

    // Switch audio handler mode based on player type
    final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
    final isBuiltinPlayer = builtinPlayerId != null && player.playerId == builtinPlayerId;
    if (isBuiltinPlayer) {
      audioHandler.setLocalMode();
      // Update notification for builtin player using local mode method (keeps pause working)
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        final artistWithPlayer = track.artistsString.isNotEmpty
            ? '${track.artistsString} • ${player.name}'
            : player.name;
        final mediaItem = audio_service.MediaItem(
          id: track.uri ?? track.itemId,
          title: track.name,
          artist: artistWithPlayer,
          album: track.album?.name ?? '',
          duration: track.duration,
          artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
        );
        // Position comes from actual player in updateLocalModeNotification
        audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        // Builtin player active but no cached track - show player name placeholder
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        audioHandler.updateLocalModeNotification(
          item: mediaItem,
          playing: player.state == 'playing',
        );
      }
    } else {
      // For remote players, immediately show notification if we have cached track info
      // and the player is playing (don't wait for polling to kick in)
      if (_currentTrack != null && (player.state == 'playing' || player.state == 'paused')) {
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        // Include player name in artist line: "Artist • Player Name"
        final artistWithPlayer = track.artistsString.isNotEmpty
            ? '${track.artistsString} • ${player.name}'
            : player.name;
        final mediaItem = audio_service.MediaItem(
          id: track.uri ?? track.itemId,
          title: track.name,
          artist: artistWithPlayer,
          album: track.album?.name ?? '',
          duration: track.duration,
          artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
        );
        // Use position tracker for consistent position
        final position = _positionTracker.currentPosition;
        audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: track.duration,
        );
      } else if (player.state == 'playing' || player.state == 'paused') {
        // Player is active but no cached track - show player name placeholder
        // This prevents stale notification from previous player
        final mediaItem = audio_service.MediaItem(
          id: 'player_${player.playerId}',
          title: player.name,
          artist: 'Loading...',
        );
        final position = _positionTracker.currentPosition;
        audioHandler.setRemotePlaybackState(
          item: mediaItem,
          playing: player.state == 'playing',
          position: position,
          duration: Duration.zero,
        );
      }
    }

    _startPlayerStatePolling();

    // Start notification position timer for remote players
    _manageNotificationPositionTimer();

    _preloadAdjacentPlayers();

    // Immediately fetch fresh track data from queue to avoid showing stale cache
    // This is important when resuming app after being in background - cached data
    // from player_updated events may have incomplete artist info
    await _updatePlayerState();

    if (!skipNotify) {
      notifyListeners();
    }
  }

  /// Cycle to the next active player (for notification switch button)
  /// Only cycles through players that are currently playing or paused
  Future<void> selectNextPlayer() async {
    // If not connected yet (cold start), wait briefly for connection
    if (!isConnected) {
      _logger.log('🔄 Not connected yet, waiting for connection...');
      // Wait up to 3 seconds for connection to be established
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (isConnected) break;
      }
      if (!isConnected) {
        _logger.log('🔄 Still not connected, cannot switch player');
        return;
      }
    }

    // If players haven't loaded yet (cold start), try to load them first
    if (_availablePlayers.isEmpty && _api != null) {
      _logger.log('🔄 Players not loaded yet, loading...');
      await _loadAndSelectPlayers();
    }

    // Only include players that are available AND actively playing/paused
    // Always include the builtin player so user can switch to local device
    final activePlayers = _availablePlayers.where((p) =>
      p.available && (
        p.state == 'playing' ||
        p.state == 'paused' ||
        p.playerId.startsWith('ensemble_')  // Always include builtin player
      )
    ).toList();

    if (activePlayers.isEmpty) {
      _logger.log('🔄 No active players to switch to');
      return;
    }

    if (_selectedPlayer == null) {
      // If no player selected, select the first active one
      _logger.log('🔄 No player selected, selecting first active: ${activePlayers.first.name}');
      selectPlayer(activePlayers.first);
      return;
    }

    // Find current player in active list
    final currentIndex = activePlayers.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);

    // Calculate next index - if current isn't in active list, start at 0
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % activePlayers.length;
    final nextPlayer = activePlayers[nextIndex];

    _logger.log('🔄 Switching to next active player: ${nextPlayer.name} (${nextIndex + 1}/${activePlayers.length})');
    selectPlayer(nextPlayer);
  }

  /// Manage notification position timer for remote players and Sendspin PCM.
  /// This timer updates the notification position every second using interpolated time,
  /// making the progress bar smooth instead of jumping every 5 seconds (polling interval).
  void _manageNotificationPositionTimer() {
    _notificationPositionTimer?.cancel();

    if (_selectedPlayer == null || _currentTrack == null) return;

    // Check if this is a builtin/local player
    final playerId = _selectedPlayer!.playerId;
    if (playerId.startsWith('ensemble_')) {
      // This is a local player ID, but we need to check if it's using Sendspin PCM
      // Sendspin PCM needs the timer because flutter_pcm_sound doesn't broadcast position
      // just_audio (non-Sendspin) handles position automatically via native events
      if (!_sendspinConnected || _pcmAudioPlayer == null) {
        // True local player using just_audio - no timer needed
        return;
      }
      // Sendspin PCM player - continue to start timer
      _logger.log('🔔 Starting notification timer for Sendspin PCM player');
    }

    // Only run timer if player is playing
    if (_selectedPlayer!.state != 'playing') return;

    _notificationPositionTimer = Timer.periodic(
      const Duration(milliseconds: 500), // 500ms for smoother progress
      (_) => _updateNotificationPosition(),
    );
  }

  /// Update just the notification position (called every 500ms for remote/Sendspin players)
  void _updateNotificationPosition() {
    if (_selectedPlayer == null || _currentTrack == null) {
      _notificationPositionTimer?.cancel();
      return;
    }

    // Don't update if player is not playing
    if (_selectedPlayer!.state != 'playing') {
      _notificationPositionTimer?.cancel();
      return;
    }

    final track = _currentTrack!;
    Duration position;

    // For Sendspin PCM, use the PCM player's elapsed time (based on bytes played)
    // For remote players, use the position tracker (server-based interpolation)
    if (_sendspinConnected && _pcmAudioPlayer != null && _pcmAudioPlayer!.isPlaying) {
      position = _pcmAudioPlayer!.elapsedTime;

      // Check if track has ended based on PCM elapsed time
      if (track.duration != null && position >= track.duration!) {
        _logger.log('🔔 Sendspin: Track appears to have ended (position >= duration)');
        return;
      }
    } else {
      // Use position tracker for remote players
      position = _positionTracker.currentPosition;

      // Check if track has ended (position reached duration)
      if (_positionTracker.hasReachedEnd) {
        _logger.log('PositionTracker: Track appears to have ended (position >= duration)');
        return;
      }
    }

    final artworkUrl = _api?.getImageUrl(track, size: 512);
    final artistWithPlayer = track.artistsString.isNotEmpty
        ? '${track.artistsString} • ${_selectedPlayer!.name}'
        : _selectedPlayer!.name;
    final mediaItem = audio_service.MediaItem(
      id: track.uri ?? track.itemId,
      title: track.name,
      artist: artistWithPlayer,
      album: track.album?.name ?? '',
      duration: track.duration,
      artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
    );

    audioHandler.setRemotePlaybackState(
      item: mediaItem,
      playing: true,
      position: position,
      duration: track.duration,
    );
  }

  Future<void> _preloadAdjacentPlayers({bool preloadAll = false}) async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();
    if (players.isEmpty) return;

    if (preloadAll) {
      _logger.log('🖼️ Preloading track info for all ${players.length} players...');
      await Future.wait(
        players.map((player) => _preloadPlayerTrack(player)),
      );
      _logger.log('🖼️ Preloading complete');
      return;
    }

    if (_selectedPlayer == null) return;
    if (players.length <= 1) return;

    final currentIndex = players.indexWhere((p) => p.playerId == _selectedPlayer!.playerId);
    if (currentIndex == -1) return;

    final prevIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    final nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;

    final playersToPreload = <Player>{};
    if (prevIndex != currentIndex) playersToPreload.add(players[prevIndex]);
    if (nextIndex != currentIndex) playersToPreload.add(players[nextIndex]);

    // Await all preloads so images are ready for next swipe
    await Future.wait(
      playersToPreload.map((player) => _preloadPlayerTrack(player)),
    );
  }

  Future<void> _preloadPlayerTrack(Player player) async {
    if (_api == null) return;

    try {
      _logger.log('🔍 Preload ${player.name}: state=${player.state}, available=${player.available}');

      if (!player.available || !player.powered) {
        _logger.log('🔍 Preload ${player.name}: SKIPPED - not available or powered');
        _cacheService.setCachedTrackForPlayer(player.playerId, null);
        return;
      }

      final queue = await getQueue(player.playerId);
      _logger.log('🔍 Preload ${player.name}: queue=${queue != null}, currentItem=${queue?.currentItem != null}');

      if (queue != null && queue.currentItem != null) {
        final track = queue.currentItem!.track;

        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        final existingHasImage = existingTrack?.metadata?['images'] != null;
        final newHasImage = track.metadata?['images'] != null;

        if (existingHasImage && !newHasImage) {
          _logger.log('🔍 Preload ${player.name}: SKIPPED - keeping cached track with image');
        } else {
          _cacheService.setCachedTrackForPlayer(player.playerId, track);
          _logger.log('🔍 Preload ${player.name}: CACHED track "${track.name}"');

          // Also precache the image so it's ready for swipe preview
          final imageUrl = getImageUrl(track, size: 512);
          if (imageUrl != null) {
            _precacheImage(imageUrl);
          }
        }
      } else {
        _logger.log('🔍 Preload ${player.name}: NO TRACK - queue empty');
        final existingTrack = _cacheService.getCachedTrackForPlayer(player.playerId);
        if (existingTrack?.metadata?['images'] == null) {
          _cacheService.setCachedTrackForPlayer(player.playerId, null);
        }
      }
    } catch (e) {
      _logger.log('Error preloading player track for ${player.name}: $e');
    }
  }

  /// Precache an image URL so it loads instantly when displayed
  Future<void> _precacheImage(String url) async {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late ImageStreamListener listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) completer.complete();
          imageStream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) completer.completeError(exception);
          imageStream.removeListener(listener);
        },
      );

      imageStream.addListener(listener);
      await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
        imageStream.removeListener(listener);
      });
    } catch (e) {
      // Silently ignore precache errors - image will load on demand
    }
  }

  Future<void> preloadAllPlayerTracks() async {
    if (_api == null) return;

    final players = _availablePlayers.where((p) => p.available).toList();

    await Future.wait(
      players.map((player) => _preloadPlayerTrack(player)),
    );

    // After preloading, update _currentTrack from cache if it has better data
    // This fixes the issue where mini player shows wrong info but device list is correct
    // For grouped child players, this gets the leader's track
    if (_selectedPlayer != null && _currentTrack != null) {
      final cachedTrack = getCachedTrackForPlayer(_selectedPlayer!.playerId);
      if (cachedTrack != null && cachedTrack.uri == _currentTrack!.uri) {
        final cachedHasImage = cachedTrack.metadata?['images'] != null;
        final currentHasImage = _currentTrack!.metadata?['images'] != null;
        final cachedHasArtist = cachedTrack.artistsString.isNotEmpty &&
            cachedTrack.artistsString != 'Unknown Artist';
        final currentHasArtist = _currentTrack!.artistsString.isNotEmpty &&
            _currentTrack!.artistsString != 'Unknown Artist';

        if ((cachedHasImage && !currentHasImage) || (cachedHasArtist && !currentHasArtist)) {
          _currentTrack = cachedTrack;
          _logger.log('🎵 Updated currentTrack from cache with better metadata');
          notifyListeners();
        }
      }
    }
  }

  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();

    if (_selectedPlayer == null) return;

    _playerStateTimer = Timer.periodic(Timings.playerPollingInterval, (_) async {
      try {
        await _updatePlayerState();
      } catch (e) {
        _logger.log('Error updating player state (will retry): $e');
      }
    });

    _updatePlayerState();
  }

  Future<void> _updatePlayerState() async {
    if (_selectedPlayer == null || _api == null) return;

    try {
      bool stateChanged = false;

      final allPlayers = await getPlayers();
      final updatedPlayer = allPlayers.firstWhere(
        (p) => p.playerId == _selectedPlayer!.playerId,
        orElse: () => _selectedPlayer!,
      );

      _selectedPlayer = updatedPlayer;
      stateChanged = true;

      // Feed position tracker with server data
      // Log raw values to debug position issues
      final rawElapsedTime = updatedPlayer.elapsedTime;
      final rawTimestamp = updatedPlayer.elapsedTimeLastUpdated;
      if (rawElapsedTime == null) {
        _logger.log('⚠️ Player ${updatedPlayer.name} has null elapsedTime');
      }

      _positionTracker.updateFromServer(
        playerId: updatedPlayer.playerId,
        position: rawElapsedTime ?? 0.0,
        isPlaying: updatedPlayer.state == 'playing',
        duration: _currentTrack?.duration,
        serverTimestamp: rawTimestamp,
      );

      final isPlayingOrPaused = _selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused';
      final isIdleWithContent = _selectedPlayer!.state == 'idle' && _selectedPlayer!.powered;
      final shouldShowTrack = _selectedPlayer!.available && (isPlayingOrPaused || isIdleWithContent);

      if (!shouldShowTrack) {
        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
          // Persist cleared track state
          _persistPlaybackState();
        }
        // Clear audiobook context when playback stops
        if (_currentAudiobook != null) {
          _logger.log('📚 Playback stopped, clearing audiobook context');
          _currentAudiobook = null;
          stateChanged = true;
        }

        if (stateChanged) {
          notifyListeners();
        }
        return;
      }

      final queue = await getQueue(_selectedPlayer!.playerId);

      if (queue != null && queue.currentItem != null) {
        final queueTrack = queue.currentItem!.track;
        final trackChanged = _currentTrack == null ||
            _currentTrack!.uri != queueTrack.uri ||
            _currentTrack!.name != queueTrack.name;

        if (trackChanged) {
          // Check if cached track has better metadata (images, proper artist info)
          // This prevents losing album art and artist data when resuming the app
          // For grouped child players, this gets the leader's cached track
          final cachedTrack = getCachedTrackForPlayer(_selectedPlayer!.playerId);
          final cachedHasImage = cachedTrack?.metadata?['images'] != null;
          final queueHasImage = queueTrack.metadata?['images'] != null;
          // Also check for malformed artist names (e.g., "Artist - Title" format in name)
          final cachedHasProperArtist = cachedTrack?.artistsString.isNotEmpty == true &&
              cachedTrack?.artistsString != 'Unknown Artist' &&
              !cachedTrack!.name.contains(' - '); // Proper track doesn't have artist in name
          final queueHasProperArtist = queueTrack.artistsString.isNotEmpty &&
              queueTrack.artistsString != 'Unknown Artist' &&
              !queueTrack.name.contains(' - ');

          // Also check if _currentTrack (set from cache in selectPlayer) has good data
          final currentHasImage = _currentTrack?.metadata?['images'] != null;
          final currentHasProperArtist = _currentTrack?.artistsString.isNotEmpty == true &&
              _currentTrack?.artistsString != 'Unknown Artist' &&
              !(_currentTrack?.name.contains(' - ') ?? false);

          // Match by URI - name might differ if queue has malformed data
          final isSameTrackAsCached = cachedTrack?.uri == queueTrack.uri;
          final cachedHasBetterData = (cachedHasImage && !queueHasImage) ||
              (cachedHasProperArtist && !queueHasProperArtist);

          // Queue track has bad metadata if it lacks image AND lacks proper artist
          final queueHasBadMetadata = !queueHasImage && !queueHasProperArtist;
          // Current track (from cache at selectPlayer) has good metadata
          final currentHasGoodMetadata = currentHasImage || currentHasProperArtist;

          if (isSameTrackAsCached && cachedHasBetterData) {
            // Use cached track which has better metadata
            _currentTrack = cachedTrack;
            _logger.log('🎵 Using cached track with better metadata for ${cachedTrack!.name}');
          } else if (queueHasBadMetadata && currentHasGoodMetadata) {
            // Queue has bad data, but _currentTrack (set from cache) is good - keep it
            _logger.log('🎵 Keeping currentTrack - queue has bad metadata but current is good');
            // Don't change _currentTrack, keep the good data
          } else {
            _currentTrack = queueTrack;
            // Update cache if queue track has good metadata
            if (queueHasImage || queueHasProperArtist) {
              _cacheService.setCachedTrackForPlayer(_selectedPlayer!.playerId, queueTrack);
            }
          }
          stateChanged = true;

          // Persist the updated playback state to database for instant restore on next launch
          _persistPlaybackState();

          // Clear audiobook context if switched to a different media item
          // Check if the new track is from the same audiobook (by comparing URIs)
          if (_currentAudiobook != null) {
            final currentUri = _currentTrack!.uri ?? '';
            final audiobookUri = _currentAudiobook!.uri ?? 'library://audiobook/${_currentAudiobook!.itemId}';
            // The audiobook chapter URIs should contain the audiobook URI pattern
            if (!currentUri.contains(_currentAudiobook!.itemId) &&
                !currentUri.contains(audiobookUri)) {
              _logger.log('📚 Track changed to non-audiobook, clearing context');
              _currentAudiobook = null;
            }
          }
        }

        // Update notification for ALL players
        final track = _currentTrack!;
        final artworkUrl = _api?.getImageUrl(track, size: 512);
        final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
        final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;

        if (isBuiltinPlayer) {
          // Local playback - use local mode notification (keeps pause working)
          final artistWithPlayer = track.artistsString.isNotEmpty
              ? '${track.artistsString} • ${_selectedPlayer!.name}'
              : _selectedPlayer!.name;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: artistWithPlayer,
            album: track.album?.name ?? '',
            duration: track.duration,
            artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
          );
          // Position comes from actual player in updateLocalModeNotification
          audioHandler.updateLocalModeNotification(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
            duration: track.duration,
          );
        } else {
          // Remote MA player - show notification via remote mode
          // Include player name in artist line: "Artist • Player Name"
          final artistWithPlayer = track.artistsString.isNotEmpty
              ? '${track.artistsString} • ${_selectedPlayer!.name}'
              : _selectedPlayer!.name;
          final mediaItem = audio_service.MediaItem(
            id: track.uri ?? track.itemId,
            title: track.name,
            artist: artistWithPlayer,
            album: track.album?.name ?? '',
            duration: track.duration,
            artUri: artworkUrl != null ? Uri.tryParse(artworkUrl) : null,
          );
          // Use position tracker for consistent position (single source of truth)
          final position = _positionTracker.currentPosition;
          audioHandler.setRemotePlaybackState(
            item: mediaItem,
            playing: _selectedPlayer!.state == 'playing',
            position: position,
            duration: track.duration,
          );
        }
      } else {
        // No track data available - show player name placeholder for active players
        final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
        final isBuiltinPlayer = builtinPlayerId != null && _selectedPlayer!.playerId == builtinPlayerId;

        if (_currentTrack != null) {
          _currentTrack = null;
          stateChanged = true;
          // Persist cleared track state
          _persistPlaybackState();
        }

        // Show player name placeholder so notification shows correct player
        if (_selectedPlayer!.state == 'playing' || _selectedPlayer!.state == 'paused') {
          final mediaItem = audio_service.MediaItem(
            id: 'player_${_selectedPlayer!.playerId}',
            title: _selectedPlayer!.name,
            artist: 'No track info',
          );
          if (isBuiltinPlayer) {
            // Position comes from actual player in updateLocalModeNotification
            audioHandler.updateLocalModeNotification(
              item: mediaItem,
              playing: _selectedPlayer!.state == 'playing',
            );
          } else {
            final position = _positionTracker.currentPosition;
            audioHandler.setRemotePlaybackState(
              item: mediaItem,
              playing: _selectedPlayer!.state == 'playing',
              position: position,
              duration: Duration.zero,
            );
          }
        } else {
          audioHandler.clearRemotePlaybackState();
          _positionTracker.clear();
        }
      }

      // Manage notification position timer based on current player state
      _manageNotificationPositionTimer();

      if (stateChanged) {
        notifyListeners();
      }
    } catch (e) {
      _logger.log('❌ Error updating player state: $e');
    }
  }

  Future<void> playPauseSelectedPlayer() async {
    if (_selectedPlayer == null) return;

    final wasPlaying = _selectedPlayer!.isPlaying;

    if (wasPlaying) {
      await pausePlayer(_selectedPlayer!.playerId);
      // For pause: Don't refresh - we already did optimistic UI update
      // The player_updated event from MA will handle final state sync
    } else {
      await resumePlayer(_selectedPlayer!.playerId);
      // For resume: Refresh in background to get updated track info
      unawaited(refreshPlayers());
    }
  }

  Future<void> nextTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await nextTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> previousTrackSelectedPlayer() async {
    if (_selectedPlayer == null) return;
    await previousTrack(_selectedPlayer!.playerId);
    await Future.delayed(Timings.trackChangeDelay);
    await _updatePlayerState();
  }

  Future<void> refreshPlayers() async {
    final previousState = _selectedPlayer?.state;
    final previousVolume = _selectedPlayer?.volumeLevel;

    await _loadAndSelectPlayers(forceRefresh: true);

    bool stateChanged = false;
    if (_selectedPlayer != null && _availablePlayers.isNotEmpty) {
      try {
        final updatedPlayer = _availablePlayers.firstWhere(
          (p) => p.playerId == _selectedPlayer!.playerId,
        );

        if (updatedPlayer.state != previousState ||
            updatedPlayer.volumeLevel != previousVolume) {
          stateChanged = true;
        }

        _selectedPlayer = updatedPlayer;
      } catch (e) {
        stateChanged = true;
      }
    }

    if (stateChanged) {
      notifyListeners();
    }
  }

  // ============================================================================
  // LIBRARY DATA
  // ============================================================================

  Future<void> loadLibrary() async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;

      // Load from database cache first (instant)
      final syncService = SyncService.instance;
      if (syncService.hasCache) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('📦 Loaded ${_albums.length} albums, ${_artists.length} artists from cache');
        notifyListeners();
      }

      // Fetch tracks from API (not cached - too many items)
      if (_api != null) {
        try {
          _tracks = await _api!.getTracks(limit: LibraryConstants.maxLibraryItems);
          _logger.log('📥 Fetched ${_tracks.length} tracks from MA');
        } catch (e) {
          _logger.log('⚠️ Failed to fetch tracks: $e');
        }
      }

      _isLoading = false;
      notifyListeners();

      // Trigger background sync (non-blocking)
      if (_api != null) {
        _syncLibraryInBackground();
      }
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Load library');
      _error = errorInfo.userMessage;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sync library data in background without blocking UI
  Future<void> _syncLibraryInBackground() async {
    if (_api == null) return;

    final syncService = SyncService.instance;

    // Listen for sync completion to update our lists
    void onSyncComplete() {
      if (syncService.status == SyncStatus.completed) {
        _albums = syncService.cachedAlbums;
        _artists = syncService.cachedArtists;
        _logger.log('🔄 Updated library from background sync: ${_albums.length} albums, ${_artists.length} artists');
        notifyListeners();
      }
      syncService.removeListener(onSyncComplete);
    }

    syncService.addListener(onSyncComplete);
    await syncService.syncFromApi(_api!);
  }

  Future<void> loadArtists({int? limit, int? offset, String? search}) async {
    if (!isConnected) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _artists = await _api!.getArtists(
        limit: limit ?? LibraryConstants.maxLibraryItems,
        offset: offset,
        search: search,
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

  Future<void> loadAlbums({
    int? limit,
    int? offset,
    String? search,
    String? artistId,
  }) async {
    if (!isConnected) return;

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

  Future<List<Track>> getAlbumTracks(String provider, String itemId) async {
    if (!isConnected) return [];

    try {
      return await _api!.getAlbumTracks(provider, itemId);
    } catch (e) {
      ErrorHandler.logError('Get album tracks', e);
      return [];
    }
  }

  Future<Map<String, List<MediaItem>>> search(String query, {bool libraryOnly = false}) async {
    if (!isConnected) {
      return {'artists': [], 'albums': [], 'tracks': []};
    }

    try {
      return await _api!.search(query, libraryOnly: libraryOnly);
    } catch (e) {
      ErrorHandler.logError('Search', e);
      return {'artists': [], 'albums': [], 'tracks': []};
    }
  }

  String getStreamUrl(String provider, String itemId, {String? uri, List<ProviderMapping>? providerMappings}) {
    return _api?.getStreamUrl(provider, itemId, uri: uri, providerMappings: providerMappings) ?? '';
  }

  String? getImageUrl(MediaItem item, {int size = 256}) {
    return _api?.getImageUrl(item, size: size);
  }

  /// Get artist image URL with fallback to external sources (Deezer, Fanart.tv)
  /// Returns a Future since fallback requires async API calls
  Future<String?> getArtistImageUrlWithFallback(Artist artist, {int size = 256}) async {
    // Try Music Assistant first
    final maUrl = _api?.getImageUrl(artist, size: size);
    if (maUrl != null) {
      return maUrl;
    }

    // Fall back to external sources (Deezer, Fanart.tv, etc.)
    return MetadataService.getArtistImageUrl(artist.name);
  }

  // ============================================================================
  // PLAYER AND QUEUE MANAGEMENT
  // ============================================================================

  Future<List<Player>> getPlayers() async {
    return await _api?.getPlayers() ?? [];
  }

  Future<PlayerQueue?> getQueue(String playerId) async {
    // If this player is a group child, fetch the leader's queue instead
    // This ensures grouped players show the same queue as their leader
    String effectivePlayerId = playerId;
    final player = _availablePlayers.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => Player(
        playerId: playerId,
        name: '',
        available: false,
        powered: false,
        state: 'idle',
      ),
    );

    if (player.isGroupChild && player.syncedTo != null) {
      _logger.log('🔗 Player $playerId is grouped, fetching leader queue: ${player.syncedTo}');
      effectivePlayerId = player.syncedTo!;
    }

    final queue = await _api?.getQueue(effectivePlayerId);

    // Persist queue to database for instant display on app resume
    if (queue != null) {
      _persistQueueToDatabase(playerId, queue);
    }

    return queue;
  }

  /// Get cached queue for instant display (before API refresh)
  Future<PlayerQueue?> getCachedQueue(String playerId) async {
    try {
      if (!DatabaseService.instance.isInitialized) return null;

      final cachedItems = await DatabaseService.instance.getCachedQueue(playerId);
      if (cachedItems.isEmpty) return null;

      final items = <QueueItem>[];
      for (final cached in cachedItems) {
        try {
          final itemData = jsonDecode(cached.itemJson) as Map<String, dynamic>;
          items.add(QueueItem.fromJson(itemData));
        } catch (e) {
          _logger.log('⚠️ Error parsing cached queue item: $e');
        }
      }

      if (items.isEmpty) return null;

      return PlayerQueue(
        playerId: playerId,
        items: items,
        currentIndex: 0, // Will be updated from fresh data
      );
    } catch (e) {
      _logger.log('⚠️ Error loading cached queue: $e');
      return null;
    }
  }

  /// Persist queue to database for app restart persistence
  void _persistQueueToDatabase(String playerId, PlayerQueue queue) {
    () async {
      try {
        if (!DatabaseService.instance.isInitialized) return;

        final itemJsonList = queue.items.map((item) => jsonEncode(item.toJson())).toList();
        await DatabaseService.instance.saveQueue(playerId, itemJsonList);
        _logger.log('💾 Persisted ${queue.items.length} queue items to database');
      } catch (e) {
        _logger.log('⚠️ Error persisting queue to database: $e');
      }
    }();
  }

  Future<void> playTrack(String playerId, Track track, {bool clearQueue = true}) async {
    try {
      await _api?.playTrack(playerId, track, clearQueue: clearQueue);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play track');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play track', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playTracks(String playerId, List<Track> tracks, {int? startIndex, bool clearQueue = true}) async {
    try {
      await _api?.playTracks(playerId, tracks, startIndex: startIndex, clearQueue: clearQueue);

      final trackIndex = startIndex ?? 0;
      if (tracks.isNotEmpty && trackIndex < tracks.length) {
        _currentTrack = tracks[trackIndex];
        notifyListeners();
      }
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play tracks');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play tracks', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playRadio(String playerId, Track track) async {
    try {
      await _api?.playRadio(playerId, track);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> playArtistRadio(String playerId, Artist artist) async {
    try {
      await _api?.playArtistRadio(playerId, artist);
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Play artist radio');
      _error = errorInfo.userMessage;
      ErrorHandler.logError('Play artist radio', e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> getCurrentStreamUrl(String playerId) async {
    return await _api?.getCurrentStreamUrl(playerId);
  }

  Future<void> pausePlayer(String playerId) async {
    try {
      // Get builtin player ID - this is cached so should be fast
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();

      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏸️ Non-blocking local pause for builtin player');

        // CRITICAL: Don't await these - they can block the UI thread
        // Use unawaited to make them fire-and-forget
        unawaited(_pcmAudioPlayer?.pause() ?? Future.value());

        // Don't pause just_audio for Sendspin mode - it's not being used for audio output
        // and calling pause() on it can cause blocking issues
        // unawaited(_localPlayer.pause());

        // Report state to MA immediately (fire and forget)
        _sendspinService?.reportState(playing: false, paused: true);

        // Update local player state optimistically for UI responsiveness
        if (_selectedPlayer != null) {
          _selectedPlayer = _selectedPlayer!.copyWith(state: 'paused');
          notifyListeners();
        }
      }

      // Send command to MA for proper state sync - don't await
      unawaited(_api?.pausePlayer(playerId) ?? Future.value());
    } catch (e) {
      ErrorHandler.logError('Pause player', e);
      // Don't rethrow - we want pause to be resilient
    }
  }

  Future<void> resumePlayer(String playerId) async {
    try {
      // For resume, we let MA handle it since it needs to restart the stream
      // The stream_start event will trigger local playback
      await _api?.resumePlayer(playerId);
    } catch (e) {
      // Check if this is a "No playable item" error - means server queue is empty
      final errorStr = e.toString();
      if (errorStr.contains('No playable item')) {
        _logger.log('⚠️ Server queue empty - attempting to restore from cached queue...');

        // Try to restore queue from cached data
        final restored = await _restoreQueueFromCache(playerId);
        if (restored) {
          _logger.log('✅ Queue restored from cache - playback started');
          return; // Successfully restored and playing
        }
        _logger.log('❌ Could not restore queue from cache');
      }

      ErrorHandler.logError('Resume player', e);
      rethrow;
    }
  }

  /// Attempt to restore the queue from cached data and start playback
  Future<bool> _restoreQueueFromCache(String playerId) async {
    try {
      final cachedQueue = await getCachedQueue(playerId);
      if (cachedQueue == null || cachedQueue.items.isEmpty) {
        _logger.log('⚠️ No cached queue to restore');
        return false;
      }

      // Extract tracks from queue items
      // playTracks needs either: providerMappings with available entries, OR provider+itemId
      final tracks = cachedQueue.items
          .map((item) => item.track)
          .where((track) {
            // Check for providerMappings with at least one available entry
            if (track.providerMappings != null && track.providerMappings!.isNotEmpty) {
              return track.providerMappings!.any((m) => m.available);
            }
            // Fallback: provider + itemId can be used to construct URI
            return track.provider.isNotEmpty && track.itemId.isNotEmpty;
          })
          .toList();

      if (tracks.isEmpty) {
        _logger.log('⚠️ Cached queue has no valid tracks');
        return false;
      }

      _logger.log('🔄 Restoring ${tracks.length} tracks from cached queue');

      // Re-queue all tracks and start playback
      await playTracks(playerId, tracks, startIndex: 0);

      return true;
    } catch (e) {
      _logger.log('❌ Error restoring queue from cache: $e');
      return false;
    }
  }

  Future<void> nextTrack(String playerId) async {
    try {
      // Optimistic local stop for builtin player on skip - non-blocking
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏭️ Non-blocking local stop for skip on builtin player');
        // Stop current audio immediately - fire and forget
        unawaited(_pcmAudioPlayer?.pause() ?? Future.value());
        // Don't stop just_audio - not used for Sendspin audio output
      }
      await _api?.nextTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Next track', e);
      rethrow;
    }
  }

  Future<void> previousTrack(String playerId) async {
    try {
      // Optimistic local stop for builtin player on previous - non-blocking
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId && _sendspinConnected) {
        _logger.log('⏮️ Non-blocking local stop for previous on builtin player');
        // Stop current audio immediately - fire and forget
        unawaited(_pcmAudioPlayer?.pause() ?? Future.value());
        // Don't stop just_audio - not used for Sendspin audio output
      }
      await _api?.previousTrack(playerId);
    } catch (e) {
      ErrorHandler.logError('Previous track', e);
      rethrow;
    }
  }

  Future<void> stopPlayer(String playerId) async {
    try {
      await _api?.stopPlayer(playerId);
    } catch (e) {
      ErrorHandler.logError('Stop player', e);
      rethrow;
    }
  }

  /// Sync a player to the currently selected player (temporary group)
  /// The target player will play the same audio as the selected player
  Future<void> syncPlayerToSelected(String targetPlayerId) async {
    try {
      final leaderPlayer = _selectedPlayer;
      _logger.log('🔗 syncPlayerToSelected: target=$targetPlayerId, leader=${leaderPlayer?.playerId}');

      if (leaderPlayer == null) {
        _logger.log('❌ Cannot sync: no player selected');
        return;
      }

      if (targetPlayerId == leaderPlayer.playerId) {
        _logger.log('❌ Cannot sync player to itself');
        return;
      }

      if (_api == null) {
        _logger.log('❌ Cannot sync: API is null');
        return;
      }

      // Translate Cast player ID to Sendspin ID if available
      // This is needed because regular Cast players can't sync with Sendspin players
      final actualTargetId = _castToSendspinIdMap[targetPlayerId] ?? targetPlayerId;
      if (actualTargetId != targetPlayerId) {
        _logger.log('🔗 Translated Cast ID to Sendspin ID: $targetPlayerId -> $actualTargetId');
      }

      _logger.log('🔗 Calling API syncPlayerToLeader($actualTargetId, ${leaderPlayer.playerId})');
      await _api!.syncPlayerToLeader(actualTargetId, leaderPlayer.playerId);
      _logger.log('✅ API sync call completed');

      // Refresh players to get updated group state
      _logger.log('🔄 Refreshing players after sync...');
      await refreshPlayers();
      _logger.log('✅ Players refreshed');
    } catch (e) {
      _logger.log('❌ syncPlayerToSelected error: $e');
      ErrorHandler.logError('Sync player to selected', e);
      rethrow;
    }
  }

  /// Remove a player from its sync group
  Future<void> unsyncPlayer(String playerId) async {
    try {
      _logger.log('🔓 Unsyncing player: $playerId');
      await _api?.unsyncPlayer(playerId);

      // Refresh players to get updated group state
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Unsync player', e);
      rethrow;
    }
  }

  /// Toggle sync state: if player is synced, unsync it; otherwise sync to selected
  /// For Cast/Sendspin players that are powered off, powers on first then syncs
  Future<void> togglePlayerSync(String playerId) async {
    _logger.log('🔗 togglePlayerSync called for: $playerId');

    try {
      final player = _availablePlayers.firstWhere(
        (p) => p.playerId == playerId,
        orElse: () => throw Exception('Player not found'),
      );

      _logger.log('🔗 Player found: ${player.name}, isGrouped: ${player.isGrouped}');
      _logger.log('🔗 groupMembers: ${player.groupMembers}, syncedTo: ${player.syncedTo}');
      _logger.log('🔗 powered: ${player.powered}, available: ${player.available}');

      if (player.isGrouped) {
        _logger.log('🔓 Player is grouped, unsyncing...');
        await unsyncPlayer(playerId);
      } else {
        // Check if this is a Cast player with a Sendspin counterpart that's powered off
        final hasSendspinCounterpart = _castToSendspinIdMap.containsKey(playerId);

        if (hasSendspinCounterpart && !player.powered) {
          _logger.log('🔌 Cast/Sendspin player is off, powering on first...');

          // Power on the Cast player
          await _api?.setPower(playerId, true);

          // Wait for the player to power on and Sendspin to become ready
          _logger.log('🔗 Waiting for player to power on...');

          // Poll for up to 10 seconds for the player to be powered and available
          const maxAttempts = 20;
          const pollInterval = Duration(milliseconds: 500);

          for (var attempt = 0; attempt < maxAttempts; attempt++) {
            await Future.delayed(pollInterval);
            await refreshPlayers();

            // Check if the Cast player is now powered on
            final updatedPlayer = _availablePlayers.where(
              (p) => p.playerId == playerId
            ).firstOrNull;

            if (updatedPlayer != null && updatedPlayer.powered && updatedPlayer.available) {
              _logger.log('✅ Player powered on, syncing...');
              await syncPlayerToSelected(playerId);
              return;
            }

            _logger.log('⏳ Attempt ${attempt + 1}/$maxAttempts - waiting for power on...');
          }

          _logger.log('⚠️ Timeout waiting for power on, attempting sync anyway...');
          await syncPlayerToSelected(playerId);
        } else {
          _logger.log('🔗 Player not grouped, syncing to selected...');
          await syncPlayerToSelected(playerId);
        }
      }
    } catch (e) {
      _logger.log('❌ togglePlayerSync error: $e');
      rethrow;
    }
  }

  Future<void> togglePower(String playerId) async {
    try {
      _logger.log('🔋 togglePower called for playerId: $playerId');

      final localPlayerId = await SettingsService.getBuiltinPlayerId();
      final isLocalPlayer = localPlayerId != null && playerId == localPlayerId;

      _logger.log('🔋 Is local builtin player: $isLocalPlayer');

      if (isLocalPlayer) {
        _logger.log('🔋 Handling power toggle LOCALLY for builtin player');

        _isLocalPlayerPowered = !_isLocalPlayerPowered;
        _logger.log('🔋 Local player power set to: $_isLocalPlayerPowered');

        if (!_isLocalPlayerPowered) {
          _logger.log('🔋 Stopping playback because powered off');
          await _localPlayer.stop();
        }

        await _reportLocalPlayerState();
        await refreshPlayers();
      } else {
        _logger.log('🔋 Sending power command to server for regular player');

        final player = _availablePlayers.firstWhere(
          (p) => p.playerId == playerId,
          orElse: () => _selectedPlayer != null && _selectedPlayer!.playerId == playerId
              ? _selectedPlayer!
              : throw Exception("Player not found"),
        );

        _logger.log('🔋 Current power state: ${player.powered}, will set to: ${!player.powered}');

        await _api?.setPower(playerId, !player.powered);

        _logger.log('🔋 setPower command sent successfully');

        await refreshPlayers();
      }
    } catch (e) {
      _logger.log('🔋 ERROR in togglePower: $e');
      ErrorHandler.logError('Toggle power', e);
    }
  }

  Future<void> setVolume(String playerId, int volumeLevel) async {
    try {
      final builtinPlayerId = await SettingsService.getBuiltinPlayerId();
      if (builtinPlayerId != null && playerId == builtinPlayerId) {
        _localPlayerVolume = volumeLevel;
        await FlutterVolumeController.setVolume(volumeLevel / 100.0);
      }
      await _api?.setVolume(playerId, volumeLevel);
    } catch (e) {
      ErrorHandler.logError('Set volume', e);
      rethrow;
    }
  }

  Future<void> setMute(String playerId, bool muted) async {
    try {
      await _api?.setMute(playerId, muted);
      await refreshPlayers();
    } catch (e) {
      ErrorHandler.logError('Set mute', e);
      rethrow;
    }
  }

  Future<void> seek(String playerId, int position) async {
    try {
      // Immediately update position tracker for responsive UI
      _positionTracker.onSeek(position.toDouble());
      await _api?.seek(playerId, position);
    } catch (e) {
      ErrorHandler.logError('Seek', e);
      rethrow;
    }
  }

  /// Seek relative to current position (e.g., +30 or -30 seconds)
  Future<void> seekRelative(String playerId, int deltaSeconds) async {
    try {
      final currentPosition = _positionTracker.currentPosition.inSeconds;
      final totalDuration = _currentTrack?.duration?.inSeconds ?? 0;
      final newPosition = (currentPosition + deltaSeconds).clamp(0, totalDuration);
      await seek(playerId, newPosition);
    } catch (e) {
      ErrorHandler.logError('Seek relative', e);
      rethrow;
    }
  }

  // ============================================================================
  // AUDIOBOOK CONTEXT
  // ============================================================================

  /// Set the currently playing audiobook context (with chapters)
  void setCurrentAudiobook(Audiobook audiobook) {
    _currentAudiobook = audiobook;
    _logger.log('📚 Set current audiobook: ${audiobook.name}, chapters: ${audiobook.chapters?.length ?? 0}');
    notifyListeners();
  }

  /// Clear the audiobook context
  void clearCurrentAudiobook() {
    if (_currentAudiobook != null) {
      _logger.log('📚 Cleared audiobook context');
      _currentAudiobook = null;
      notifyListeners();
    }
  }

  /// Get the current chapter based on playback position
  Chapter? getCurrentChapter() {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return null;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return null;

    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;

    // Find the chapter that contains the current position
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (currentPositionMs >= chapters[i].positionMs) {
        return chapters[i];
      }
    }
    return chapters.first;
  }

  /// Get the index of the current chapter
  int getCurrentChapterIndex() {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return -1;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return -1;

    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;

    for (int i = chapters.length - 1; i >= 0; i--) {
      if (currentPositionMs >= chapters[i].positionMs) {
        return i;
      }
    }
    return 0;
  }

  /// Seek to the next chapter
  Future<void> seekToNextChapter(String playerId) async {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return;

    final currentIndex = getCurrentChapterIndex();
    if (currentIndex < chapters.length - 1) {
      final nextChapter = chapters[currentIndex + 1];
      final positionSeconds = nextChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to next chapter: ${nextChapter.title}');
    }
  }

  /// Seek to the previous chapter (or start of current chapter if > 3 seconds in)
  Future<void> seekToPreviousChapter(String playerId) async {
    if (_currentAudiobook == null || _currentAudiobook!.chapters == null) return;
    final chapters = _currentAudiobook!.chapters!;
    if (chapters.isEmpty) return;

    final currentIndex = getCurrentChapterIndex();
    if (currentIndex < 0) return;

    final currentChapter = chapters[currentIndex];
    final currentPositionMs = _positionTracker.currentPosition.inMilliseconds;
    final chapterProgressMs = currentPositionMs - currentChapter.positionMs;

    // If more than 3 seconds into current chapter, go to start of current chapter
    // Otherwise, go to previous chapter
    if (chapterProgressMs > 3000 || currentIndex == 0) {
      final positionSeconds = currentChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to start of chapter: ${currentChapter.title}');
    } else {
      final previousChapter = chapters[currentIndex - 1];
      final positionSeconds = previousChapter.positionMs ~/ 1000;
      await seek(playerId, positionSeconds);
      _logger.log('📚 Jumped to previous chapter: ${previousChapter.title}');
    }
  }

  Future<void> toggleShuffle(String queueId) async {
    try {
      await _api?.toggleShuffle(queueId);
    } catch (e) {
      ErrorHandler.logError('Toggle shuffle', e);
      rethrow;
    }
  }

  Future<void> setRepeatMode(String queueId, String mode) async {
    try {
      await _api?.setRepeatMode(queueId, mode);
    } catch (e) {
      ErrorHandler.logError('Set repeat mode', e);
      rethrow;
    }
  }

  Future<void> cycleRepeatMode(String queueId, String? currentMode) async {
    String nextMode;
    switch (currentMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }
    await setRepeatMode(queueId, nextMode);
  }

  @override
  void dispose() {
    _playerStateTimer?.cancel();
    _notificationPositionTimer?.cancel();
    _localPlayerStateReportTimer?.cancel();
    _localPlayerEventSubscription?.cancel();
    _playerUpdatedEventSubscription?.cancel();
    _playerAddedEventSubscription?.cancel();
    _positionTracker.dispose();
    _pcmAudioPlayer?.dispose();
    _sendspinService?.dispose();
    _api?.dispose();
    super.dispose();
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Check if a hostname is a local/private network address
  bool _isLocalNetworkHost(String host) {
    return host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.16.') ||
        host.startsWith('172.17.') ||
        host.startsWith('172.18.') ||
        host.startsWith('172.19.') ||
        host.startsWith('172.2') ||
        host.startsWith('172.30.') ||
        host.startsWith('172.31.') ||
        host == 'localhost' ||
        host.startsWith('127.') ||
        host.endsWith('.local') ||
        host.endsWith('.ts.net'); // Tailscale - treat as local since it's a VPN
  }
}
