import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/profile_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/auth/auth_manager.dart';
import '../services/cache_service.dart';

/// Provider for managing connection state to Music Assistant server
/// Handles WebSocket connection, authentication, and reconnection
class ConnectionProvider with ChangeNotifier {
  MusicAssistantAPI? _api;
  final AuthManager _authManager = AuthManager();
  final DebugLogger _logger = DebugLogger();
  final CacheService _cacheService = CacheService();

  MAConnectionState _connectionState = MAConnectionState.disconnected;
  String? _serverUrl;
  String? _error;

  // Callbacks for post-connection initialization
  VoidCallback? onConnected;
  VoidCallback? onAuthenticated;
  VoidCallback? onDisconnected;

  MAConnectionState get connectionState => _connectionState;
  String? get serverUrl => _serverUrl;
  String? get error => _error;
  bool get isConnected => _connectionState == MAConnectionState.connected ||
                          _connectionState == MAConnectionState.authenticated;

  MusicAssistantAPI? get api => _api;
  AuthManager get authManager => _authManager;
  CacheService get cacheService => _cacheService;

  ConnectionProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    _serverUrl = await SettingsService.getServerUrl();
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      await _restoreAuthCredentials();
      await connectToServer(_serverUrl!);
    }
  }

  /// Restore auth credentials from persistent storage
  Future<void> _restoreAuthCredentials() async {
    final savedCredentials = await SettingsService.getAuthCredentials();
    if (savedCredentials != null) {
      _logger.log('🔐 Restoring saved auth credentials...');
      _authManager.deserializeCredentials(savedCredentials);
      _logger.log('🔐 Auth credentials restored: ${_authManager.currentStrategy?.name ?? "none"}');
    } else {
      _logger.log('🔐 No saved auth credentials found');
    }
  }

  /// Handle Music Assistant native authentication after WebSocket connection
  Future<bool> handleMaAuthentication() async {
    if (_api == null) return false;

    try {
      // First, try stored MA token
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

      // No valid token - try stored credentials
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

  /// Fetch user profile from MA and set owner name + create/activate local profile
  Future<void> _fetchAndSetUserProfileName() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) {
        _logger.log('⚠️ Could not fetch user profile');
        return;
      }

      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;

      _logger.log('🔍 Profile data: display_name="$displayName", username="$username"');

      final profileName = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : username;

      if (profileName != null && profileName.isNotEmpty) {
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');

        // Create/activate profile in local database
        if (DatabaseService.instance.isInitialized && username != null) {
          await ProfileService.instance.onMaAuthenticated(
            username: username,
            displayName: displayName,
          );
          _logger.log('✅ Local profile activated: $username');
        }
      } else {
        _logger.log('⚠️ No valid name in profile');
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user profile (non-fatal): $e');
    }
  }

  Future<void> connectToServer(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Disconnect existing connection
      await _api?.disconnect();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      // Listen to connection state changes
      _api!.connectionState.listen(
        (state) async {
          _connectionState = state;
          notifyListeners();

          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            if (_api!.authRequired && !_api!.isAuthenticated) {
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await handleMaAuthentication();
              if (!authenticated) {
                _logger.log('❌ MA authentication failed - stopping connection flow');
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              return;
            }

            // No auth required - notify connected
            onConnected?.call();
          } else if (state == MAConnectionState.authenticated) {
            _logger.log('✅ MA authentication successful');
            onAuthenticated?.call();
          } else if (state == MAConnectionState.disconnected) {
            // DON'T clear caches on disconnect - keep showing cached data
            // This allows instant UI display when app resumes or reconnects
            // Caches will be refreshed when connection is restored
            onDisconnected?.call();
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
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

  Future<void> disconnect() async {
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    // DON'T clear caches on disconnect - keep showing cached data for instant reconnect
    notifyListeners();
  }

  /// Clear all caches and state (for logout or server change)
  void clearCachesOnLogout() {
    _cacheService.clearAll();
    notifyListeners();
  }

  /// Check connection and reconnect if needed (called when app resumes)
  Future<void> checkAndReconnect() async {
    _logger.log('🔄 checkAndReconnect called - state: $_connectionState');

    if (_serverUrl == null) {
      _logger.log('🔄 No server URL saved, skipping reconnect');
      return;
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
      _logger.log('🔄 Already connected, connection verified');
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}
