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
/// Authelia endpoints used:
/// - /api/firstfactor
/// - /api/secondfactor/totp (preferred)
/// - /api/secondfactor (legacy fallback)
/// - /api/verify
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

        // If the user supplied a TOTP code, always attempt 2FA.
        // Otherwise, try to infer whether 2FA is needed.
        final bool wants2FA = totpCode != null && totpCode.isNotEmpty;
        final bool needs2FA = wants2FA ? true : _needs2FA(response);

        if (needs2FA) {
          _logger.log('🔐 2FA required');

          if (totpCode == null || totpCode.isEmpty) {
            _logger.log('✗ 2FA required but no TOTP code provided');
            _logger.log('Hint: Use format "password|||123456" to provide TOTP code');
            client.close();
            return null;
          }

          // Extract the session cookie from the first-factor response to send with second-factor.
          _logger.log('DEBUG: All response headers: ${response.headers.keys.toList()}');
          final firstFactorCookies = response.headers['set-cookie'];
          _logger.log('First factor cookies: ${firstFactorCookies ?? "none"}');

          final firstFactorSession = (firstFactorCookies != null && firstFactorCookies.isNotEmpty)
              ? _extractSessionCookiePair(firstFactorCookies)
              : null;
          if (firstFactorSession == null) {
            _logger.log('✗ Could not extract session cookie after first factor');
            client.close();
            return null;
          }

          // Submit second factor (TOTP)
          _logger.log('Submitting TOTP code...');
          final secondFactorUrlPreferred = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: '/api/secondfactor/totp',
          );
          final secondFactorUrlLegacy = Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: '/api/secondfactor',
          );

          final totpBody = jsonEncode({
            'token': totpCode,
            'keepMeLoggedIn': true,
          });

          // Build headers with cookies from first-factor response
          final secondFactorHeaders = {
            'Content-Type': 'application/json',
          };

          // Only send the Authelia session cookie (avoid brittle Set-Cookie parsing).
          final firstCookieHeader = '${firstFactorSession.key}=${firstFactorSession.value}';
          secondFactorHeaders['Cookie'] = firstCookieHeader;
          _logger.log('Sending cookies with second factor: $firstCookieHeader');

          response = await client
              .post(
                secondFactorUrlPreferred,
                headers: secondFactorHeaders,
                body: totpBody,
              )
              .timeout(const Duration(seconds: 10));

          // Backwards compatibility: some older setups used /api/secondfactor.
          if (response.statusCode == 404) {
            _logger.log('Second factor endpoint /api/secondfactor/totp returned 404, trying legacy endpoint...');
            response = await client
                .post(
                  secondFactorUrlLegacy,
                  headers: secondFactorHeaders,
                  body: totpBody,
                )
                .timeout(const Duration(seconds: 10));
          }

          _logger.log('Second factor response status: ${response.statusCode}');

          if (response.statusCode != 200) {
            _logger.log('✗ 2FA failed: ${response.statusCode}');
            _logger.log('Response: ${response.body}');
            client.close();
            return null;
          }

          _logger.log('✓ 2FA successful');
        }

        // Extract session cookie from Set-Cookie header.
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _logger.log('✓ Received session cookie');

          final session = _extractSessionCookiePair(cookies);
          if (session != null) {
            _logger.log('✓ Extracted session cookie (${session.key})');
            client.close();
            return AuthCredentials('authelia', {
              // Preserve existing key for compatibility.
              'session_cookie': session.value,
              // New: cookie name is configurable in Authelia (session.name).
              'cookie_name': session.key,
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
            // Check for common Authelia 2FA response fields.
            if (json.containsKey('available_methods')) return true;

            final data = json['data'];
            if (data is Map) {
              if (data.containsKey('available_methods') || data.containsKey('methods')) return true;
              if (data['second_factor'] == true || data['two_factor'] == true) return true;
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
      final sessionCookie = _extractSessionCookiePair(cookies);
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
    final cookieName = (credentials.data['cookie_name'] as String?) ?? 'authelia_session';
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

      // Use KeyChain HTTP client if available so mTLS-protected setups can
      // validate sessions without failing due to missing client cert.
      http.Client client = http.Client();
      try {
        if (Platform.isAndroid && uri.scheme == 'https') {
          final mtlsAlias = await SettingsService.getAndroidMtlsKeyAlias();
          if (mtlsAlias != null && mtlsAlias.isNotEmpty) {
            client = AndroidKeyChainHttpClient(alias: mtlsAlias);
          }
        }

        final response = await client
            .get(
              verifyUrl,
              headers: {
                'Cookie': '$cookieName=$sessionCookie',
              },
            )
            .timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      _logger.log('Auth validation failed: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    final cookieName = (credentials.data['cookie_name'] as String?) ?? 'authelia_session';
    return {
      'Cookie': '$cookieName=$sessionCookie',
    };
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    final cookieName = (credentials.data['cookie_name'] as String?) ?? 'authelia_session';
    return {
      'Cookie': '$cookieName=$sessionCookie',
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

  /// Parse Set-Cookie header and format for Cookie request header
  /// Converts "Set-Cookie: name=value; Path=/; HttpOnly" to "name=value"
  String _parseCookiesForRequest(String setCookieHeader) {
    final cookies = <String>[];

    // Set-Cookie can contain multiple cookies separated by commas
    // But cookies can also have comma in their value, so we need to be careful
    final cookieParts = setCookieHeader.split(',');

    for (final part in cookieParts) {
      // Extract just the name=value part (before first semicolon)
      final cookieValue = part.split(';').first.trim();
      if (cookieValue.isNotEmpty && cookieValue.contains('=')) {
        cookies.add(cookieValue);
      }
    }

    return cookies.join('; ');
  }

  /// Extract the configured Authelia session cookie name+value from a Set-Cookie header.
  /// Authelia allows customizing the cookie name (session.name), so we can't assume authelia_session.
  MapEntry<String, String>? _extractSessionCookiePair(String setCookieHeader) {
    // Prefer a cookie whose name contains "session".
    final re = RegExp(r'(^|,\s*)([A-Za-z0-9_\-]+)=([^;]+)');
    MapEntry<String, String>? first;
    for (final m in re.allMatches(setCookieHeader)) {
      final name = m.group(2);
      final value = m.group(3);
      if (name == null || value == null) continue;
      first ??= MapEntry(name, value);
      if (name.toLowerCase().contains('session')) {
        return MapEntry(name, value);
      }
    }

    // Fallback: return the first cookie pair we saw.
    return first;
  }
}
