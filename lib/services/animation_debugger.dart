import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'debug_logger.dart';

/// Comprehensive animation debugging utility for diagnosing jank and performance issues.
///
/// Usage:
/// 1. Call AnimationDebugger.startSession('playerExpand') at animation start
/// 2. Call AnimationDebugger.recordFrame() in animation listener (every frame)
/// 3. Call AnimationDebugger.endSession() when animation completes
/// 4. Logs will show frame timing, jank detection, and summary stats
class AnimationDebugger {
  static final _logger = DebugLogger();
  static bool _enabled = true;

  // Session tracking
  static String? _currentSession;
  static int _frameCount = 0;
  static final List<_FrameData> _frames = [];
  static DateTime? _sessionStart;
  static double? _lastAnimationValue;

  // Scheduler binding for frame timing
  static Duration? _lastFrameTime;

  /// Enable or disable animation debugging
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Start a new animation debugging session
  static void startSession(String name) {
    if (!_enabled) return;

    _currentSession = name;
    _frameCount = 0;
    _frames.clear();
    _sessionStart = DateTime.now();
    _lastFrameTime = null;
    _lastAnimationValue = null;

    // Listen to frame timing
    SchedulerBinding.instance.addPostFrameCallback(_onFirstFrame);

    _logger.log('🎬 ANIM[$name] START');
  }

  static void _onFirstFrame(Duration timestamp) {
    _lastFrameTime = timestamp;
  }

  /// Record a frame during animation
  /// [animationValue] - current animation progress (0.0 to 1.0)
  /// [context] - optional context string for this frame
  static void recordFrame(double animationValue, {String? context}) {
    if (!_enabled || _currentSession == null) return;

    final now = DateTime.now();
    final frameTime = SchedulerBinding.instance.currentFrameTimeStamp;

    Duration? frameDuration;
    if (_lastFrameTime != null) {
      frameDuration = frameTime - _lastFrameTime!;
    }
    _lastFrameTime = frameTime;

    // Calculate animation delta
    double? animationDelta;
    if (_lastAnimationValue != null) {
      animationDelta = (animationValue - _lastAnimationValue!).abs();
    }
    _lastAnimationValue = animationValue;

    final frame = _FrameData(
      frameNumber: _frameCount,
      timestamp: now,
      frameDuration: frameDuration,
      animationValue: animationValue,
      animationDelta: animationDelta,
      context: context,
    );

    _frames.add(frame);
    _frameCount++;

    // Log jank immediately (frames > 16.67ms for 60fps)
    if (frameDuration != null && frameDuration.inMicroseconds > 16667) {
      final ms = frameDuration.inMicroseconds / 1000;
      _logger.log('🔴 ANIM[$_currentSession] JANK frame $_frameCount: ${ms.toStringAsFixed(2)}ms (>${(ms/16.67).toStringAsFixed(1)}x target)');
    }
  }

  /// Record a build/layout event during animation
  static void recordBuild(String widgetName) {
    if (!_enabled || _currentSession == null) return;
    _logger.log('🔨 ANIM[$_currentSession] BUILD: $widgetName at frame $_frameCount');
  }

  /// End the current session and log summary
  static void endSession() {
    if (!_enabled || _currentSession == null) return;

    final sessionName = _currentSession!;
    final totalDuration = DateTime.now().difference(_sessionStart!);

    // Calculate statistics
    int jankFrames = 0;
    int severeJankFrames = 0;
    double maxFrameMs = 0;
    double totalFrameMs = 0;
    int measuredFrames = 0;

    for (final frame in _frames) {
      if (frame.frameDuration != null) {
        final ms = frame.frameDuration!.inMicroseconds / 1000;
        totalFrameMs += ms;
        measuredFrames++;

        if (ms > maxFrameMs) maxFrameMs = ms;
        if (ms > 16.67) jankFrames++;
        if (ms > 33.33) severeJankFrames++; // Dropped more than 1 frame
      }
    }

    final avgFrameMs = measuredFrames > 0 ? totalFrameMs / measuredFrames : 0;
    final effectiveFps = avgFrameMs > 0 ? 1000 / avgFrameMs : 0;

    // Build summary
    final buffer = StringBuffer();
    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('🎬 ANIMATION SUMMARY: $sessionName');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('Duration: ${totalDuration.inMilliseconds}ms');
    buffer.writeln('Total frames: $_frameCount');
    buffer.writeln('Measured frames: $measuredFrames');
    buffer.writeln('Average frame: ${avgFrameMs.toStringAsFixed(2)}ms');
    buffer.writeln('Max frame: ${maxFrameMs.toStringAsFixed(2)}ms');
    buffer.writeln('Effective FPS: ${effectiveFps.toStringAsFixed(1)}');
    buffer.writeln('Jank frames (>16.67ms): $jankFrames (${measuredFrames > 0 ? (jankFrames * 100 / measuredFrames).toStringAsFixed(1) : 0}%)');
    buffer.writeln('Severe jank (>33.33ms): $severeJankFrames');

    // List worst frames
    if (_frames.isNotEmpty) {
      final sortedFrames = List<_FrameData>.from(_frames)
        ..sort((a, b) {
          final aMs = a.frameDuration?.inMicroseconds ?? 0;
          final bMs = b.frameDuration?.inMicroseconds ?? 0;
          return bMs.compareTo(aMs);
        });

      final worstFrames = sortedFrames.take(5).where((f) => f.frameDuration != null && f.frameDuration!.inMicroseconds > 16667).toList();

      if (worstFrames.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('Worst frames:');
        for (final frame in worstFrames) {
          final ms = frame.frameDuration!.inMicroseconds / 1000;
          buffer.writeln('  Frame ${frame.frameNumber}: ${ms.toStringAsFixed(2)}ms (anim=${frame.animationValue.toStringAsFixed(3)})');
        }
      }
    }

    buffer.writeln('═══════════════════════════════════════');

    _logger.log(buffer.toString());

    // Reset
    _currentSession = null;
    _frames.clear();
    _sessionStart = null;
    _lastAnimationValue = null;
  }

  /// Log a one-off animation event (for Hero transitions, page transitions, etc.)
  static void logEvent(String event, {String? details}) {
    if (!_enabled) return;
    final detailStr = details != null ? ' - $details' : '';
    _logger.log('🎬 ANIM_EVENT: $event$detailStr');
  }

  /// Log frame callback timing (call this from addPostFrameCallback)
  static void logPostFrame(String context) {
    if (!_enabled) return;
    final frameTime = SchedulerBinding.instance.currentFrameTimeStamp;
    _logger.log('📐 POST_FRAME[$context]: ${frameTime.inMilliseconds}ms');
  }

  /// Create a HeroFlightShuttleBuilder that logs Hero animation progress
  static HeroFlightShuttleBuilder createHeroDebugShuttle(String heroTag) {
    return (
      BuildContext flightContext,
      Animation<double> animation,
      HeroFlightDirection flightDirection,
      BuildContext fromHeroContext,
      BuildContext toHeroContext,
    ) {
      // Log Hero flight start
      if (animation.value < 0.1) {
        logEvent('Hero flight START', details: 'tag=$heroTag, direction=${flightDirection.name}');
      }

      // Add listener for completion (one-shot)
      void onComplete(AnimationStatus status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          logEvent('Hero flight END', details: 'tag=$heroTag, status=${status.name}');
          animation.removeStatusListener(onComplete);
        }
      }
      animation.addStatusListener(onComplete);

      // Return default shuttle (the toHero's child)
      final Hero toHero = toHeroContext.widget as Hero;
      return toHero.child;
    };
  }
}

class _FrameData {
  final int frameNumber;
  final DateTime timestamp;
  final Duration? frameDuration;
  final double animationValue;
  final double? animationDelta;
  final String? context;

  _FrameData({
    required this.frameNumber,
    required this.timestamp,
    this.frameDuration,
    required this.animationValue,
    this.animationDelta,
    this.context,
  });
}
