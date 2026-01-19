import 'dart:async';
import 'package:flutter/services.dart';

/// Wraps the platform websocket session so we can:
///  - avoid spamming NO_SESSION errors
///  - stop retry loops when disconnected
///  - provide a single "connected" gate for all commands
class MaWsSession {
  MaWsSession({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('musicassistant/ws');

  final MethodChannel _channel;

  String? _sessionId;
  bool _connected = false;
  DateTime? _lastNoSessionLog;

  final StreamController<bool> _connectedCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectedStream => _connectedCtrl.stream;
  bool get isConnected => _connected;
  String? get sessionId => _sessionId;

  Future<void> connect(Map<String, dynamic> args) async {
    // args example: { "host": "...", "port": 8095, "tls": false, ... }
    final id = await _channel.invokeMethod<String>('connect', args);
    _sessionId = id;
    _setConnected(true);
  }

  Future<void> disconnect() async {
    final id = _sessionId;
    _sessionId = null;
    _setConnected(false);
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('disconnect', {'id': id});
      } catch (_) {
        // Best-effort.
      }
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _connectedCtrl.add(value);
  }

  /// Send a message only if connected; treat NO_SESSION as disconnected and do NOT retry.
  Future<T?> send<T>(String method, Map<String, dynamic> payload) async {
    final id = _sessionId;
    if (!_connected || id == null) return null;

    try {
      return await _channel.invokeMethod<T>(method, {
        'id': id,
        ...payload,
      });
    } on PlatformException catch (e) {
      if (e.code == 'NO_SESSION') {
        // Throttle the log to once per 5s to avoid spam.
        final now = DateTime.now();
        if (_lastNoSessionLog == null ||
            now.difference(_lastNoSessionLog!).inMilliseconds > 5000) {
          _lastNoSessionLog = now;
          // Intentionally quiet: callers will see null and stop retrying.
          // print('WebSocket NO_SESSION; marking disconnected');
        }
        // Mark disconnected and clear session so polling/commands stop.
        _sessionId = null;
        _setConnected(false);
        return null;
      }
      rethrow;
    }
  }

  void dispose() {
    _connectedCtrl.close();
  }
}
