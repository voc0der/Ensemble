import 'dart:async';

import 'package:flutter/foundation.dart' show unawaited;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'android_keychain.dart';

/// A [WebSocketChannel] implementation backed by Android OkHttp + KeyChain.
///
/// Dart's `WebSocket.connect()` cannot use client private keys stored in the
/// Android system KeyChain, so we bridge WebSocket operations through a native
/// OkHttp WebSocket that is configured with a KeyChain alias.
class NativeKeyChainWebSocketChannel implements WebSocketChannel {
  @override
  final Stream<dynamic> stream;

  @override
  final WebSocketSink sink;

  @override
  final String? protocol;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  NativeKeyChainWebSocketChannel._({
    required this.stream,
    required this.sink,
    this.protocol,
  });

  static Future<NativeKeyChainWebSocketChannel> connect({
    required String alias,
    required String url,
    Map<String, String>? headers,
  }) async {
    final id = await AndroidKeyChain.wsConnect(
      alias: alias,
      url: url,
      headers: headers,
    );

    final incoming = StreamController<dynamic>();
    final doneCompleter = Completer<void>();

    late StreamSubscription<Map<String, dynamic>> sub;

    void finish([Object? error, StackTrace? st]) {
      if (!doneCompleter.isCompleted) {
        if (error != null) {
          doneCompleter.completeError(error, st);
        } else {
          doneCompleter.complete();
        }
      }
      if (!incoming.isClosed) {
        incoming.close();
      }
      sub.cancel();
    }

    sub = AndroidKeyChain.wsEvents.listen((event) {
      if (event['id'] != id) return;

      final type = (event['type'] ?? '').toString();
      switch (type) {
        case 'open':
          // no-op
          break;
        case 'message':
          // Music Assistant uses JSON text frames.
          incoming.add(event['message']);
          break;
        case 'closing':
          // no-op; await closed
          break;
        case 'closed':
          finish();
          break;
        case 'failure':
          final err = event['error']?.toString() ?? 'WebSocket failure';
          finish(Exception(err));
          break;
        default:
          // ignore unknown events
          break;
      }
    }, onError: (e, st) {
      finish(e, st);
    }, onDone: () {
      finish();
    });

    final sink = _NativeWebSocketSink(
      id: id,
      done: doneCompleter.future,
      onClose: ({int? code, String? reason}) async {
        await AndroidKeyChain.wsClose(id: id, code: code, reason: reason);
      },
      onSend: (msg) async {
        await AndroidKeyChain.wsSend(id: id, message: msg);
      },
    );

    return NativeKeyChainWebSocketChannel._(
      stream: incoming.stream,
      sink: sink,
    );
  }
}

class _NativeWebSocketSink implements WebSocketSink {
  final String id;
  final Future<void> _done;
  final Future<void> Function({int? code, String? reason}) onClose;
  final Future<void> Function(String message) onSend;

  bool _isClosed = false;

  _NativeWebSocketSink({
    required this.id,
    required Future<void> done,
    required this.onClose,
    required this.onSend,
  }) : _done = done;

  @override
  Future<void> get done => _done;

  @override
  void add(dynamic data) {
    if (_isClosed) return;
    if (data is String) {
      unawaited(onSend(data));
    } else {
      // Be strict: MA expects text JSON frames.
      unawaited(onSend(data.toString()));
    }
  }

  @override
  Future addStream(Stream stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    // No direct equivalent on native bridge; treat as close.
  }

  @override
  Future close([int? closeCode, String? closeReason]) async {
    if (_isClosed) return;
    _isClosed = true;
    await onClose(code: closeCode, reason: closeReason);
    return;
  }
}
