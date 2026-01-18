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
///
/// Supports:
/// - Single-factor authentication (username/password)
/// - Two-factor authentication (TOTP)
/// - mTLS client certificates (Android only)
///
/// For 2FA/TOTP: Use password format "yourpassword|||123456" where 123456 is your TOTP code
///
/// Authelia endpoints used: /api/firstfactor, /api/secondfactor, /api/verify
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

      // Parse password field for optional TOTP code (format: "password|||123456")
      String actualPassword = password;
      String? totpCode;
      if (password.contains('|||')) {
        final parts = password.split('|||');
        actualPassword = parts[0];
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          totpCode = parts[1].trim();
          _logger.log('TOTP code detected in password field');
        }
      }

      // Prepare request body
      final requestBody = jsonEncode({
        'username': username,
        'password': actualPassword,
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
        _logger.log('✓ First factor successful');

        // Check if 2FA is required
        final bool needs2FA = _needs2FA(response);

        if (needs2FA) {
          _logger.log('🔐 2FA required');

          if (totpCode == null || totpCode.isEmpty) {
            _logger.log('✗ 2FA required but no TOTP code provided');
            _logger.log('Hint: Use format "password|||123456" to provide TOTP code');
            client.close();
            return null;
          }

          // Submit second factor (TOTP)
          _logger.log('Submitting TOTP code...');
          final secondFactorUrl = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: '/api/secondfactor',
          );

          final totpBody = jsonEncode({
            'token': totpCode,
            'keepMeLoggedIn': true,
          });

          response = await client.post(
            secondFactorUrl,
            headers: {
              'Content-Type': 'application/json',
            },
            body: totpBody,
          ).timeout(const Duration(seconds: 10));

          _logger.log('Second factor response status: ${response.statusCode}');

          if (response.statusCode != 200) {
            _logger.log('✗ 2FA failed: ${response.statusCode}');
            _logger.log('Response: ${response.body}');
            client.close();
            return null;
          }

          _logger.log('✓ 2FA successful');
        }

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

  bool _needs2FA(http.Response response) {
    // After successful first-factor, check if 2FA is required
    // Authelia returns 200 but may indicate 2FA is needed in the response

    try {
      // Check response body for 2FA indicators
      final body = response.body;
      if (body.isNotEmpty) {
        // Try to parse JSON response
        try {
          final json = jsonDecode(body);
          // Check for common Authelia 2FA response fields
          if (json is Map) {
            // If status field exists and indicates 2FA required
            if (json.containsKey('status') && json['status'] != null) {
              return true; // Authelia typically returns a status object when 2FA is pending
            }
            // Check for available_methods or similar fields
            if (json.containsKey('available_methods')) {
              return true;
            }
          }
        } catch (_) {
          // Not JSON or parsing failed, continue with other checks
        }
      }

      // Alternative check: if we got 200 but no session cookie, assume 2FA required
      // (This is the most reliable indicator)
      final cookies = response.headers['set-cookie'];
      if (cookies == null || cookies.isEmpty) {
        _logger.log('No session cookie after first factor - assuming 2FA required');
        return true;
      }

      // Check if the session cookie looks incomplete/temporary
      final sessionCookie = _extractSessionCookie(cookies);
      if (sessionCookie == null) {
        _logger.log('Could not extract session cookie - assuming 2FA required');
        return true;
      }

      // If we have a proper session cookie, 2FA is not required
      return false;
    } catch (e) {
      _logger.log('Error checking 2FA requirement: $e');
      return false;
    }
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
