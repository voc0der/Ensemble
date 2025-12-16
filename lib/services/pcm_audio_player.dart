import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart' as pcm;
import 'debug_logger.dart';

/// Callback type for elapsed time updates
typedef ElapsedTimeCallback = void Function(Duration elapsed);

/// Audio format configuration matching Sendspin protocol
class PcmAudioFormat {
  final int sampleRate;
  final int channels;
  final int bitDepth;

  const PcmAudioFormat({
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitDepth = 16,
  });

  /// Default Sendspin format: 48kHz, stereo, 16-bit PCM
  static const sendspin = PcmAudioFormat();
}

/// Player state for PCM audio
enum PcmPlayerState {
  idle,
  initializing,
  ready,
  playing,
  paused,
  error,
}

/// Service to play raw PCM audio data from Sendspin WebSocket stream
/// Uses flutter_pcm_sound plugin for low-level PCM playback
class PcmAudioPlayer {
  final _logger = DebugLogger();

  PcmPlayerState _state = PcmPlayerState.idle;
  PcmAudioFormat _format = PcmAudioFormat.sendspin;

  StreamSubscription<Uint8List>? _audioSubscription;

  // Audio buffer for smooth playback
  final List<Uint8List> _audioBuffer = [];
  bool _isFeeding = false;
  bool _isStarted = false;

  // Stats
  int _framesPlayed = 0;
  int _bytesPlayed = 0;

  // Elapsed time tracking for notification sync
  Timer? _elapsedTimeTimer;
  final _elapsedTimeController = StreamController<Duration>.broadcast();
  ElapsedTimeCallback? onElapsedTimeUpdate;

  // Track offset for pause/resume (preserves position across pause cycles)
  int _bytesPlayedAtLastPause = 0;
  DateTime? _playbackStartTime;

  PcmPlayerState get state => _state;
  bool get isPlaying => _state == PcmPlayerState.playing;
  bool get isReady => _state == PcmPlayerState.ready || _state == PcmPlayerState.playing || _state == PcmPlayerState.paused;
  int get framesPlayed => _framesPlayed;
  int get bytesPlayed => _bytesPlayed;

  /// Stream of elapsed time updates (emits every 500ms when playing)
  Stream<Duration> get elapsedTimeStream => _elapsedTimeController.stream;

  /// Calculate elapsed playback time from bytes played
  /// For 48kHz stereo 16-bit: 4 bytes per frame, 48000 frames per second
  Duration get elapsedTime {
    // Bytes per frame = channels * (bitDepth / 8) = 2 * 2 = 4
    final bytesPerFrame = _format.channels * (_format.bitDepth ~/ 8);
    final framesFromBytes = _bytesPlayed / bytesPerFrame;
    final elapsedSeconds = framesFromBytes / _format.sampleRate;
    return Duration(milliseconds: (elapsedSeconds * 1000).round());
  }

  /// Get elapsed time in seconds (for convenience)
  double get elapsedTimeSeconds {
    final bytesPerFrame = _format.channels * (_format.bitDepth ~/ 8);
    final framesFromBytes = _bytesPlayed / bytesPerFrame;
    return framesFromBytes / _format.sampleRate;
  }

  /// Initialize the PCM player with the given format
  Future<bool> initialize({PcmAudioFormat? format}) async {
    if (_state == PcmPlayerState.initializing) return false;

    _format = format ?? PcmAudioFormat.sendspin;
    _state = PcmPlayerState.initializing;

    try {
      _logger.log('PcmAudioPlayer: Initializing (${_format.sampleRate}Hz, ${_format.channels}ch, ${_format.bitDepth}bit)');

      // Setup flutter_pcm_sound with Sendspin audio format
      await pcm.FlutterPcmSound.setup(
        sampleRate: _format.sampleRate,
        channelCount: _format.channels,
      );

      // Set feed threshold - request more data when buffer has fewer frames
      // Lower threshold = lower latency but more risk of underruns
      await pcm.FlutterPcmSound.setFeedThreshold(8000);

      // Set up feed callback for when buffer needs more data
      pcm.FlutterPcmSound.setFeedCallback(_onFeedRequested);

      // Set log level for debugging
      await pcm.FlutterPcmSound.setLogLevel(pcm.LogLevel.standard);

      _state = PcmPlayerState.ready;
      _logger.log('PcmAudioPlayer: Initialized successfully');
      return true;
    } catch (e) {
      _logger.log('PcmAudioPlayer: Initialization failed: $e');
      _state = PcmPlayerState.error;
      return false;
    }
  }

  /// Callback when flutter_pcm_sound needs more audio data
  void _onFeedRequested(int remainingFrames) {
    // This is called when buffer is getting low
    // We'll feed from our buffer if we have data
    if (_audioBuffer.isNotEmpty && !_isFeeding) {
      _feedNextChunk();
    }
  }

  /// Connect to a Sendspin audio data stream and start playback
  Future<bool> connectToStream(Stream<Uint8List> audioStream) async {
    if (_state == PcmPlayerState.error || _state == PcmPlayerState.idle) {
      _logger.log('PcmAudioPlayer: Cannot connect - player not initialized');
      return false;
    }

    // Cancel any existing subscription
    await _audioSubscription?.cancel();

    _logger.log('PcmAudioPlayer: Connecting to audio stream');

    // Subscribe to the audio stream
    _audioSubscription = audioStream.listen(
      _onAudioData,
      onError: _onStreamError,
      onDone: _onStreamDone,
    );

    return true;
  }

  /// Handle incoming audio data from the stream
  void _onAudioData(Uint8List audioData) {
    if (_state == PcmPlayerState.error) return;

    // Add to buffer
    _audioBuffer.add(audioData);

    // Start playback if not already started
    if (!_isStarted && _state == PcmPlayerState.ready) {
      _startPlayback();
    }

    // Feed data if not currently feeding
    if (!_isFeeding && _isStarted) {
      _feedNextChunk();
    }
  }

  /// Start audio playback
  Future<void> _startPlayback() async {
    if (_isStarted) return;

    try {
      await pcm.FlutterPcmSound.start();
      _isStarted = true;
      _state = PcmPlayerState.playing;
      _playbackStartTime = DateTime.now();
      _startElapsedTimeTimer();
      _logger.log('PcmAudioPlayer: Started playback');
    } catch (e) {
      _logger.log('PcmAudioPlayer: Error starting playback: $e');
      _state = PcmPlayerState.error;
    }
  }

  /// Start the elapsed time update timer
  void _startElapsedTimeTimer() {
    _elapsedTimeTimer?.cancel();
    _elapsedTimeTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _emitElapsedTime(),
    );
    // Emit immediately
    _emitElapsedTime();
  }

  /// Stop the elapsed time update timer
  void _stopElapsedTimeTimer() {
    _elapsedTimeTimer?.cancel();
    _elapsedTimeTimer = null;
  }

  /// Emit the current elapsed time to listeners
  void _emitElapsedTime() {
    if (_state != PcmPlayerState.playing) return;

    final elapsed = elapsedTime;
    if (!_elapsedTimeController.isClosed) {
      _elapsedTimeController.add(elapsed);
    }
    onElapsedTimeUpdate?.call(elapsed);
  }

  /// Feed the next chunk of audio data to the player
  Future<void> _feedNextChunk() async {
    if (_isFeeding || _audioBuffer.isEmpty) return;

    _isFeeding = true;

    try {
      while (_audioBuffer.isNotEmpty && _state == PcmPlayerState.playing) {
        final chunk = _audioBuffer.removeAt(0);

        // Convert Uint8List (raw bytes) to Int16 samples
        // Sendspin sends 16-bit little-endian PCM
        final samples = _bytesToInt16List(chunk);

        if (samples.isNotEmpty) {
          await pcm.FlutterPcmSound.feed(pcm.PcmArrayInt16.fromList(samples));

          _framesPlayed++;
          _bytesPlayed += chunk.length;

          // Log periodically
          if (_framesPlayed % 100 == 0) {
            _logger.log('PcmAudioPlayer: Played $_framesPlayed frames (${(_bytesPlayed / 1024).toStringAsFixed(1)} KB)');
          }
        }
      }
    } catch (e) {
      _logger.log('PcmAudioPlayer: Error feeding audio: $e');
    }

    _isFeeding = false;
  }

  /// Convert raw bytes (Uint8List) to Int16 samples
  /// Assumes little-endian 16-bit PCM
  List<int> _bytesToInt16List(Uint8List bytes) {
    if (bytes.length < 2) return [];

    final byteData = ByteData.sublistView(bytes);
    final samples = <int>[];

    for (int i = 0; i < bytes.length - 1; i += 2) {
      samples.add(byteData.getInt16(i, Endian.little));
    }

    return samples;
  }

  /// Handle stream errors
  void _onStreamError(dynamic error) {
    _logger.log('PcmAudioPlayer: Stream error: $error');
  }

  /// Handle stream completion
  void _onStreamDone() {
    _logger.log('PcmAudioPlayer: Audio stream ended');
    // Don't stop immediately - let buffered audio finish
  }

  /// Start playback (if paused)
  Future<void> play() async {
    if (_state == PcmPlayerState.error) return;

    if (_state == PcmPlayerState.paused) {
      // Resume from pause - restart timer, keep position
      _state = PcmPlayerState.playing;
      _startElapsedTimeTimer();
      _logger.log('PcmAudioPlayer: Resumed playback from ${elapsedTime.inSeconds}s');

      // Resume feeding
      if (!_isFeeding && _audioBuffer.isNotEmpty) {
        _feedNextChunk();
      }
    } else if (_state == PcmPlayerState.ready) {
      await _startPlayback();
      _logger.log('PcmAudioPlayer: Started playback');

      // Start feeding
      if (!_isFeeding && _audioBuffer.isNotEmpty) {
        _feedNextChunk();
      }
    }
  }

  /// Pause playback
  Future<void> pause() async {
    if (_state != PcmPlayerState.playing) return;

    // flutter_pcm_sound doesn't have a native pause, so we just stop feeding
    // and mark as paused
    _state = PcmPlayerState.paused;
    _bytesPlayedAtLastPause = _bytesPlayed;
    _stopElapsedTimeTimer();
    _logger.log('PcmAudioPlayer: Paused playback at ${elapsedTime.inSeconds}s');
  }

  /// Stop playback (clears buffer and resets position)
  Future<void> stop() async {
    _isStarted = false;
    _audioBuffer.clear();
    _stopElapsedTimeTimer();

    try {
      await pcm.FlutterPcmSound.release();
    } catch (e) {
      _logger.log('PcmAudioPlayer: Error releasing: $e');
    }

    _state = PcmPlayerState.ready;
    _framesPlayed = 0;
    _bytesPlayed = 0;
    _bytesPlayedAtLastPause = 0;
    _playbackStartTime = null;
    _logger.log('PcmAudioPlayer: Stopped playback');

    // Re-initialize for next playback
    await initialize(format: _format);
  }

  /// Reset position to zero (for new track) without stopping playback
  void resetPosition() {
    _framesPlayed = 0;
    _bytesPlayed = 0;
    _bytesPlayedAtLastPause = 0;
    _playbackStartTime = DateTime.now();
    _logger.log('PcmAudioPlayer: Position reset to 0');
    _emitElapsedTime();
  }

  /// Disconnect from audio stream
  Future<void> disconnect() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await stop();
    _logger.log('PcmAudioPlayer: Disconnected from stream');
  }

  /// Release all resources
  Future<void> dispose() async {
    _isFeeding = false;
    _isStarted = false;
    _stopElapsedTimeTimer();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _audioBuffer.clear();

    try {
      await pcm.FlutterPcmSound.release();
    } catch (e) {
      _logger.log('PcmAudioPlayer: Error releasing: $e');
    }

    if (!_elapsedTimeController.isClosed) {
      await _elapsedTimeController.close();
    }

    _state = PcmPlayerState.idle;
    _logger.log('PcmAudioPlayer: Disposed');
  }
}
