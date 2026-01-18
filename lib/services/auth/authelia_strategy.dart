import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import '../debug_logger.dart';
import '../settings_service.dart';
import '../security/android_keychain.dart';
import '../security/android_keychain_http_client.dart';

/// Authelia authentication strategy
/// Used when Music Assistant is behind Authelia reverse proxy authentication
/// Authelia-specific endpoints: /api/firstfactor, /api/verify
class AutheliaStrategy implements AuthStrategy {
  final _logger = DebugLogger();

  @override
  String get name => 'authelia';

  @override
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    try {
      // Normalize server URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      _logger.log('🔐 Attempting Authelia login to $baseUrl');

      // Parse URL and construct Authelia firstfactor endpoint
      final uri = Uri.parse(baseUrl);
      final authUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/firstfactor',
      );

      _logger.log('Auth URL: $authUrl');

      // Prepare request body
      final requestBody = jsonEncode({
        'username': username,
        'password': password,
        'keepMeLoggedIn': true,
      });

      // Try with KeyChain HTTP client if available (Android HTTPS only)
      http.Client client = http.Client();
      String? mtlsAlias;

      if (Platform.isAndroid && uri.scheme == 'https') {
        mtlsAlias = await SettingsService.getAndroidMtlsKeyAlias();
        if (mtlsAlias != null && mtlsAlias.isNotEmpty) {
          _logger.log('Using Android KeyChain cert for HTTP request');
          client = AndroidKeyChainHttpClient(alias: mtlsAlias);
        }
      }

      // POST to Authelia's firstfactor endpoint
      var response = await client.post(
        authUrl,
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      ).timeout(const Duration(seconds: 10));

      _logger.log('Auth response status: ${response.statusCode}');

      // Check if client certificate is required (400 status with cert error)
      if (Platform.isAndroid &&
          uri.scheme == 'https' &&
          response.statusCode == 400 &&
          (mtlsAlias == null || mtlsAlias.isEmpty) &&
          _looksLikeClientCertRequired(response.body)) {

        _logger.log('🔐 Client certificate required, prompting for selection...');

        // Prompt user to select certificate
        final selectedAlias = await AndroidKeyChain.selectClientCertificate(
          host: uri.host,
          port: uri.hasPort ? uri.port : 443,
        );

        if (selectedAlias != null && selectedAlias.isNotEmpty) {
          _logger.log('✓ Certificate selected, saving and retrying...');
          await SettingsService.setAndroidMtlsKeyAlias(selectedAlias);

          // Retry with the selected certificate
          client.close();
          client = AndroidKeyChainHttpClient(alias: selectedAlias);

          response = await client.post(
            authUrl,
            headers: {
              'Content-Type': 'application/json',
            },
            body: requestBody,
          ).timeout(const Duration(seconds: 10));

          _logger.log('Auth response status (with cert): ${response.statusCode}');
        } else {
          _logger.log('✗ No certificate selected');
          client.close();
          return null;
        }
      }

      // Check for successful authentication
      if (response.statusCode == 200) {
        _logger.log('✓ Authentication successful');

        // Extract session cookie from Set-Cookie header
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _logger.log('✓ Received session cookie');

          final sessionCookie = _extractSessionCookie(cookies);
          if (sessionCookie != null) {
            _logger.log('✓ Extracted session cookie');
            client.close();
            return AuthCredentials('authelia', {
              'session_cookie': sessionCookie,
              'username': username,
            });
          }
        }

        // If 200 but no cookie, something is wrong
        _logger.log('✗ No session cookie in response');
        client.close();
        return null;
      }

      _logger.log('✗ Authentication failed: ${response.statusCode}');
      _logger.log('Response body: ${response.body}');
      client.close();
      return null;
    } catch (e) {
      _logger.log('✗ Login error: $e');
      return null;
    }
  }

  bool _looksLikeClientCertRequired(String body) {
    final msg = body.toLowerCase();
    return msg.contains('no required ssl certificate') ||
        msg.contains('certificate required') ||
        msg.contains('certificate_required') ||
        msg.contains('client certificate');
  }

  @override
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    final sessionCookie = credentials.data['session_cookie'] as String?;
    if (sessionCookie == null) return false;

    try {
      // Normalize server URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      // Parse URL and construct Authelia verify endpoint
      final uri = Uri.parse(baseUrl);
      final verifyUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/verify',
      );

      final response = await http.get(
        verifyUrl,
        headers: {
          'Cookie': 'authelia_session=$sessionCookie',
        },
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      _logger.log('Auth validation failed: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    return {
      'Cookie': 'authelia_session=$sessionCookie',
    };
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    return {
      'Cookie': 'authelia_session=$sessionCookie',
    };
  }

  @override
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials) {
    return credentials.data;
  }

  @override
  AuthCredentials deserializeCredentials(Map<String, dynamic> data) {
    return AuthCredentials('authelia', data);
  }

  /// Extract authelia_session cookie value from Set-Cookie header
  /// Migrated from auth_service.dart:81-98
  String? _extractSessionCookie(String setCookieHeader) {
    final cookies = setCookieHeader.split(',');

    for (final cookie in cookies) {
      if (cookie.trim().startsWith('authelia_session=')) {
        final parts = cookie.split(';');
        if (parts.isNotEmpty) {
          final value = parts[0].trim();
          if (value.startsWith('authelia_session=')) {
            return value.substring('authelia_session='.length);
          }
        }
      }
    }

    return null;
  }
}
