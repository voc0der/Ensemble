import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'security/android_keychain_http_client.dart';
import 'settings_service.dart';
import 'debug_logger.dart';

/// Custom cache manager that uses AndroidKeyChainHttpClient for mTLS support
/// and adds Authelia cookies for authentication
class AuthenticatedCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'authenticatedImageCache';
  static AuthenticatedCacheManager? _instance;

  /// Get singleton instance
  static AuthenticatedCacheManager get instance {
    _instance ??= AuthenticatedCacheManager._();
    return _instance!;
  }

  AuthenticatedCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 200,
            fileService: _AuthenticatedHttpFileService(),
          ),
        );

  /// Reset the cache manager (useful after auth changes)
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}

/// Custom HTTP file service that uses AndroidKeyChainHttpClient with mTLS
/// and adds authentication headers for Authelia
class _AuthenticatedHttpFileService extends HttpFileService {
  http.Client? _httpClient;
  String? _activeMtlsAlias;
  final _logger = DebugLogger();

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    _httpClient ??= await _createHttpClient();
    // Re-evaluate mTLS alias on each request so we don't get stuck on a non-mTLS
    // client created before the user selected/saved their cert.
    _httpClient = await _refreshHttpClientIfNeeded();

    final authHeaders = await _getAuthHeaders();
    final allHeaders = {...?headers, ...authHeaders};
    // Helpful for diagnosing whether images are using the authenticated
    // cache path (shows up in reverse-proxy logs).
    allHeaders.putIfAbsent('User-Agent', () => 'EnsembleImage/OkHttp');

    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(allHeaders);

    final httpResponse = await _httpClient!.send(req);

    return HttpGetResponse(httpResponse);
  }

  /// Create HTTP client with mTLS support if needed
  Future<http.Client> _createHttpClient() async {
    if (!Platform.isAndroid) {
      return http.Client();
    }

    try {
      final mtlsAlias = await SettingsService.getAndroidMtlsKeyAlias();
      if (mtlsAlias != null && mtlsAlias.isNotEmpty) {
        _activeMtlsAlias = mtlsAlias;
        _logger.debug('🖼️ ImageCache: using Android KeyChain mTLS cert (alias=$mtlsAlias)', context: 'ImageCache');
        return AndroidKeyChainHttpClient(alias: mtlsAlias);
      }
    } catch (e) {
      // Fall back to standard client
      _logger.warning('🖼️ ImageCache: failed to read mTLS alias, falling back: $e', context: 'ImageCache');
    }

    _activeMtlsAlias = null;
    return http.Client();
  }

  /// If the user selects a certificate after this service was created, we must
  /// recreate the underlying http client so future image downloads actually use mTLS.
  Future<http.Client> _refreshHttpClientIfNeeded() async {
    if (!Platform.isAndroid) {
      return _httpClient ?? http.Client();
    }

    String? alias;
    try {
      alias = await SettingsService.getAndroidMtlsKeyAlias();
    } catch (e) {
      // Keep whatever we have if reading settings fails.
      return _httpClient ?? http.Client();
    }

    final wantsMtls = alias != null && alias.isNotEmpty;
    final hasMtlsClient = _httpClient is AndroidKeyChainHttpClient;

    if (wantsMtls) {
      if (!hasMtlsClient || _activeMtlsAlias != alias) {
        _logger.debug('🖼️ ImageCache: (re)creating mTLS HTTP client (alias=$alias)', context: 'ImageCache');
        _httpClient?.close();
        _activeMtlsAlias = alias;
        _httpClient = AndroidKeyChainHttpClient(alias: alias!);
      }
    } else {
      if (hasMtlsClient || _activeMtlsAlias != null) {
        _logger.debug('🖼️ ImageCache: switching to standard HTTP client (no mTLS alias)', context: 'ImageCache');
        _httpClient?.close();
        _activeMtlsAlias = null;
        _httpClient = http.Client();
      }
    }

    return _httpClient ?? http.Client();
  }

  /// Get authentication headers (Authelia cookie)
  Future<Map<String, String>> _getAuthHeaders() async {
    final headers = <String, String>{};

    try {
      // Stored credentials are serialized as:
      // {"strategy": "authelia", "data": {"session_cookie": "...", "cookie_name": "..."}}
      final stored = await SettingsService.getAuthCredentials();
      final strategy = stored?['strategy'] as String?;
      final data = stored?['data'];

      if (strategy == 'authelia' && data is Map) {
        final sessionCookie = data['session_cookie'] as String?;
        final cookieName = (data['cookie_name'] as String?) ?? 'authelia_session';

        if (sessionCookie != null && sessionCookie.isNotEmpty) {
          headers['Cookie'] = '$cookieName=$sessionCookie';
          _logger.debug('🖼️ ImageCache: adding Authelia cookie header ($cookieName=***)', context: 'ImageCache');
        } else {
          _logger.debug('🖼️ ImageCache: Authelia strategy present but no session cookie found', context: 'ImageCache');
        }
      }
    } catch (e) {
      // Silently ignore auth errors
      _logger.warning('🖼️ ImageCache: failed to read auth credentials: $e', context: 'ImageCache');
    }

    return headers;
  }

  void dispose() {
    _httpClient?.close();
  }
}
