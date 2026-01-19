import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'security/android_keychain_http_client.dart';
import 'settings_service.dart';

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

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    _httpClient ??= await _createHttpClient();

    final authHeaders = await _getAuthHeaders();
    final allHeaders = {...?headers, ...authHeaders};

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
        return AndroidKeyChainHttpClient(alias: mtlsAlias);
      }
    } catch (e) {
      // Fall back to standard client
    }

    return http.Client();
  }

  /// Get authentication headers (Authelia cookie)
  Future<Map<String, String>> _getAuthHeaders() async {
    final headers = <String, String>{};

    try {
      final credentials = await SettingsService.getAuthCredentials();

      if (credentials != null && credentials['strategyName'] == 'authelia') {
        final sessionCookie = credentials['session_cookie'] as String?;
        final cookieName = (credentials['cookie_name'] as String?) ?? 'authelia_session';

        if (sessionCookie != null) {
          headers['Cookie'] = '$cookieName=$sessionCookie';
        }
      }
    } catch (e) {
      // Silently ignore auth errors
    }

    return headers;
  }

  void dispose() {
    _httpClient?.close();
  }
}
