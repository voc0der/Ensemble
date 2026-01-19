import 'dart:async';
import 'ma_ws_session.dart';

/// Centralized polling so we don't have multiple timers spamming players/all
/// (and timing out) when the WS session is gone.
class MaPolling {
  MaPolling(this._ws);

  final MaWsSession _ws;

  Timer? _timer;
  bool _inFlight = false;
  Duration _interval = const Duration(seconds: 3);

  StreamSubscription<bool>? _connSub;

  void start() {
    _connSub ??= _ws.connectedStream.listen((connected) {
      if (connected) {
        _startTimer();
      } else {
        stop();
      }
    });
    if (_ws.isConnected) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!_ws.isConnected) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      // If your native channel method name differs, rename 'sendJson'.
      // The point: this MUST become a no-op if NO_SESSION occurs.
      await _ws.send<void>('sendJson', {
        'type': 'command',
        'command': 'players/all',
      });
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _inFlight = false;
  }

  void dispose() {
    stop();
    _connSub?.cancel();
  }
}
