import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import 'no_auth_strategy.dart';
import 'basic_auth_strategy.dart';
import 'authelia_strategy.dart';
import 'ma_auth_strategy.dart';
import '../debug_logger.dart';

/// Central authentication manager
/// Manages auth strategy selection, auto-detection, and credential lifecycle
class AuthManager {
  final _logger = DebugLogger();

  // Available auth strategies
  final List<AuthStrategy> _strategies = [
    NoAuthStrategy(),
    BasicAuthStrategy(),
    AutheliaStrategy(),
    MusicAssistantAuthStrategy(),
  ];

  AuthStrategy? _currentStrategy;
  AuthCredentials? _currentCredentials;

  /// Get current auth strategy (null if none selected)
  AuthStrategy? get currentStrategy => _currentStrategy;

  /// Get current credentials (null if none stored)
  AuthCredentials? get currentCredentials => _currentCredentials;

  /// Auto-detect authentication requirements for a server
  /// Returns null if server is unreachable or auth method unknown
  /// Also returns the final URL used (in case of HTTP fallback) via the callback
  String? _lastSuccessfulUrl;
  String? get lastSuccessfulUrl => _lastSuccessfulUrl;

  Future<AuthStrategy?> detectAuthStrategy(String serverUrl) async {
    _logger.log('🔍 Auto-detecting auth strategy for $serverUrl');
    _lastSuccessfulUrl = null;

    // Normalize URL
    var baseUrl = _normalizeUrl(serverUrl);
    _logger.log('Normalized URL: $baseUrl');

    // Try detection with the initial URL
    var result = await _tryDetectAuth(baseUrl);

    // If HTTPS failed and we haven't tried HTTP yet, try HTTP fallback
    if (result == null && baseUrl.startsWith('https://')) {
      final httpUrl = baseUrl.replaceFirst('https://', 'http://');
      _logger.log('🔄 HTTPS failed, trying HTTP fallback: $httpUrl');
      result = await _tryDetectAuth(httpUrl);
      if (result != null) {
        baseUrl = httpUrl;
      }
    }

    if (result != null) {
      _lastSuccessfulUrl = baseUrl;
      _logger.log('✅ Auth detection successful with URL: $baseUrl');
    }

    return result;
  }

  /// Normalize a server URL with appropriate protocol
  String _normalizeUrl(String url) {
    var baseUrl = url;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      // Use http for local IPs, https for domains
      if (baseUrl.startsWith('192.') ||
          baseUrl.startsWith('10.') ||
          baseUrl.startsWith('172.') ||
          baseUrl == 'localhost' ||
          baseUrl.startsWith('127.')) {
        baseUrl = 'http://$baseUrl';
      } else if (baseUrl.endsWith('.ts.net') || baseUrl.contains('.ts.net:')) {
        // Tailscale URLs - default to http:// since VPN tunnel is already encrypted
        baseUrl = 'http://$baseUrl';
        _logger.log('🔗 Detected Tailscale URL, using HTTP');
      } else {
        baseUrl = 'https://$baseUrl';
      }
    }
    return baseUrl;
  }

  /// Check if a hostname is a local/private IP address
  bool _isLocalIpAddress(String host) {
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
        host.endsWith('.local');
  }

  /// Try to detect auth strategy for a given URL
  /// Returns the strategy if successful, null if connection failed
  Future<AuthStrategy?> _tryDetectAuth(String baseUrl) async {
    // First, check if this is a Music Assistant server with native auth
    _logger.log('Checking for Music Assistant native auth at $baseUrl...');
    final maAuthResult = await _checkMusicAssistantAuth(baseUrl);
    if (maAuthResult != null) {
      if (maAuthResult == 'required') {
        _logger.log('✓ Detected Music Assistant native authentication');
        return _strategies.firstWhere((s) => s.name == 'music_assistant');
      } else if (maAuthResult == 'none') {
        _logger.log('✓ Music Assistant server - no auth required');
        return _strategies.firstWhere((s) => s.name == 'none');
      }
    }

    // Try no-auth (direct connection without any auth)
    _logger.log('Testing no-auth strategy...');
    final canConnect = await _canConnectWithoutAuth(baseUrl);
    _logger.log('No-auth result: $canConnect');

    if (canConnect) {
      _logger.log('✓ Server does not require authentication');
      return _strategies.firstWhere((s) => s.name == 'none');
    }

    // Probe server for auth requirements (reverse proxy scenarios)
    try {
      _logger.log('Probing server for auth headers...');
      // Test root endpoint
      final probeUrl = baseUrl;
      _logger.log('Probe URL: $probeUrl');

      final response = await http.get(
        Uri.parse(probeUrl),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Probe status: ${response.statusCode}');

      // Check for redirect (common with reverse proxy auth)
      if (response.statusCode == 302 || response.statusCode == 307) {
        final location = response.headers['location'];
        _logger.log('Redirect to: $location');

        // If redirects to Authelia login, it's Authelia
        if (location != null && location.contains('authelia')) {
          _logger.log('✓ Detected Authelia (redirect)');
          return _strategies.firstWhere((s) => s.name == 'authelia');
        }
      }

      // Server returned 401 Unauthorized - check WWW-Authenticate header
      if (response.statusCode == 401) {
        final wwwAuth = response.headers['www-authenticate']?.toLowerCase();
        _logger.log('401 with WWW-Authenticate: $wwwAuth');

        // Check for Basic Auth
        if (wwwAuth != null && wwwAuth.contains('basic')) {
          _logger.log('✓ Detected Basic Authentication');
          return _strategies.firstWhere((s) => s.name == 'basic');
        }

        // Check for Bearer token - could be MA native auth
        if (wwwAuth != null && wwwAuth.contains('bearer')) {
          _logger.log('✓ Detected Bearer auth - likely Music Assistant native');
          return _strategies.firstWhere((s) => s.name == 'music_assistant');
        }
      }

      // If we got here and there's any auth challenge, assume Authelia
      // (since we're behind a reverse proxy that requires auth)
      if (response.statusCode >= 300) {
        _logger.log('Server requires authentication (status ${response.statusCode})');
        _logger.log('Assuming Authelia (default for authenticated reverse proxy)');
        return _strategies.firstWhere((s) => s.name == 'authelia');
      }
    } catch (e) {
      _logger.log('✗ Auth detection error: $e');
      return null; // Return null to trigger fallback
    }

    _logger.log('⚠️ Could not determine auth method');
    return null;
  }

  /// Check if server is a Music Assistant server with native auth
  /// Returns 'required' if auth needed, 'none' if no auth, null if not MA or error
  Future<String?> _checkMusicAssistantAuth(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl);
      // Use the port from URL if specified, otherwise use default ports (80/443)
      // Don't default to 8095 here - that's only for direct connections without reverse proxy
      final apiUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api',
      );

      _logger.log('Checking MA API at: $apiUrl');

      // Use IOClient to control redirect behavior for local IPs
      final isLocalIp = _isLocalIpAddress(uri.host);
      http.Response response;

      if (isLocalIp) {
        // For local IPs, don't follow redirects - handle them explicitly
        final client = HttpClient();
        try {
          final request = await client.postUrl(apiUrl);
          request.followRedirects = false;
          request.headers.set('Content-Type', 'application/json');
          request.write(jsonEncode({'command': 'info'}));
          final ioResponse = await request.close().timeout(const Duration(seconds: 5));

          // Check for redirect to HTTPS
          if (ioResponse.statusCode == 308 || ioResponse.statusCode == 301 || ioResponse.statusCode == 302) {
            final location = ioResponse.headers.value('location');
            _logger.log('Local IP redirects to: $location');
            if (location != null && location.startsWith('https://')) {
              _logger.log('⚠️ Server redirects HTTP to HTTPS - this may cause certificate issues for local IP');
              // Don't follow the redirect - it will likely fail with cert error
              // Instead, return null to trigger fallback logic
              client.close();
              return null;
            }
          }

          final body = await ioResponse.transform(utf8.decoder).join();
          response = http.Response(body, ioResponse.statusCode);
          client.close();
        } catch (e) {
          client.close();
          rethrow;
        }
      } else {
        // For non-local URLs, use standard http.post which follows redirects
        response = await http.post(
          apiUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'command': 'info',
          }),
        ).timeout(const Duration(seconds: 5));
      }

      _logger.log('MA API response: ${response.statusCode}');
      _logger.log('MA API body: ${response.body}');

      // 401/403 means auth required - check this first
      if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.log('MA API returned ${response.statusCode} - auth required');
        return 'required';
      }

      // Also check for "Authentication required" text response
      if (response.body.toLowerCase().contains('authentication required')) {
        _logger.log('MA API returned auth required message');
        return 'required';
      }

      if (response.statusCode == 200) {
        // Try to parse as JSON
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;

          // Check if we got server info successfully (no auth required)
          if (data.containsKey('result')) {
            final result = data['result'] as Map<String, dynamic>?;
            final serverVersion = result?['server_version'] as String?;
            final schemaVersion = result?['schema_version'] as int?;

            if (serverVersion != null) {
              _logger.log('MA server version: $serverVersion, schema: $schemaVersion');

              // Schema 28+ requires auth, but if we got here without auth, it's not enabled
              return 'none';
            }
          }

          // Check for auth error in JSON
          if (data.containsKey('error_code')) {
            final errorCode = data['error_code'] as int?;
            // Error 50 = AuthenticationRequired
            if (errorCode == 50) {
              _logger.log('MA server requires authentication (error 50)');
              return 'required';
            }
          }
        } catch (jsonError) {
          _logger.log('MA API response not JSON: $jsonError');
        }
      }

      return null;
    } catch (e) {
      _logger.log('MA auth check error: $e');
      return null;
    }
  }

  /// Test if server is accessible without authentication
  Future<bool> _canConnectWithoutAuth(String serverUrl) async {
    try {
      final uri = Uri.parse(serverUrl);
      _logger.log('No-auth test URL: $serverUrl');

      final isLocalIp = _isLocalIpAddress(uri.host);
      int statusCode;

      if (isLocalIp) {
        // For local IPs, don't follow redirects to avoid HTTPS cert issues
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          request.followRedirects = false;
          final response = await request.close().timeout(const Duration(seconds: 10));
          statusCode = response.statusCode;

          // Check for redirect to HTTPS
          if (statusCode == 308 || statusCode == 301 || statusCode == 302) {
            final location = response.headers.value('location');
            if (location != null && location.startsWith('https://')) {
              _logger.log('⚠️ Local IP redirects to HTTPS: $location');
              client.close();
              return false; // Can't connect - would need HTTPS which has cert issues
            }
          }
          client.close();
        } catch (e) {
          client.close();
          rethrow;
        }
      } else {
        // For non-local URLs, use standard http.get
        final response = await http.get(uri).timeout(const Duration(seconds: 10));
        statusCode = response.statusCode;
      }

      _logger.log('No-auth status: $statusCode');

      // 200 = no auth required
      // 302/307/308 = redirect (probably to auth or HTTPS)
      // 401 = auth required
      if (statusCode == 200) {
        return true;
      }

      return false;
    } catch (e) {
      _logger.log('No-auth error: $e');
      return false;
    }
  }

  /// Attempt login with specified strategy
  /// Returns true if login successful and credentials stored
  /// authServerUrl is optional - only used for Authelia when auth is on a different domain
  Future<bool> login(
    String serverUrl,
    String username,
    String password,
    AuthStrategy strategy, {
    String? authServerUrl,
  }) async {
    _logger.log('Attempting login with ${strategy.name} strategy');

    // Use auth server URL if provided, otherwise use main server URL
    final loginUrl = authServerUrl?.isNotEmpty == true ? authServerUrl! : serverUrl;
    _logger.log('Login URL: $loginUrl');

    final credentials = await strategy.login(loginUrl, username, password);

    if (credentials != null) {
      _currentStrategy = strategy;
      _currentCredentials = credentials;
      _logger.log('✓ Login successful with ${strategy.name}');
      return true;
    }

    _logger.log('✗ Login failed with ${strategy.name}');
    return false;
  }

  /// Validate current credentials are still valid
  Future<bool> validateCurrentCredentials(String serverUrl) async {
    if (_currentStrategy == null || _currentCredentials == null) {
      return false;
    }

    return await _currentStrategy!.validateCredentials(
      serverUrl,
      _currentCredentials!,
    );
  }

  /// Get WebSocket connection headers for current credentials
  Map<String, dynamic> getWebSocketHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildWebSocketHeaders(_currentCredentials!);
  }

  /// Get HTTP streaming headers for current credentials
  Map<String, String> getStreamingHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildStreamingHeaders(_currentCredentials!);
  }

  /// Serialize current credentials for persistent storage
  Map<String, dynamic>? serializeCredentials() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return null;
    }

    return {
      'strategy': _currentStrategy!.name,
      'data': _currentStrategy!.serializeCredentials(_currentCredentials!),
    };
  }

  /// Deserialize and restore credentials from persistent storage
  void deserializeCredentials(Map<String, dynamic> stored) {
    final strategyName = stored['strategy'] as String?;
    final data = stored['data'] as Map<String, dynamic>?;

    if (strategyName == null || data == null) {
      return;
    }

    // Find matching strategy
    try {
      final strategy = _strategies.firstWhere((s) => s.name == strategyName);
      _currentStrategy = strategy;
      _currentCredentials = strategy.deserializeCredentials(data);
      _logger.log('✓ Restored ${strategy.name} credentials from storage');
    } catch (e) {
      _logger.log('✗ Could not restore credentials: $e');
    }
  }

  /// Clear current authentication state
  void logout() {
    _currentStrategy = null;
    _currentCredentials = null;
    _logger.log('Logged out - cleared auth state');
  }

  /// Get strategy by name (for manual selection)
  AuthStrategy? getStrategyByName(String name) {
    try {
      return _strategies.firstWhere((s) => s.name == name);
    } catch (e) {
      return null;
    }
  }
}
