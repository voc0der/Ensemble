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
  bool _isPausePending = false;  // Flag to stop feed operations during pause
  Completer<void>? _feedCompleter;  // Tracks when current feed operation completes

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
    // This is called from native when buffer is getting low
    // Don't start new feed operations if paused or pause is pending
    // CRITICAL: _isPausePending stays true during pause to block all feeding
    if (_state != PcmPlayerState.playing) return;
    if (_isPausePending) return;
    if (_audioBuffer.isEmpty || _isFeeding) return;

    _feedNextChunk();
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
    // Ignore data if in error state or if pause is pending/active
    // CRITICAL: When paused, _isPausePending stays true to prevent any feeding
    if (_state == PcmPlayerState.error) return;
    if (_isPausePending || _state == PcmPlayerState.paused) {
      // Silently ignore audio data when paused - don't even buffer it
      // This prevents buffer accumulation during pause and any race conditions
      return;
    }

    // Add to buffer
    _audioBuffer.add(audioData);

    // Start playback if not already started
    if (!_isStarted && _state == PcmPlayerState.ready) {
      _startPlayback();
    }

    // NOTE: Auto-resume from paused state has been removed to prevent race conditions.
    // The provider should explicitly call play() when ready to resume.

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
  /// CRITICAL: This loop must yield to the event loop to prevent UI freeze
  Future<void> _feedNextChunk() async {
    if (_isFeeding || _audioBuffer.isEmpty || _isPausePending) return;

    _isFeeding = true;
    _feedCompleter = Completer<void>();

    try {
      int chunksProcessed = 0;

      while (_audioBuffer.isNotEmpty && _state == PcmPlayerState.playing && !_isPausePending) {
        final chunk = _audioBuffer.removeAt(0);

        // Convert Uint8List (raw bytes) to Int16 samples
        // Sendspin sends 16-bit little-endian PCM
        final samples = _bytesToInt16List(chunk);

        // Check pause flag again before the async feed call
        if (samples.isNotEmpty && !_isPausePending) {
          await pcm.FlutterPcmSound.feed(pcm.PcmArrayInt16.fromList(samples));

          // Don't update stats if we got paused during the feed
          if (!_isPausePending) {
            _framesPlayed++;
            _bytesPlayed += chunk.length;
            chunksProcessed++;

            // Log periodically
            if (_framesPlayed % 100 == 0) {
              _logger.log('PcmAudioPlayer: Played $_framesPlayed frames (${(_bytesPlayed / 1024).toStringAsFixed(1)} KB)');
            }
          }
        }

        // CRITICAL: Yield to event loop every few chunks to allow UI to respond
        // This prevents the feed loop from starving the event loop and causing freeze
        if (chunksProcessed % 5 == 0) {
          await Future.delayed(Duration.zero);
        }
      }
    } catch (e) {
      // Don't log errors during pause - expected when player is released
      if (!_isPausePending) {
        _logger.log('PcmAudioPlayer: Error feeding audio: $e');
      }
    }

    _isFeeding = false;
    _feedCompleter?.complete();
    _feedCompleter = null;
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

    // Clear any pending pause flag
    _isPausePending = false;

    if (_state == PcmPlayerState.paused) {
      // Resume from pause - player is still initialized, just resume feeding
      _logger.log('PcmAudioPlayer: Resuming from pause at ${elapsedTime.inSeconds}s');

      _state = PcmPlayerState.playing;
      _startElapsedTimeTimer();

      // Resume feeding - new audio will come from stream
      if (!_isFeeding && _audioBuffer.isNotEmpty) {
        _feedNextChunk();
      }

      _logger.log('PcmAudioPlayer: Resumed playback');
    } else if (_state == PcmPlayerState.ready) {
      await _startPlayback();
      _logger.log('PcmAudioPlayer: Started playback');

      // Start feeding
      if (!_isFeeding && _audioBuffer.isNotEmpty) {
        _feedNextChunk();
      }
    }
  }

  /// Pause playback - stops feeding audio so native buffer drains quickly
  /// Position is preserved via _bytesPlayed tracking
  /// Note: We don't call release() on pause to avoid native deadlocks.
  /// The native buffer is small (~170ms) so audio stops naturally.
  Future<void> pause() async {
    if (_state != PcmPlayerState.playing) return;

    _logger.log('PcmAudioPlayer: Pause requested');

    // Set pause pending flag FIRST to stop feed loop from starting new feeds
    // CRITICAL: This flag must stay true until the pause operation is complete
    _isPausePending = true;

    // Update state immediately so UI reflects pause
    _state = PcmPlayerState.paused;
    _bytesPlayedAtLastPause = _bytesPlayed;
    _stopElapsedTimeTimer();

    // Clear our buffer - no more data will be fed
    _audioBuffer.clear();

    // Wait for any in-flight feed operation to complete (short timeout)
    // This is critical to prevent UI freeze from concurrent FFI calls
    final completer = _feedCompleter;
    if (completer != null && !completer.isCompleted) {
      _logger.log('PcmAudioPlayer: Waiting for in-flight feed to complete');
      try {
        await completer.future.timeout(
          const Duration(milliseconds: 100),
          onTimeout: () {
            _logger.log('PcmAudioPlayer: Feed wait timed out, proceeding');
          },
        );
      } catch (e) {
        _logger.log('PcmAudioPlayer: Feed wait error: $e');
      }
    }

    _isFeeding = false;

    // Don't call release() - it causes native deadlocks
    // Audio will stop naturally as the small native buffer drains (~170ms)
    // We keep the player initialized for faster resume

    // CRITICAL: Keep _isPausePending = true! It's only cleared when play() is called
    // This prevents _onAudioData from auto-resuming and _onFeedRequested from starting feeds
    _logger.log('PcmAudioPlayer: Paused playback at ${elapsedTime.inSeconds}s (buffer will drain)');
  }

  /// Stop playback (clears buffer and resets position)
  Future<void> stop() async {
    // Set pause pending to stop any in-flight feed operations
    _isPausePending = true;
    _isStarted = false;
    _stopElapsedTimeTimer();

    // Clear the feed callback to prevent native code from triggering new feeds
    pcm.FlutterPcmSound.setFeedCallback(null);

    // Wait for any in-progress feed operation to complete (with timeout)
    final completer = _feedCompleter;
    if (completer != null && !completer.isCompleted) {
      await completer.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          _logger.log('PcmAudioPlayer: Feed wait timed out on stop');
        },
      );
    }

    _audioBuffer.clear();
    _isFeeding = false;

    try {
      await pcm.FlutterPcmSound.release();
    } catch (e) {
      _logger.log('PcmAudioPlayer: Error releasing: $e');
    }

    _isPausePending = false;
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
    _isPausePending = true;  // Stop any feed operations
    _isStarted = false;
    _stopElapsedTimeTimer();

    // Clear the feed callback first
    pcm.FlutterPcmSound.setFeedCallback(null);

    // Wait for any in-progress feed operation
    final completer = _feedCompleter;
    if (completer != null && !completer.isCompleted) {
      await completer.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }

    _isFeeding = false;
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
