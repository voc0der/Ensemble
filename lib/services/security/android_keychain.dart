import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android-only bridge to the system KeyChain + native OkHttp.
///
/// This mirrors the approach used in paperless-mobile:
/// - Prompt the Android KeyChain picker for a client certificate alias
/// - Use the selected alias to create an SSLContext in native and perform
///   mTLS HTTP / WebSocket operations via OkHttp (because Dart's TLS stack
///   cannot access Android system private keys).
class AndroidKeyChain {
  static const MethodChannel _channel = MethodChannel('com.musicassistant.music_assistant/android_keychain');

  static final StreamController<Map<String, dynamic>> _wsEvents =
      StreamController<Map<String, dynamic>>.broadcast();

  static bool _handlerInstalled = false;

  static void _ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wsEvent') {
        final raw = call.arguments;
        if (raw is Map) {
          _wsEvents.add(raw.cast<String, dynamic>());
        }
        return null;
      }
      return null;
    });
  }

  static Stream<Map<String, dynamic>> get wsEvents {
    _ensureHandlerInstalled();
    return _wsEvents.stream;
  }

  static Future<String?> selectClientCertificate({required String host, required int port}) async {
    if (!Platform.isAndroid) return null;
    final alias = await _channel.invokeMethod<String>(
      'selectClientCertificate',
      <String, dynamic>{
        'host': host,
        'port': port,
      },
    );
    return (alias == null || alias.isEmpty) ? null : alias;
  }

  static Future<String?> getCertificateSubject(String alias) async {
    if (!Platform.isAndroid) return null;
    final subject = await _channel.invokeMethod<String>(
      'getCertificateSubject',
      <String, dynamic>{'alias': alias},
    );
    return (subject == null || subject.isEmpty) ? null : subject;
  }

  static Future<String> wsConnect({
    required String alias,
    required String url,
    Map<String, String>? headers,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError('AndroidKeyChain.wsConnect is Android-only');
    }
    _ensureHandlerInstalled();
    final id = await _channel.invokeMethod<String>(
      'wsConnect',
      <String, dynamic>{
        'alias': alias,
        'url': url,
        'headers': headers ?? <String, String>{},
      },
    );
    if (id == null || id.isEmpty) {
      throw StateError('Native wsConnect returned null/empty id');
    }
    return id;
  }

  static Future<void> wsSend({required String id, required String message}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>(
      'wsSend',
      <String, dynamic>{
        'id': id,
        'message': message,
      },
    );
  }

  static Future<void> wsClose({required String id, int? code, String? reason}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>(
      'wsClose',
      <String, dynamic>{
        'id': id,
        if (code != null) 'code': code,
        if (reason != null) 'reason': reason,
      },
    );
  }
}
