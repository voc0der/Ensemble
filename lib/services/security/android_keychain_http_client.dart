import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

/// HTTP client that can use Android KeyChain certificates for mTLS
/// Falls back to standard http.Client on non-Android platforms
class AndroidKeyChainHttpClient extends http.BaseClient {
  static const _channel = MethodChannel('com.musicassistant.music_assistant/android_keychain');

  final String? _alias;
  final http.Client _inner;

  AndroidKeyChainHttpClient({String? alias})
      : _alias = alias,
        _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Only use native client for Android HTTPS requests with an alias
    if (_alias != null && _alias!.isNotEmpty && Platform.isAndroid && request.url.scheme == 'https') {
      try {
        return await _sendNative(request);
      } catch (e) {
        // Fall back to standard client on error
        return _inner.send(request);
      }
    }

    // Use standard client for non-HTTPS or when no alias
    return _inner.send(request);
  }

  Future<http.StreamedResponse> _sendNative(http.BaseRequest request) async {
    // Convert request to native format
    final Map<String, dynamic> nativeRequest = {
      'alias': _alias,
      'method': request.method,
      'url': request.url.toString(),
      'headers': request.headers,
    };

    // Add body for requests that support it
    if (request is http.Request && request.body.isNotEmpty) {
      nativeRequest['body'] = request.body;
    }

    // Call native HTTP method
    final result = await _channel.invokeMethod('httpRequest', nativeRequest);

    // Parse response
    final statusCode = result['statusCode'] as int;
    final headers = Map<String, String>.from(result['headers'] as Map);

    // Native layer returns response bytes as base64 so we can safely handle
    // binary payloads (e.g., JPEG/PNG album art) without corrupting the data.
    final bodyBase64 = result['bodyBase64'] as String?;
    final bodyBytes = bodyBase64 != null ? base64Decode(bodyBase64) : utf8.encode(result['body'] as String? ?? '');

    return http.StreamedResponse(
      Stream.value(bodyBytes),
      statusCode,
      headers: headers,
      request: request,
    );
  }

  @override
  void close() {
    _inner.close();
  }

  /// Create a client with the stored Android KeyChain alias (if any)
  static Future<http.Client> createFromSettings() async {
    if (!Platform.isAndroid) {
      return http.Client();
    }

    try {
      // Import here to avoid circular dependency
      final settingsService = await _getSettingsService();
      final alias = await settingsService?.getAndroidMtlsKeyAlias();

      if (alias != null && alias.isNotEmpty) {
        return AndroidKeyChainHttpClient(alias: alias);
      }
    } catch (e) {
      // Fall back to standard client
    }

    return http.Client();
  }

  // Helper to get settings service without circular import
  static Future<dynamic> _getSettingsService() async {
    // This will be imported by auth strategies
    return null; // Placeholder - will be replaced by actual implementation
  }
}
