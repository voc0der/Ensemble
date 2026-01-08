import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../services/animation_debugger.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import 'animated_icon_button.dart';
import 'global_player_overlay.dart';
import 'volume_control.dart';
import 'player/player_widgets.dart';
import 'player/mini_player_content.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// This widget is designed to be used as a global overlay, positioned above
/// the bottom navigation bar. It uses smooth morphing animations where each
/// element transitions from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  /// Slide offset for hiding the mini player (0.0 = visible, 1.0 = hidden below screen)
  final double slideOffset;

  /// Bounce offset for the player reveal animation (moves mini player down slightly)
  final double bounceOffset;

  /// Callback when swipe-down gesture triggers player reveal
  final VoidCallback? onRevealPlayers;

  /// Whether the device reveal overlay is currently visible
  /// When true, shows player name instead of track name in collapsed state
  final bool isDeviceRevealVisible;

  /// Whether the hint text should be shown
  /// When true, shows "Pull to select players" instead of track info
  final bool isHintVisible;

  const ExpandablePlayer({
    super.key,
    this.slideOffset = 0.0,
    this.bounceOffset = 0.0,
    this.onRevealPlayers,
    this.isDeviceRevealVisible = false,
    this.isHintVisible = false,
  });

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Queue panel slide animation
  late AnimationController _queuePanelController;
  late Animation<double> _queuePanelAnimation;
  // Cached slide position animation (avoids recreating Tween.animate every frame)
  late Animation<Offset> _queueSlideAnimation;

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  bool _isLoadingQueue = false;
  bool _isQueueDragging = false; // True while queue item is being dragged
  bool _queuePanelTargetOpen = false; // Target state for queue panel (separate from animation value)

  // Progress tracking - uses PositionTracker stream as single source of truth
  StreamSubscription<Duration>? _positionSubscription;
  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double?> _seekPositionNotifier = ValueNotifier<double?>(null);

  // Pre-computed static colors to avoid object creation during animation frames
  static const Color _shadowColor = Color(0x4D000000); // Colors.black.withOpacity(0.3)

  // Dimensions
  static double get _collapsedHeight => MiniPlayerLayout.height;
  static const double _collapsedMargin = 12.0; // Increased from 8 to 12 (4px more gap above nav bar)
  static const double _collapsedBorderRadius = 16.0;
  static double get _collapsedArtSize => MiniPlayerLayout.artSize;
  static const double _bottomNavHeight = 56.0;
  static const double _edgeDeadZone = 40.0; // Dead zone for Android back gesture

  // Pastel yellow for grouped players (matches PlayerCard.groupBorderColor)
  static const Color _groupBorderColor = Color(0xFFFFF59D);

  // Track horizontal drag start position
  double? _horizontalDragStartX;

  // Slide animation for device switching - now supports finger-following
  late AnimationController _slideController;
  // ValueNotifier avoids setState during high-frequency drag updates
  final ValueNotifier<double> _slideOffsetNotifier = ValueNotifier(0.0);
  double get _slideOffset => _slideOffsetNotifier.value;
  set _slideOffset(double value) => _slideOffsetNotifier.value = value;
  bool _isSliding = false;
  bool _isDragging = false; // True while finger is actively dragging

  // For peek preview - track which player we'd switch to
  dynamic _peekPlayer; // The player that would be selected if swipe commits
  String? _peekImageUrl; // Image URL for peek player's current track

  // Flag to indicate we're in the middle of a player switch transition
  // When true, we hide main content and show peek content at center
  bool _inTransition = false;

  // Volume swipe state (only active when device reveal is visible)
  bool _isDraggingVolume = false;
  double _dragVolumeLevel = 0.0;
  int _lastVolumeUpdateTime = 0;
  int _lastVolumeDragEndTime = 0; // Track when last drag ended for consecutive swipes
  bool _hasLocalVolumeOverride = false; // True if we've set volume locally
  static const int _volumeThrottleMs = 150; // Only send volume updates every 150ms
  static const int _precisionThrottleMs = 50; // Faster updates in precision mode
  static const int _consecutiveSwipeWindowMs = 5000; // 5 seconds - extended window for consecutive swipes

  // Volume precision mode state
  bool _inVolumePrecisionMode = false;
  Timer? _volumePrecisionTimer;
  Offset? _lastVolumeDragPosition;
  double _lastVolumeLocalX = 0.0; // Last local X position during drag
  bool _volumePrecisionModeEnabled = true; // From settings
  double _volumePrecisionZoomCenter = 0.0; // Volume level when precision mode started
  double _volumePrecisionStartX = 0.0; // Finger X position when precision mode started
  static const int _precisionTriggerMs = 800; // Hold still for 800ms to enter precision mode
  static const double _precisionStillnessThreshold = 5.0; // Max pixels of movement considered "still"
  static const double _precisionSensitivity = 0.1; // Zoomed range (10% = left edge to right edge)

  // Track favorite state for current track
  bool _isCurrentTrackFavorite = false;
  String? _lastTrackUri; // Track which track we last checked favorite status for

  // Cached title height to avoid TextPainter.layout() every animation frame
  // Only invalidate when track name changes (screen width doesn't change during animation)
  double? _cachedExpandedTitleHeight;
  String? _lastMeasuredTrackName;

  // Gesture-driven expansion state
  bool _isVerticalDragging = false;
  double _dragStartY = 0;
  double _dragStartValue = 0;

  // Maximum drag distance for full expand/collapse
  static const double _maxDragDistance = 300.0;

  // Thresholds for committing expand/collapse
  static const double _commitPositionThreshold = 0.3; // 30% progress
  static const double _commitVelocityThreshold = 800.0; // px/s

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Simple curved animation - performant and smooth
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Notify listeners of expansion progress changes
    _controller.addListener(_notifyExpansionProgress);

    // Animation debugging - record every frame
    _controller.addListener(_recordAnimationFrame);

    // Queue panel animation - uses spring physics directly (no CurvedAnimation)
    // Spring simulation already provides natural physics-based easing
    // CurvedAnimation would distort the spring output and cause jerky motion during swipe
    _queuePanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // Use controller directly - spring physics provide the easing
    _queuePanelAnimation = _queuePanelController;
    // Cache the slide animation to avoid recreating Tween.animate() every frame
    _queueSlideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(_queuePanelController);

    // Slide animation for device switching - used for snap/spring animations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      // PERF: Load queue after animation completes, not during
      // This prevents network I/O from competing with animation frames
      if (status == AnimationStatus.completed) {
        _loadQueue();
      } else if (status == AnimationStatus.dismissed) {
        // Close queue panel when player collapses
        _queuePanelController.duration = _queueCloseDuration;
        _queuePanelController.reverse();
      }
    });

    // Subscribe to position tracker stream - single source of truth for playback position
    _subscribeToPositionTracker();

    // Auto-refresh queue when panel is open
    _queuePanelController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _startQueueRefreshTimer();
      } else if (status == AnimationStatus.dismissed) {
        _stopQueueRefreshTimer();
      }
    });

    // Load precision mode setting
    _loadVolumePrecisionModeSetting();
  }

  Future<void> _loadVolumePrecisionModeSetting() async {
    final enabled = await SettingsService.getVolumePrecisionMode();
    if (mounted) {
      _volumePrecisionModeEnabled = enabled;
    }
  }

  void _enterVolumePrecisionMode() {
    if (_inVolumePrecisionMode) return;
    HapticFeedback.mediumImpact(); // Vibrate to indicate precision mode
    setState(() {
      _inVolumePrecisionMode = true;
      _volumePrecisionZoomCenter = _dragVolumeLevel; // Capture current volume as zoom center
      _volumePrecisionStartX = _lastVolumeLocalX; // Capture finger position at entry
    });
  }

  void _exitVolumePrecisionMode() {
    _volumePrecisionTimer?.cancel();
    _volumePrecisionTimer = null;
    if (!_inVolumePrecisionMode) return;
    setState(() {
      _inVolumePrecisionMode = false;
    });
  }

  Timer? _queueRefreshTimer;

  void _startQueueRefreshTimer() {
    _stopQueueRefreshTimer();
    // Refresh queue at configured interval when panel is open
    _queueRefreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted && isQueuePanelOpen) {
        _loadQueue();
      }
    });
  }

  void _stopQueueRefreshTimer() {
    _queueRefreshTimer?.cancel();
    _queueRefreshTimer = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _queuePanelController.dispose();
    _slideController.dispose();
    _slideOffsetNotifier.dispose();
    _positionSubscription?.cancel();
    _queueRefreshTimer?.cancel();
    _volumePrecisionTimer?.cancel();
    _progressNotifier.dispose();
    _seekPositionNotifier.dispose();
    super.dispose();
  }

  void _recordAnimationFrame() {
    AnimationDebugger.recordFrame(_controller.value);
  }

  // Animation durations - asymmetric for snappier collapse
  static const Duration _expandDuration = Duration(milliseconds: 280);
  static const Duration _collapseDuration = Duration(milliseconds: 200);
  static const Duration _queueOpenDuration = Duration(milliseconds: 320);
  static const Duration _queueCloseDuration = Duration(milliseconds: 220);

  // Spring description for queue panel animations
  // Higher damping ratio prevents oscillation and ensures clean settling
  // Critical damping = 2 * sqrt(stiffness * mass) = 2 * sqrt(550) ≈ 47
  // Using damping slightly above critical for overdamped (no bounce) behavior
  // PERF: Increased stiffness from 400→550 for snappier animation
  static const SpringDescription _queueSpring = SpringDescription(
    mass: 1.0,
    stiffness: 550.0,
    damping: 50.0, // Overdamped - no oscillation, clean settle
  );

  void expand() {
    if (_isVerticalDragging) return;
    AnimationDebugger.startSession('playerExpand');
    _controller.duration = _expandDuration;
    _controller.forward().then((_) {
      AnimationDebugger.endSession();
    });
  }

  void collapse() {
    if (_isVerticalDragging) return;
    // If queue panel is open, close it first instead of collapsing player
    // This prevents both from closing on a single back press
    if (isQueuePanelOpen) {
      closeQueuePanel();
      return;
    }
    AnimationDebugger.startSession('playerCollapse');
    // Instantly hide queue panel when collapsing to avoid visual glitches
    // during Android's predictive back gesture (only reached if queue already closed)
    _queuePanelController.value = 0;
    _queuePanelTargetOpen = false;
    _controller.duration = _collapseDuration;
    _controller.reverse().then((_) {
      AnimationDebugger.endSession();
    });
  }

  /// Handle vertical drag start - begin gesture-driven expansion
  void _handleVerticalDragStart(DragStartDetails details) {
    _isVerticalDragging = true;
    _dragStartY = details.globalPosition.dy;
    _dragStartValue = _controller.value;
    _controller.stop(); // Stop any running animation
  }

  /// Handle vertical drag update - finger tracking
  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDragging) return;

    final dragDelta = _dragStartY - details.globalPosition.dy;
    // Swipe up = positive delta = expand (increase value)
    // Swipe down = negative delta = collapse (decrease value)
    final normalizedDelta = dragDelta / _maxDragDistance;
    final newValue = (_dragStartValue + normalizedDelta).clamp(0.0, 1.0);

    _controller.value = newValue;
  }

  /// Handle vertical drag end - decide to commit or snap back
  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_isVerticalDragging) return;
    _isVerticalDragging = false;

    final velocity = details.primaryVelocity ?? 0;
    final currentValue = _controller.value;

    // Determine direction based on velocity first, then position
    bool shouldExpand;
    if (velocity.abs() > _commitVelocityThreshold) {
      // High velocity: use velocity direction (negative = swipe up = expand)
      shouldExpand = velocity < 0;
    } else if (currentValue > _commitPositionThreshold && currentValue < (1 - _commitPositionThreshold)) {
      // In the middle zone: use velocity direction if any, otherwise snap to nearest
      shouldExpand = velocity < 0 || (velocity == 0 && currentValue > 0.5);
    } else {
      // Near edges: commit to nearest endpoint
      shouldExpand = currentValue > 0.5;
    }

    // Animate to target with appropriate duration
    if (shouldExpand) {
      if (currentValue < 1.0) {
        AnimationDebugger.startSession('playerExpand');
        _controller.duration = _expandDuration;
        _controller.forward().then((_) {
          AnimationDebugger.endSession();
        });
      }
    } else {
      if (currentValue > 0.0) {
        AnimationDebugger.startSession('playerCollapse');
        _queuePanelController.value = 0;
        _queuePanelTargetOpen = false;
        _controller.duration = _collapseDuration;
        _controller.reverse().then((_) {
          AnimationDebugger.endSession();
        });
      }
    }
  }

  bool get isExpanded => _controller.value > 0.5;

  double get expansionProgress => _controller.value;

  Color? _currentExpandedBgColor;
  Color? get currentExpandedBgColor => _currentExpandedBgColor;
  Color? _currentExpandedPrimaryColor;

  void _notifyExpansionProgress() {
    playerExpansionNotifier.value = PlayerExpansionState(
      _controller.value,
      _currentExpandedBgColor,
      _currentExpandedPrimaryColor,
    );
  }

  void _subscribeToPositionTracker() {
    _positionSubscription?.cancel();
    // Subscribe to position tracker stream - single source of truth
    // This eliminates race conditions between multiple timers
    final maProvider = context.read<MusicAssistantProvider>();
    _positionSubscription = maProvider.positionTracker.positionStream.listen((position) {
      if (!mounted) return;
      _progressNotifier.value = position.inSeconds;
    });
  }

  Future<void> _loadQueue() async {
    if (_isLoadingQueue) return;

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player == null) {
      if (mounted) setState(() => _isLoadingQueue = false);
      return;
    }

    // 1. Show cached queue immediately (if available)
    // Only load from cache if we don't already have a queue (preserves optimistic updates)
    if (_queue == null) {
      final cachedQueue = await maProvider.getCachedQueue(player.playerId);
      if (cachedQueue != null && cachedQueue.items.isNotEmpty && mounted) {
        setState(() {
          _queue = cachedQueue;
          _isLoadingQueue = false;
        });
      } else {
        setState(() => _isLoadingQueue = true);
      }
    }

    // 2. Fetch fresh queue in background
    if (maProvider.api != null) {
      try {
        final freshQueue = await maProvider.getQueue(player.playerId);
        if (mounted && freshQueue != null) {
          debugPrint('🔀 Queue loaded: shuffle=${freshQueue.shuffle}, shuffleEnabled=${freshQueue.shuffleEnabled}');
          // Check if queue items were reordered by comparing first few item IDs
          bool itemsReordered = false;
          if (_queue != null && _queue!.items.isNotEmpty && freshQueue.items.isNotEmpty) {
            // Compare first 3 items to detect reordering (shuffle changes item order)
            final maxCheck = (_queue!.items.length < 3 ? _queue!.items.length : 3).clamp(1, freshQueue.items.length);
            for (int i = 0; i < maxCheck; i++) {
              if (_queue!.items[i].queueItemId != freshQueue.items[i].queueItemId) {
                itemsReordered = true;
                debugPrint('🔀 Queue items reordered detected at position $i');
                break;
              }
            }
          }
          // Update if queue metadata or item order changed
          final queueChanged = _queue == null ||
              _queue!.items.length != freshQueue.items.length ||
              _queue!.currentIndex != freshQueue.currentIndex ||
              _queue!.shuffle != freshQueue.shuffle ||
              itemsReordered;
          if (queueChanged) {
            debugPrint('🔀 Queue changed, updating UI (reordered=$itemsReordered)');
            setState(() {
              _queue = freshQueue;
              _isLoadingQueue = false;
            });
          }
        }
      } catch (e) {
        // Silent failure - keep showing cached queue
      }
    }

    if (mounted && _isLoadingQueue) {
      setState(() => _isLoadingQueue = false);
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    if (_lastImageUrl == imageUrl) return;
    _lastImageUrl = imageUrl;

    try {
      final colorSchemes = await PaletteHelper.extractColorSchemes(
        CachedNetworkImageProvider(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });

        // Share adaptive colors globally via ThemeProvider
        final themeProvider = context.read<ThemeProvider>();
        themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2);
      }
    } catch (e) {
      // Silently ignore color extraction errors
    }
  }

  Future<void> _toggleShuffle() async {
    debugPrint('🔀 Shuffle button pressed');
    if (_queue == null) {
      debugPrint('🔀 Shuffle: _queue is null, returning');
      return;
    }
    final newShuffleState = !_queue!.shuffle;
    debugPrint('🔀 Shuffle: current=${_queue!.shuffle}, toggling to $newShuffleState');

    // Optimistically update local state for immediate visual feedback
    setState(() {
      _queue = PlayerQueue(
        playerId: _queue!.playerId,
        items: _queue!.items,
        currentIndex: _queue!.currentIndex,
        shuffleEnabled: newShuffleState,
        repeatMode: _queue!.repeatMode,
      );
    });
    debugPrint('🔀 Shuffle: optimistic update applied, shuffleEnabled=$newShuffleState');

    final maProvider = context.read<MusicAssistantProvider>();
    // Toggle: if currently shuffled, disable; if not shuffled, enable
    await maProvider.toggleShuffle(_queue!.playerId, newShuffleState);
    debugPrint('🔀 Shuffle: command sent, waiting for server to reorder queue');
    // Small delay to allow server to finish reordering queue items
    await Future.delayed(const Duration(milliseconds: 150));
    debugPrint('🔀 Shuffle: reloading queue');
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;

    // Calculate next repeat mode: off -> all -> one -> off
    String nextMode;
    switch (_queue!.repeatMode) {
      case 'off':
      case null:
        nextMode = 'all';
        break;
      case 'all':
        nextMode = 'one';
        break;
      case 'one':
        nextMode = 'off';
        break;
      default:
        nextMode = 'off';
    }

    // Optimistically update local state for immediate visual feedback
    setState(() {
      _queue = PlayerQueue(
        playerId: _queue!.playerId,
        items: _queue!.items,
        currentIndex: _queue!.currentIndex,
        shuffleEnabled: _queue!.shuffleEnabled,
        repeatMode: nextMode,
      );
    });

    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.setRepeatMode(_queue!.playerId, nextMode);
    await _loadQueue();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;

    // For audiobooks and long content (>= 1 hour), show hours
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleQueuePanel() {
    if (_queuePanelController.isAnimating) return;
    // Use threshold check instead of exact equality (spring may not land exactly at 0/1)
    if (_queuePanelController.value < 0.1) {
      _openQueuePanelWithSpring();
    } else {
      _closeQueuePanelWithSpring();
    }
  }

  /// Open queue panel with spring physics for natural feel
  void _openQueuePanelWithSpring() {
    HapticFeedback.lightImpact();
    // setState ensures PopScope rebuilds with correct canPop value
    setState(() {
      _queuePanelTargetOpen = true;
    });
    // Use overdamped spring - settles cleanly without oscillation or snap
    final simulation = SpringSimulation(
      _queueSpring,
      _queuePanelController.value,
      1.0,
      0.0, // velocity
    );
    _queuePanelController.animateWith(simulation);
  }

  /// Close queue panel with spring physics
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  void _closeQueuePanelWithSpring({double velocity = 0.0, bool withHaptic = true}) {
    // setState ensures PopScope rebuilds with correct canPop value
    setState(() {
      _queuePanelTargetOpen = false;
    });
    if (withHaptic) {
      HapticFeedback.lightImpact();
    }
    // Use overdamped spring for snappy close without oscillation
    // Slightly stiffer than open spring for quicker settle
    // PERF: Increased stiffness from 450→600 for snappier close
    const closeSpring = SpringDescription(
      mass: 1.0,
      stiffness: 600.0,
      damping: 52.0, // Overdamped - no bounce, clean settle
    );
    final simulation = SpringSimulation(
      closeSpring,
      _queuePanelController.value,
      0.0,
      velocity,
    );
    _queuePanelController.animateWith(simulation);
  }

  bool get isQueuePanelOpen => _queuePanelController.value > 0.5;

  /// Whether queue panel is intended to be open (target state, not animation value)
  /// Use this for back gesture handling to avoid timing issues during animations
  bool get isQueuePanelTargetOpen => _queuePanelTargetOpen;

  /// Close queue panel if open (for external access via GlobalPlayerOverlay)
  /// [withHaptic]: Set to false for Android back gesture (system provides haptic)
  void closeQueuePanel({bool withHaptic = true}) {
    // Use target state, not animation value, to handle rapid open-close
    // Allow closing even during animation by stopping it first
    if (_queuePanelTargetOpen) {
      if (_queuePanelController.isAnimating) {
        _queuePanelController.stop();
      }
      _closeQueuePanelWithSpring(withHaptic: withHaptic);
    }
  }

  /// Update favorite status when track changes
  void _updateFavoriteStatus(dynamic currentTrack) {
    if (currentTrack == null) {
      _isCurrentTrackFavorite = false;
      _lastTrackUri = null;
      return;
    }

    final trackUri = currentTrack.uri as String?;
    if (trackUri != _lastTrackUri) {
      _lastTrackUri = trackUri;
      _isCurrentTrackFavorite = currentTrack.favorite == true;
    }
  }

  /// Toggle favorite status for current track (with offline queuing support)
  Future<void> _toggleCurrentTrackFavorite(dynamic currentTrack) async {
    if (currentTrack == null) return;

    final maProvider = context.read<MusicAssistantProvider>();

    try {
      bool success;

      if (_isCurrentTrackFavorite) {
        // Remove from favorites - need library_item_id (numeric)
        int? libraryItemId;

        if (currentTrack.provider == 'library') {
          // If provider is library, itemId is the library ID
          libraryItemId = int.tryParse(currentTrack.itemId.toString());
        } else if (currentTrack.providerMappings != null) {
          // Find the library mapping to get the library ID
          final mappings = currentTrack.providerMappings as List<dynamic>?;
          if (mappings != null) {
            for (final mapping in mappings) {
              if (mapping.providerInstance == 'library') {
                libraryItemId = int.tryParse(mapping.itemId.toString());
                break;
              }
            }
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'track',
            libraryItemId: libraryItemId,
          );
        } else {
          throw Exception('Could not determine library ID for this track');
        }
      } else {
        // Add to favorites - use the source provider (not library)
        String actualProvider = currentTrack.provider?.toString() ?? 'library';
        String actualItemId = currentTrack.itemId?.toString() ?? '';

        if (currentTrack.providerMappings != null) {
          final mappings = currentTrack.providerMappings as List<dynamic>?;
          if (mappings != null && mappings.isNotEmpty) {
            // Find a non-library provider mapping
            // Use providerDomain (e.g., "spotify") not providerInstance (e.g., "spotify--xyz")
            for (final mapping in mappings) {
              if (mapping.available == true && mapping.providerInstance != 'library') {
                actualProvider = mapping.providerDomain;
                actualItemId = mapping.itemId;
                break;
              }
            }
            // Fallback to first available if no non-library found
            if (actualProvider == 'library') {
              for (final mapping in mappings) {
                if (mapping.available == true) {
                  actualProvider = mapping.providerDomain;
                  actualItemId = mapping.itemId;
                  break;
                }
              }
            }
          }
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          itemId: actualItemId,
          provider: actualProvider,
        );
      }

      if (success) {
        // Toggle local state
        setState(() {
          _isCurrentTrackFavorite = !_isCurrentTrackFavorite;
        });

        // Invalidate home cache so favorites are updated
        maProvider.invalidateHomeCache();

        // Show feedback (different message if offline)
        if (mounted) {
          final isOffline = !maProvider.isConnected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? S.of(context)!.actionQueuedForSync
                    : (_isCurrentTrackFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.failedToUpdateFavorite(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Show fullscreen album art overlay
  void _showFullscreenArt(BuildContext context, String? imageUrl) {
    if (imageUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
                  Navigator.of(context).pop();
                }
              },
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: Hero(
                    tag: 'fullscreen_album_art',
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 3.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        memCacheWidth: 1024,
                        memCacheHeight: 1024,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Get available players sorted alphabetically (consistent with device selector)
  List<dynamic> _getAvailablePlayersSorted(MusicAssistantProvider maProvider) {
    // Use the provider's already-sorted list, filter for available only
    return maProvider.availablePlayers.where((p) => p.available).toList();
  }

  /// Get the next or previous player relative to current selection
  dynamic _getAdjacentPlayer(MusicAssistantProvider maProvider, {required bool next}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return null;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    if (currentIndex == -1) return players[0];

    int adjacentIndex;
    if (next) {
      adjacentIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    } else {
      adjacentIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    }

    return players[adjacentIndex];
  }

  // Cache for peek track data
  dynamic _peekTrack;

  /// Cycle to the next available player (for swipe gesture)
  void _cycleToNextPlayer(MusicAssistantProvider maProvider, {bool reverse = false}) {
    final players = _getAvailablePlayersSorted(maProvider);
    if (players.length <= 1) return;

    final selectedPlayerId = maProvider.selectedPlayer?.playerId;
    final currentIndex = players.indexWhere((p) => p.playerId == selectedPlayerId);

    // If current player not found in list, start from beginning
    if (currentIndex == -1) {
      HapticFeedback.mediumImpact();
      maProvider.selectPlayer(players[0]);
      return;
    }

    int nextIndex;
    if (reverse) {
      nextIndex = currentIndex <= 0 ? players.length - 1 : currentIndex - 1;
    } else {
      nextIndex = currentIndex >= players.length - 1 ? 0 : currentIndex + 1;
    }

    // Haptic feedback on device switch
    HapticFeedback.mediumImpact();

    // Animate slide transition
    _animateSlide(reverse ? 1 : -1, () {
      maProvider.selectPlayer(players[nextIndex]);
    });
  }

  /// Handle real-time drag updates for finger-following swipe
  void _handleHorizontalDragUpdate(DragUpdateDetails details, MusicAssistantProvider maProvider, double containerWidth) {
    if (_isSliding) return;

    // Start tracking if not already
    if (!_isDragging) {
      _isDragging = true;
      _peekPlayer = null;
      _peekImageUrl = null;
      _peekTrack = null;
    }

    // Calculate normalized offset (-1 to 1 range)
    // Negative = dragging left (showing next player from right)
    // Positive = dragging right (showing previous player from left)
    final delta = details.primaryDelta ?? 0;
    final normalizedDelta = delta / containerWidth;
    final newSlideOffset = (_slideOffset + normalizedDelta).clamp(-1.0, 1.0);

    // Update slideOffset via ValueNotifier (no setState needed - avoids 60fps rebuilds)
    _slideOffset = newSlideOffset;

    // Only trigger setState when peek player changes (not every frame)
    if (_slideOffset != 0) {
      _updatePeekPlayerState(maProvider, _slideOffset);
    }
  }

  /// Update peek player state variables - only calls setState when peek player changes
  void _updatePeekPlayerState(MusicAssistantProvider maProvider, double dragDirection) {
    // dragDirection < 0 means swiping left (next player)
    // dragDirection > 0 means swiping right (previous player)
    final isNext = dragDirection < 0;
    final newPeekPlayer = _getAdjacentPlayer(maProvider, next: isNext);

    // Only setState when peek player actually changes (prevents unnecessary rebuilds)
    if (newPeekPlayer?.playerId != _peekPlayer?.playerId) {
      setState(() {
        _peekPlayer = newPeekPlayer;
        // Get the peek player's current track image if available
        if (_peekPlayer != null) {
          _peekTrack = maProvider.getCachedTrackForPlayer(_peekPlayer.playerId);
          _peekImageUrl = _peekTrack != null ? maProvider.getImageUrl(_peekTrack, size: 512) : null;
        } else {
          _peekTrack = null;
          _peekImageUrl = null;
        }
      });
    }
  }

  /// Handle drag end - either commit to next player or snap back
  void _handleHorizontalDragEnd(DragEndDetails details, MusicAssistantProvider maProvider) {
    if (!_isDragging || _isSliding) {
      _isDragging = false;
      return;
    }

    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;

    // Thresholds for committing the swipe
    const commitThreshold = 0.3; // 30% of width
    const velocityThreshold = 500.0; // px/s

    final shouldCommit = _slideOffset.abs() > commitThreshold || velocity.abs() > velocityThreshold;
    final direction = _slideOffset != 0 ? _slideOffset.sign : (velocity != 0 ? -velocity.sign : 0);

    if (shouldCommit && _peekPlayer != null && direction != 0) {
      // Commit: animate to full slide, switch player, then reset
      // Note: Don't clear _peekPlayer here - let _animateCommit handle cleanup
      // so the peek content can remain visible during the transition
      _animateCommit(direction.toInt(), () {
        HapticFeedback.mediumImpact();
        maProvider.selectPlayer(_peekPlayer);
      });
    } else {
      // Cancel: spring back to center
      _animateSnapBack();
    }
  }

  /// Animate committing to the next/previous player
  void _animateCommit(int direction, VoidCallback onSwitch) {
    if (_isSliding) return;

    // Mark transition state in setState to ensure rebuilds happen properly
    setState(() {
      _isSliding = true;
      // Mark transition BEFORE animation - this keeps peek content visible
      // and hides main content to prevent any flash
      _inTransition = true;
    });

    final startOffset = _slideOffset;
    final targetOffset = direction < 0 ? -1.0 : 1.0;

    _slideController.reset();

    void animateToTarget() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutCubic.transform(_slideController.value);
      // ValueNotifier triggers AnimatedBuilder rebuild - no setState needed
      _slideOffset = startOffset + (targetOffset - startOffset) * curvedValue;
    }

    _slideController.addListener(animateToTarget);
    _slideController.duration = const Duration(milliseconds: 150);

    _slideController.forward().then((_) {
      if (!mounted) return;

      _slideController.removeListener(animateToTarget);

      // Cache the peek data BEFORE switching - we'll use this to crossfade
      final cachedPeekPlayer = _peekPlayer;
      final cachedPeekTrack = _peekTrack;
      final cachedPeekImageUrl = _peekImageUrl;

      // Switch the player - this sets currentTrack from cache in the provider
      onSwitch();

      // Get the new track state
      final maProvider = context.read<MusicAssistantProvider>();
      final newTrack = maProvider.currentTrack;

      // Move peek content to center position (slideOffset = 0) while keeping it visible.
      // The main content is hidden via _inTransition flag.
      // This creates a seamless visual - peek content is already at center.
      _slideOffset = 0.0; // ValueNotifier triggers AnimatedBuilder rebuild
      setState(() {
        _isSliding = false;
        // Keep _inTransition = true and peek data intact
      });

      if (newTrack != null) {
        // Switching to a playing player - need to wait for image to be ready
        // before showing main content and hiding peek
        final newImageUrl = maProvider.getImageUrl(newTrack, size: 512);

        if (newImageUrl != null && newImageUrl == cachedPeekImageUrl) {
          // Same image - can transition immediately
          _completeTransition();
        } else if (newImageUrl != null) {
          // Different image - precache it first, then transition
          _precacheAndTransition(newImageUrl);
        } else {
          // No image - transition after frame
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      } else {
        // Switching to non-playing player - DeviceSelectorBar will show
        // Wait for it to render, then complete transition
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        });
      }

      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Precache an image and then complete the transition
  void _precacheAndTransition(String imageUrl) {
    // Use CachedNetworkImage's cache to ensure image is ready
    final imageProvider = CachedNetworkImageProvider(imageUrl);
    final imageStream = imageProvider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;

    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        imageStream.removeListener(listener);
        if (mounted) {
          // Image is now in memory cache - safe to transition
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _completeTransition();
          });
        }
      },
      onError: (exception, stackTrace) {
        imageStream.removeListener(listener);
        // Even on error, complete the transition
        if (mounted) _completeTransition();
      },
    );

    imageStream.addListener(listener);

    // Safety timeout - don't wait forever
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _inTransition) {
        imageStream.removeListener(listener);
        _completeTransition();
      }
    });
  }

  /// Complete the transition by hiding peek content and showing main content
  void _completeTransition() {
    if (!mounted) return;
    setState(() {
      _inTransition = false;
      _peekPlayer = null;
      _peekTrack = null;
      _peekImageUrl = null;
    });
  }

  /// Animate snapping back to center (cancelled swipe)
  void _animateSnapBack() {
    if (_isSliding) return;
    _isSliding = true;

    final startOffset = _slideOffset;
    _slideController.reset();

    void animateBack() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutBack.transform(_slideController.value);
      // ValueNotifier triggers AnimatedBuilder rebuild - no setState needed
      _slideOffset = startOffset * (1.0 - curvedValue);
    }

    _slideController.addListener(animateBack);
    _slideController.duration = const Duration(milliseconds: 220); // Snappier snap-back

    _slideController.forward().then((_) {
      if (!mounted) return;
      _slideController.removeListener(animateBack);
      // Update slideOffset via ValueNotifier (triggers rebuild)
      _slideOffset = 0.0;
      // Other state changes still need setState
      setState(() {
        _isSliding = false;
        _peekPlayer = null;
        _peekImageUrl = null;
      });
      _slideController.duration = const Duration(milliseconds: 250); // Reset default
    });
  }

  /// Legacy method - now calls new commit animation
  void _animateSlide(int direction, VoidCallback onComplete) {
    _animateCommit(direction, onComplete);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show if no player selected
        if (selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        // Get image URL for current track
        final imageUrl = currentTrack != null
            ? maProvider.getImageUrl(currentTrack, size: 512)
            : null;

        // Extract colors for adaptive theme
        if (themeProvider.adaptiveTheme && imageUrl != null) {
          _extractColors(imageUrl);
        }

        // Update favorite status when track changes
        _updateFavoriteStatus(currentTrack);

        // Sync progress notifier with position tracker
        // This ensures the progress bar shows correct position on expand,
        // after seek, or when switching players
        final currentPosition = maProvider.positionTracker.currentPosition.inSeconds;
        if (_progressNotifier.value != currentPosition) {
          // Use addPostFrameCallback to avoid updating during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _progressNotifier.value = currentPosition;
            }
          });
        }

        // Handle Android back button - close queue panel first, then collapse player
        // Use _queuePanelTargetOpen (intent) instead of animation value for reliable back handling
        // This prevents race conditions where animation value crosses threshold during gesture
        return PopScope(
          canPop: !_queuePanelTargetOpen && !isExpanded,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              if (_queuePanelTargetOpen) {
                // Always close queue panel on back, even if animating
                // Stop any existing animation and start close
                if (_queuePanelController.isAnimating) {
                  _queuePanelController.stop();
                }
                // No haptic - Android back gesture provides its own haptic feedback
                _closeQueuePanelWithSpring(withHaptic: false);
              } else if (isExpanded) {
                // Only collapse if not already animating
                if (!_controller.isAnimating) {
                  collapse();
                }
              }
            }
          },
          child: AnimatedBuilder(
            // PERF: Only include _expandAnimation and _slideOffsetNotifier
            // Queue panel has its own AnimatedBuilder - don't rebuild entire player on queue animation
            animation: Listenable.merge([_expandAnimation, _slideOffsetNotifier]),
            builder: (context, _) {
              // If no track is playing, show device selector bar
              if (currentTrack == null) {
                return _buildDeviceSelectorBar(context, maProvider, selectedPlayer, themeProvider);
              }
              return _buildMorphingPlayer(
                context,
                maProvider,
                selectedPlayer,
                currentTrack,
                imageUrl,
                themeProvider,
              );
            },
          ),
        );
      },
    );
  }

  /// Build a compact device selector bar when no track is playing
  Widget _buildDeviceSelectorBar(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    ThemeProvider themeProvider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    // Use viewPadding to match BottomNavigationBar's height calculation
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    final backgroundColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    final textColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;

    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final bottomOffset = bottomNavSpace + _collapsedMargin;
    final width = screenSize.width - (_collapsedMargin * 2);

    // Apply slide offset for hiding and bounce offset for reveal animation
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + bottomOffset + 20);
    final bounceDownAmount = widget.bounceOffset;
    final adjustedBottomOffset = bottomOffset - slideDownAmount - bounceDownAmount;

    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;

    return Positioned(
      left: _collapsedMargin,
      right: _collapsedMargin,
      bottom: adjustedBottomOffset,
      child: GestureDetector(
        // Tap to dismiss player reveal (matching _buildMorphingPlayer behavior)
        onTap: widget.isDeviceRevealVisible ? GlobalPlayerOverlay.dismissPlayerReveal : null,
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! > 5 && widget.onRevealPlayers != null) {
            widget.onRevealPlayers!();
          }
        },
        child: DeviceSelectorBar(
        selectedPlayer: selectedPlayer,
        peekPlayer: _peekPlayer,
        hasMultiplePlayers: hasMultiplePlayers,
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: width,
        height: _collapsedHeight,
        borderRadius: _collapsedBorderRadius,
        slideOffset: _slideOffset,
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, width);
        },
        onHorizontalDragEnd: (details) {
          // Check for edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          _handleHorizontalDragEnd(details, maProvider);
        },
        onPowerToggle: () => maProvider.togglePower(selectedPlayer.playerId),
      ),
      ),
    );
  }

  Widget _buildMorphingPlayer(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    ThemeProvider themeProvider,
  ) {
    final screenSize = MediaQuery.of(context).size;
    // Use viewPadding (not padding) to match BottomNavigationBar's height calculation
    // viewPadding represents permanent system UI, padding can change (e.g., keyboard)
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Animation progress
    final t = _expandAnimation.value;

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    // Color transitions - mini player uses adaptive primaryContainer (darker tinted color)
    final collapsedBg = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.primaryContainer
        : colorScheme.primaryContainer;
    // Create a darker shade for the "unplayed" portion of progress bar
    final collapsedBgUnplayed = Color.lerp(collapsedBg, Colors.black, 0.3)!;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF121212);
    final expandedPrimary = adaptiveScheme?.primary;
    // Always update to current value - don't preserve stale adaptive colors
    _currentExpandedBgColor = expandedBg;
    _currentExpandedPrimaryColor = expandedPrimary;
    // When collapsed, use the darker unplayed color as base (progress bar will overlay the played portion)
    // When expanded, transition to the normal background
    final backgroundColor = Color.lerp(t < 0.5 ? collapsedBgUnplayed : collapsedBg, expandedBg, t)!;

    final collapsedTextColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;
    // Use colorScheme.onSurface as fallback instead of Colors.white for light theme support
    final expandedTextColor = adaptiveScheme?.onSurface ?? colorScheme.onSurface;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    // Use colorScheme.primary as fallback instead of Colors.white for light theme support
    final primaryColor = adaptiveScheme?.primary ?? colorScheme.primary;

    // Always position above bottom nav bar
    // Overlap by 2px when expanded to eliminate any subpixel rendering gaps
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    final expandedBottomOffset = bottomNavSpace - 2;
    final expandedHeight = screenSize.height - bottomNavSpace + 2;

    // Apply slide offset to hide mini player (slides down off-screen)
    // Apply bounce offset for reveal animation (small downward movement)
    // Smoothly fade out offsets as animation progresses (continuous, no discontinuity)
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + collapsedBottomOffset + 20);
    final bounceDownAmount = widget.bounceOffset;
    // Fade out slide/bounce effects smoothly over first 15% of animation
    final offsetFade = (1.0 - (t / 0.15)).clamp(0.0, 1.0);
    final baseBottomOffset = _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);
    final slideAdjustedBottomOffset = baseBottomOffset - (slideDownAmount + bounceDownAmount) * offsetFade;

    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final width = _lerpDouble(collapsedWidth, screenSize.width, t);
    final height = _lerpDouble(_collapsedHeight, expandedHeight, t);
    final horizontalMargin = _lerpDouble(_collapsedMargin, 0, t);
    // Use slide-adjusted offset when collapsed, normal lerp otherwise
    final bottomOffset = slideAdjustedBottomOffset;
    final borderRadius = _lerpDouble(_collapsedBorderRadius, 0, t);

    // ===========================================
    // EXPANDED LAYOUT - Vertical rhythm based design
    // ===========================================
    // Using 8px grid for consistent spacing
    // Header: 48px (player name area)
    // Art: proportional to screen, centered
    // Track info: clear hierarchy with breathing room
    // Progress: slim, elegant
    // Controls: generously spaced
    // Volume: bottom anchored

    final headerHeight = 48.0;
    final contentPadding = 32.0; // horizontal padding for content

    // Art sizing - larger on bigger screens, max 85% of width
    final maxArtSize = screenSize.width - (contentPadding * 2);
    final expandedArtSize = (maxArtSize * 0.92).clamp(280.0, 400.0);
    final artSize = _lerpDouble(_collapsedArtSize, expandedArtSize, t);
    final artBorderRadius = _lerpDouble(0, 12, t); // Square in mini player, rounded when expanded

    // Art position
    final collapsedArtLeft = 0.0;
    final expandedArtLeft = (screenSize.width - expandedArtSize) / 2;
    final artLeft = _lerpDouble(collapsedArtLeft, expandedArtLeft, t);

    final collapsedArtTop = (_collapsedHeight - _collapsedArtSize) / 2; // Center vertically
    final expandedArtTop = topPadding + headerHeight + 16;
    final artTop = _lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Typography - uses shared MiniPlayerLayout constants for collapsed state
    final titleFontSize = _lerpDouble(MiniPlayerLayout.primaryFontSize, 24.0, t);
    final artistFontSize = _lerpDouble(MiniPlayerLayout.secondaryFontSize, 18.0, t);

    final expandedTitleLeft = contentPadding;
    final titleLeft = _lerpDouble(MiniPlayerLayout.textLeft, expandedTitleLeft, t);

    final collapsedTitleTop = MiniPlayerLayout.primaryTop;

    // Controls: 36 (prev) + 34 (play) + 36 (next) + 8 (right margin) = 114px from widget right
    // For 8px gap: text ends at widgetWidth - 114 - 8 = widgetWidth - 122
    final collapsedTitleWidth = collapsedWidth - MiniPlayerLayout.textLeft - 122;
    final expandedTitleWidth = screenSize.width - (contentPadding * 2);
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Measure actual title height for dynamic layout (CACHED to avoid layout every frame)
    final titleStyle = TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    );
    // Only recalculate when track changes (screen width doesn't change during animation)
    if (_lastMeasuredTrackName != currentTrack.name ||
        _cachedExpandedTitleHeight == null) {
      final titlePainter = TextPainter(
        text: TextSpan(text: currentTrack.name, style: titleStyle),
        maxLines: 2,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: expandedTitleWidth);
      _cachedExpandedTitleHeight = titlePainter.height;
      _lastMeasuredTrackName = currentTrack.name;
    }
    final expandedTitleHeight = _cachedExpandedTitleHeight!;

    // Calculate track info block height (title + gap + artist + gap + album)
    final titleToArtistGap = 12.0;
    final artistToAlbumGap = 8.0;
    final artistHeight = 22.0; // Approximate height for 18px font
    final albumHeight = currentTrack.album != null ? 20.0 : 0.0; // Album line or nothing
    final trackInfoBlockHeight = expandedTitleHeight + titleToArtistGap + artistHeight +
        (currentTrack.album != null ? artistToAlbumGap + albumHeight : 0.0);

    // Controls section heights (from bottom up):
    // - Volume slider: 48px
    // - Gap: 40px (was 88-48=40 from volumeTop calculation)
    // - Controls row: ~70px (centered at expandedControlsTop)
    // - Gap: 64px (from expandedControlsTop = expandedProgressTop + 64)
    // - Progress bar + times: ~70px
    // Total from bottom edge: ~48 + 40 + 70 + 64 = 222, plus safe area padding
    // Position progress bar so controls section is anchored at bottom
    // Use viewPadding for consistency with player height calculation
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    final controlsSectionHeight = 222.0; // Total height of progress + controls + volume
    final playButtonHalfHeight = 36.0; // Half of the 72px play button container
    final expandedProgressTop = screenSize.height - bottomSafeArea - controlsSectionHeight - 24 - playButtonHalfHeight;

    // Calculate available space between art bottom and progress bar
    final artBottom = expandedArtTop + expandedArtSize;
    final availableSpace = expandedProgressTop - artBottom;

    // Center the track info block in available space
    final trackInfoTopMargin = (availableSpace - trackInfoBlockHeight) / 2;
    final expandedTitleTop = artBottom + trackInfoTopMargin;
    final titleTop = _lerpDouble(collapsedTitleTop, expandedTitleTop, t);

    // Artist positioned dynamically based on actual title height
    final collapsedArtistTop = MiniPlayerLayout.secondaryTop;
    final expandedArtistTop = expandedTitleTop + expandedTitleHeight + titleToArtistGap;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

    // Player name - only visible when collapsed (third line)
    final playerNameTop = MiniPlayerLayout.tertiaryTop;

    // Album - subtle, below artist
    final expandedAlbumTop = expandedArtistTop + artistHeight + artistToAlbumGap;

    // Controls - main row with comfortable touch targets
    final collapsedControlsRight = 8.0;
    final collapsedControlsTop = (_collapsedHeight - 34) / 2 - 6;
    final expandedControlsTop = expandedProgressTop + 64;
    final controlsTop = _lerpDouble(collapsedControlsTop, expandedControlsTop, t);

    // Button sizes - larger in expanded for better touch targets
    final skipButtonSize = _lerpDouble(28, 36, t);
    final playButtonSize = _lerpDouble(34, 44, t);
    final playButtonContainerSize = _lerpDouble(34, 72, t);

    final expandedElementsOpacity = Curves.easeIn.transform((t - 0.5).clamp(0, 0.5) * 2);

    // Volume - anchored near bottom with breathing room
    final volumeTop = expandedControlsTop + 88;

    // Check if we have multiple players for swipe gesture
    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;
    final selectedPlayerId = selectedPlayer.playerId;

    // Calculate slide offset for mini player content (only when collapsed)
    // Smoothly fade out horizontal slide offset (for device switching) as animation progresses
    final miniPlayerSlideOffset = _slideOffset * collapsedWidth * offsetFade;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        // Use translucent to allow child widgets (like buttons) to receive taps
        behavior: HitTestBehavior.translucent,
        // Handle tap: when device list is visible, dismiss it; when collapsed, expand
        onTap: isExpanded ? null : (widget.isDeviceRevealVisible ? GlobalPlayerOverlay.dismissPlayerReveal : expand),
        onVerticalDragStart: (details) {
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;
          // For expanded player or queue panel: start tracking immediately
          // For collapsed player: defer decision until we know swipe direction
          if (isExpanded || isQueuePanelOpen) {
            _handleVerticalDragStart(details);
          }
        },
        onVerticalDragUpdate: (details) {
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;

          final delta = details.primaryDelta ?? 0;

          // Handle queue panel close
          if (isQueuePanelOpen && delta > 0) {
            _toggleQueuePanel();
            return;
          }

          // Collapsed + not yet tracking: decide based on direction
          if (!isExpanded && !_isVerticalDragging) {
            if (delta > 5 && widget.onRevealPlayers != null) {
              // Swipe down → show player reveal
              widget.onRevealPlayers!();
              return;
            } else if (delta < -5) {
              // Swipe up → start expand tracking
              _handleVerticalDragStart(DragStartDetails(
                globalPosition: details.globalPosition,
                localPosition: details.localPosition,
              ));
            } else {
              // Not enough movement yet, wait for more
              return;
            }
          }

          // Gesture-driven expand/collapse
          _handleVerticalDragUpdate(details);
        },
        onVerticalDragEnd: (details) {
          // Ignore while queue item is being dragged
          if (_isQueueDragging) return;
          // Finish gesture-driven expansion
          _handleVerticalDragEnd(details);
        },
        onVerticalDragCancel: () {
          // Reset state if gesture is cancelled (e.g., system takes over)
          _isVerticalDragging = false;
        },
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // Start volume drag if device reveal is visible
          if (widget.isDeviceRevealVisible && !isExpanded) {
            // For consecutive swipes, use local volume (API may not have updated player state yet)
            final now = DateTime.now().millisecondsSinceEpoch;
            final timeSinceLastDrag = now - _lastVolumeDragEndTime;
            final isWithinWindow = timeSinceLastDrag < _consecutiveSwipeWindowMs;

            // Use local volume if we have an override AND within window
            final useLocalVolume = _hasLocalVolumeOverride && isWithinWindow;

            final startVolume = useLocalVolume
                ? _dragVolumeLevel // Continue from where last swipe ended
                : (selectedPlayer.volumeLevel ?? 0).toDouble() / 100.0; // Fresh from player

            setState(() {
              _isDraggingVolume = true;
              _dragVolumeLevel = startVolume;
            });
            _lastVolumeDragPosition = details.globalPosition;
            HapticFeedback.lightImpact();
          }
        },
        onHorizontalDragUpdate: (details) {
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // Volume swipe when device reveal is visible
          if (widget.isDeviceRevealVisible && _isDraggingVolume && !isExpanded) {
            // Check for stillness to trigger precision mode (only if enabled in settings)
            final currentPosition = details.globalPosition;
            if (_volumePrecisionModeEnabled && _lastVolumeDragPosition != null) {
              final movement = (currentPosition - _lastVolumeDragPosition!).distance;

              if (movement < _precisionStillnessThreshold) {
                // Finger is still - start precision timer if not already running
                if (_volumePrecisionTimer == null && !_inVolumePrecisionMode) {
                  _volumePrecisionTimer = Timer(
                    Duration(milliseconds: _precisionTriggerMs),
                    _enterVolumePrecisionMode,
                  );
                }
              } else {
                // Finger moved - cancel timer (but don't exit precision mode if already in it)
                _volumePrecisionTimer?.cancel();
                _volumePrecisionTimer = null;
              }
            }
            _lastVolumeDragPosition = currentPosition;
            _lastVolumeLocalX = details.localPosition.dx;

            double newVolume;

            if (_inVolumePrecisionMode) {
              // PRECISION MODE: Movement from entry point maps to zoomed range
              // Full width of movement = precisionSensitivity (10%) change
              // e.g., at 40% center: moving full width right = 50%, full width left = 30%
              final offsetX = details.localPosition.dx - _volumePrecisionStartX;
              final normalizedOffset = offsetX / collapsedWidth; // -1.0 to +1.0 range
              final volumeChange = normalizedOffset * _precisionSensitivity;
              newVolume = (_volumePrecisionZoomCenter + volumeChange).clamp(0.0, 1.0);
            } else {
              // NORMAL MODE: Delta-based movement (full width = 100%)
              final dragDelta = details.delta.dx;
              final volumeDelta = dragDelta / collapsedWidth;
              newVolume = (_dragVolumeLevel + volumeDelta).clamp(0.0, 1.0);
            }

            if ((newVolume - _dragVolumeLevel).abs() > 0.001) {
              setState(() {
                _dragVolumeLevel = newVolume;
              });
              // Throttle API calls to prevent flooding (faster in precision mode)
              final now = DateTime.now().millisecondsSinceEpoch;
              final throttleMs = _inVolumePrecisionMode ? _precisionThrottleMs : _volumeThrottleMs;
              if (now - _lastVolumeUpdateTime >= throttleMs) {
                _lastVolumeUpdateTime = now;
                maProvider.setVolume(selectedPlayer.playerId, (newVolume * 100).round());
              }
            }
            return;
          }

          // Only handle player swipe in collapsed mode with multiple players
          if (isExpanded || !hasMultiplePlayers) return;

          // Ignore drags that started in the edge dead zone
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          if (startedInDeadZone) return;

          _handleHorizontalDragUpdate(details, maProvider, collapsedWidth);
        },
        onHorizontalDragEnd: (details) {
          // Queue panel swipe is handled by QueuePanel's Listener (bypasses gesture arena)
          // End volume drag
          if (_isDraggingVolume) {
            // Send final volume on release
            maProvider.setVolume(selectedPlayer.playerId, (_dragVolumeLevel * 100).round());
            _lastVolumeDragEndTime = DateTime.now().millisecondsSinceEpoch; // Track for consecutive swipes
            _hasLocalVolumeOverride = true; // Mark that we have a local volume value
            _exitVolumePrecisionMode();
            _lastVolumeDragPosition = null;
            setState(() {
              _isDraggingVolume = false;
            });
            HapticFeedback.lightImpact();
            _horizontalDragStartX = null;
            return;
          }

          // Ignore swipes that started near the edges (Android back gesture zone)
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          if (isExpanded) {
            // Expanded mode: swipe LEFT to open queue (swipe right to close is handled by QueuePanel's Listener)
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -300 && !isQueuePanelOpen) {
                _toggleQueuePanel();
              }
              // NOTE: Swipe right to close is NOT handled here - QueuePanel's Listener
              // handles its own swipe-to-close via onSwipeEnd callback to avoid double-trigger
            }
          } else if (hasMultiplePlayers) {
            // Collapsed mode: use finger-following handler
            _handleHorizontalDragEnd(details, maProvider);
          }
        },
        onHorizontalDragCancel: () {
          // Reset state if gesture is cancelled (e.g., system takes over)
          _horizontalDragStartX = null;
          // Queue panel swipe is handled by QueuePanel's Listener
          if (_isDraggingVolume) {
            _exitVolumePrecisionMode();
            _lastVolumeDragPosition = null;
            setState(() => _isDraggingVolume = false);
          }
          if (_isDragging) {
            _isDragging = false;
            _slideOffset = 0.0;
            setState(() {
              _peekPlayer = null;
              _peekImageUrl = null;
              _peekTrack = null;
            });
          }
        },
        child: Container(
          // Use foregroundDecoration for border so it renders ON TOP of content
          // This prevents the album art from clipping the yellow synced border
          foregroundDecoration: maProvider.isPlayerManuallySynced(selectedPlayer.playerId) && t < 0.5
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(color: _groupBorderColor, width: 1.5),
                )
              : null,
          child: Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            elevation: _lerpDouble(4, 0, t),
            shadowColor: _shadowColor,
            // Use hardEdge when fully expanded (no border radius) to avoid anti-alias artifacts
            // Use antiAlias when collapsed/animating to smooth rounded corners
            clipBehavior: borderRadius > 0.5 ? Clip.antiAlias : Clip.hardEdge,
            child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Mini player progress bar background (collapsed only)
                // Shows played portion with brighter color, unplayed with darker
                // Starts after album art so progress is visible
                // Slides with content during swipe, hidden during transition if peek available
                // GPU PERF: Use conditional rendering + color alpha instead of Opacity
                // to avoid double saveLayer (Opacity + ClipRRect)
                if (t < 0.5 && currentTrack?.duration != null && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                      left: _collapsedArtSize + miniPlayerSlideOffset,
                      top: 0,
                      width: width - _collapsedArtSize,
                      bottom: 0,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progressNotifier,
                        builder: (context, elapsedSeconds, _) {
                          final totalSeconds = currentTrack!.duration!.inSeconds;
                          if (totalSeconds <= 0) return const SizedBox.shrink();
                          final progress = (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
                          // Fade out as we expand - use color alpha instead of Opacity widget
                          final progressOpacity = (1.0 - (t / 0.5)).clamp(0.0, 1.0);
                          final progressAreaWidth = width - _collapsedArtSize;
                          // RepaintBoundary isolates frequent progress updates from parent animation
                          return RepaintBoundary(
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(borderRadius),
                                bottomRight: Radius.circular(borderRadius),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: progressAreaWidth * progress,
                                  height: height,
                                  color: collapsedBg.withOpacity(progressOpacity),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                // Peek player content (shows when dragging OR during transition)
                // Show when: actively dragging (slideOffset != 0) OR in transition state
                // Must have peek data to render
                if (t < 0.1 && _peekPlayer != null && (_slideOffset.abs() > 0.01 || _inTransition))
                  _buildPeekContent(
                    context: context,
                    peekPlayer: _peekPlayer,
                    peekImageUrl: _peekImageUrl,
                    slideOffset: _slideOffset,
                    containerWidth: collapsedWidth,
                    backgroundColor: collapsedBg,
                    textColor: textColor,
                  ),

                // Album art - with slide animation when collapsed
                // Hidden during transition to prevent flash (peek content shows instead)
                // FALLBACK: Show main content if transition is active but peek content unavailable
                // This prevents showing only the progress bar with no content
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                if (!(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: artLeft + miniPlayerSlideOffset,
                    top: artTop,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Use onTapUp instead of onTap - resolves immediately and wins
                      // the gesture arena against the outer vertical drag detector
                      onTapUp: t > 0.5 ? (_) => _showFullscreenArt(context, imageUrl) : null,
                      child: Container(
                        width: artSize,
                        height: artSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(artBorderRadius),
                          // GPU PERF: Fixed blur/offset, only animate shadow opacity
                          boxShadow: t > 0.3
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : null,
                        ),
                        // Use RepaintBoundary to isolate art repaints during animation
                        child: RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(artBorderRadius),
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    // Fixed cache size to avoid mid-animation cache thrashing
                                    memCacheWidth: 512,
                                    memCacheHeight: 512,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    placeholderFadeInDuration: Duration.zero,
                                    placeholder: (_, __) => _buildPlaceholderArt(colorScheme, t),
                                    errorWidget: (_, __, ___) => _buildPlaceholderArt(colorScheme, t),
                                  )
                                : _buildPlaceholderArt(colorScheme, t),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Track title - with slide animation when collapsed
                // When hint is visible, show lightbulb icon + "Pull to select players"
                // When device reveal is visible, show player name instead of track name
                // Hidden during transition to prevent flash
                // FALLBACK: Show if transition active but no peek content available
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                // Hint text - vertically centered in mini player
                if (widget.isHintVisible && t < 0.5 && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: titleLeft + miniPlayerSlideOffset,
                    // Center vertically: (64 - ~20) / 2 = 22
                    top: (MiniPlayerLayout.height - 20) / 2,
                    child: SizedBox(
                      width: titleWidth,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: textColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              S.of(context)!.pullToSelectPlayers,
                              style: TextStyle(
                                color: textColor,
                                fontSize: titleFontSize,
                                fontWeight: MiniPlayerLayout.primaryFontWeight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Track title - with slide animation when collapsed
                // Hidden when hint is visible
                if (!(widget.isHintVisible && t < 0.5) && !(_inTransition && t < 0.1 && _peekPlayer != null))
                  Positioned(
                    left: titleLeft + miniPlayerSlideOffset,
                    top: titleTop,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        currentTrack.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: titleFontSize,
                          fontWeight: t > 0.5 ? FontWeight.w600 : MiniPlayerLayout.primaryFontWeight,
                          letterSpacing: t > 0.5 ? -0.5 : 0,
                          height: t > 0.5 ? 1.2 : null, // Only use line height when expanded
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: t > 0.5 ? 2 : 1,
                        softWrap: t > 0.5, // false in collapsed to ensure ellipsis truncation
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Artist/Author name - with slide animation when collapsed
                // When hint is visible, show blank line
                // When device reveal is visible, show "Now Playing" hint
                // For audiobooks: show author from audiobook context
                // Hidden during transition to prevent flash
                // FALLBACK: Show if transition active but no peek content available
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                if (!(_inTransition && t < 0.1 && _peekPlayer != null) && !(widget.isHintVisible && t < 0.5))
                  Positioned(
                    left: titleLeft + miniPlayerSlideOffset,
                    top: artistTop,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        // Always show artist/author/podcast name (was showing "Now Playing" when device reveal visible)
                        maProvider.isPlayingAudiobook
                            ? (maProvider.currentAudiobook?.authorsString ?? S.of(context)!.unknownAuthor)
                            : maProvider.isPlayingPodcast
                                ? (maProvider.currentPodcastName ?? S.of(context)!.podcasts)
                                : currentTrack.artistsString,
                        style: TextStyle(
                          color: textColor.withOpacity(t > 0.5 ? 0.7 : MiniPlayerLayout.secondaryTextOpacity),
                          fontSize: artistFontSize,
                          fontWeight: t > 0.5 ? FontWeight.w400 : FontWeight.normal,
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: 1,
                        softWrap: t > 0.5, // false in collapsed to ensure ellipsis truncation
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Player name - third line, only visible when collapsed
                // Same size as artist, same color as track
                if (t < 0.5 && !(_inTransition && t < 0.1 && _peekPlayer != null) && !(widget.isHintVisible && t < 0.5))
                  Positioned(
                    left: titleLeft + miniPlayerSlideOffset,
                    top: playerNameTop,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: textColor.withOpacity(1.0 - t * 2), // Fade out as expanding
                          fontSize: MiniPlayerLayout.tertiaryFontSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Album name OR Chapter name (expanded only)
                // GPU PERF: Use color alpha instead of Opacity widget
                // For audiobooks: show current chapter; for music: show album
                // For podcasts: hide album line since podcast name is already shown in artist position
                if (t > 0.3 && (currentTrack.album != null || maProvider.isPlayingAudiobook) && !maProvider.isPlayingPodcast)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
                    child: maProvider.isPlayingAudiobook
                        ? _buildChapterInfo(maProvider, textColor, t)
                        : Text(
                            currentTrack.album!.name,
                            style: TextStyle(
                              color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
                              fontSize: 15,
                              fontWeight: FontWeight.w300,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),

                // Audio source/format info (expanded only, when Sendspin active)
                // Shows "Playing from Sendspin" and audio format
                if (t > 0.5 && maProvider.isSendspinConnected)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedAlbumTop + (maProvider.isPlayingAudiobook ? 24 : (currentTrack.album != null ? 24 : 0)),
                    child: FadeTransition(
                      opacity: _expandAnimation.drive(
                        Tween(begin: 0.0, end: 1.0).chain(
                          CurveTween(curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.graphic_eq_rounded,
                            size: 14,
                            color: primaryColor.withOpacity(0.7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            maProvider.currentAudioFormat ?? S.of(context)!.pcmAudio,
                            style: TextStyle(
                              color: primaryColor.withOpacity(0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Progress bar (expanded only)
                // GPU PERF: Use FadeTransition instead of Opacity
                if (t > 0.5 && currentTrack.duration != null)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: expandedProgressTop,
                    child: FadeTransition(
                      opacity: _expandAnimation.drive(
                        Tween(begin: 0.0, end: 1.0).chain(
                          CurveTween(curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
                        ),
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _progressNotifier,
                        builder: (context, elapsedTime, child) {
                          return ValueListenableBuilder<double?>(
                            valueListenable: _seekPositionNotifier,
                            builder: (context, seekPosition, child) {
                              final currentProgress = seekPosition ?? elapsedTime.toDouble();
                              return Column(
                                children: [
                                  SizedBox(
                                    height: 48, // Increase touch target height
                                    child: SliderTheme(
                                      data: SliderThemeData(
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                                        trackShape: const RoundedRectSliderTrackShape(),
                                      ),
                                      child: Slider(
                                        value: currentProgress.clamp(0.0, currentTrack.duration!.inSeconds.toDouble()).toDouble(),
                                        max: currentTrack.duration!.inSeconds.toDouble(),
                                        onChanged: (value) => _seekPositionNotifier.value = value,
                                        onChangeStart: (value) => _seekPositionNotifier.value = value,
                                        onChangeEnd: (value) async {
                                          try {
                                            await maProvider.seek(selectedPlayer.playerId, value.round());
                                            await Future.delayed(const Duration(milliseconds: 200));
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(S.of(context)!.errorSeeking(e.toString()))),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              _seekPositionNotifier.value = null;
                                            }
                                          }
                                        },
                                        activeColor: primaryColor,
                                        inactiveColor: primaryColor.withOpacity(0.2),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(currentProgress.toInt()),
                                          style: TextStyle(
                                            color: textColor.withOpacity(0.5),
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        Text(
                                          _formatDuration(currentTrack.duration!.inSeconds),
                                          style: TextStyle(
                                            color: textColor.withOpacity(0.5),
                                            fontSize: 13, // Increased from 11 to 13
                                            fontWeight: FontWeight.w500,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                // Playback controls - with slide animation when collapsed
                // Use skip 30s controls for audiobooks and podcasts
                Positioned(
                  left: t > 0.5 ? 0 : null,
                  right: t > 0.5 ? 0 : collapsedControlsRight - miniPlayerSlideOffset,
                  top: controlsTop,
                  child: (maProvider.isPlayingAudiobook || maProvider.isPlayingPodcast)
                      // When device reveal is visible (player list shown), use compact controls
                      // for audiobooks/podcasts: Play, Forward 30, Power
                      ? widget.isDeviceRevealVisible && t < 0.5
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play/Pause - compact like PlayerCard
                                Transform.translate(
                                  offset: const Offset(3, 0),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      icon: Icon(
                                        selectedPlayer.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: textColor,
                                        size: 28,
                                      ),
                                      onPressed: () => maProvider.playPauseSelectedPlayer(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                // Forward 30 seconds
                                Transform.translate(
                                  offset: const Offset(6, 0),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.forward_30_rounded,
                                      color: textColor,
                                      size: 28,
                                    ),
                                    onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 30),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                                // Power button
                                IconButton(
                                  icon: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: selectedPlayer.powered ? textColor : textColor.withOpacity(0.5),
                                    size: 20,
                                  ),
                                  onPressed: () => maProvider.togglePower(selectedPlayer.playerId),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 4),
                              ],
                            )
                          : _buildAudiobookControls(
                              maProvider: maProvider,
                              selectedPlayer: selectedPlayer,
                              textColor: textColor,
                              primaryColor: primaryColor,
                              backgroundColor: backgroundColor,
                              skipButtonSize: skipButtonSize,
                              playButtonSize: playButtonSize,
                              playButtonContainerSize: playButtonContainerSize,
                              t: t,
                              expandedElementsOpacity: expandedElementsOpacity,
                            )
                      // When device reveal is visible (player list shown), use compact controls
                      // like PlayerCard: Play, Next, Power - matching other players in the list
                      : widget.isDeviceRevealVisible && t < 0.5
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Play/Pause - compact like PlayerCard
                                // Touch target increased to 44dp for accessibility
                                Transform.translate(
                                  offset: const Offset(3, 0),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton(
                                      icon: Icon(
                                        selectedPlayer.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: textColor,
                                        size: 28,
                                      ),
                                      onPressed: () => maProvider.playPauseSelectedPlayer(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                // Skip next - nudged right like PlayerCard
                                Transform.translate(
                                  offset: const Offset(6, 0),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.skip_next_rounded,
                                      color: textColor,
                                      size: 28,
                                    ),
                                    onPressed: () => maProvider.nextTrackSelectedPlayer(),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                                // Power button - smallest, like PlayerCard
                                IconButton(
                                  icon: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: selectedPlayer.powered ? textColor : textColor.withOpacity(0.5),
                                    size: 20,
                                  ),
                                  onPressed: () => maProvider.togglePower(selectedPlayer.playerId),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 4),
                              ],
                            )
                          : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: t > 0.5 ? MainAxisAlignment.center : MainAxisAlignment.end,
                    children: [
                      // Shuffle (expanded only)
                      // GPU PERF: Use color alpha instead of Opacity
                      if (t > 0.5 && expandedElementsOpacity > 0.1)
                        _buildSecondaryButton(
                          icon: Icons.shuffle_rounded,
                          color: (_queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.5))
                              .withOpacity(expandedElementsOpacity),
                          onPressed: _isLoadingQueue ? null : _toggleShuffle,
                        ),
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),

                      // Previous
                      _buildControlButton(
                        icon: Icons.skip_previous_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.previousTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

                      // Play/Pause
                      _buildPlayButton(
                        isPlaying: selectedPlayer.isPlaying,
                        textColor: textColor,
                        primaryColor: primaryColor,
                        backgroundColor: backgroundColor,
                        size: playButtonSize,
                        containerSize: playButtonContainerSize,
                        progress: t,
                        onPressed: () => maProvider.playPauseSelectedPlayer(),
                        onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
                      ),
                      SizedBox(width: _lerpDouble(0, 20, t)),

                      // Next
                      _buildControlButton(
                        icon: Icons.skip_next_rounded,
                        color: textColor,
                        size: skipButtonSize,
                        onPressed: () => maProvider.nextTrackSelectedPlayer(),
                        useAnimation: t > 0.5,
                      ),

                      // Repeat (expanded only)
                      // GPU PERF: Use color alpha instead of Opacity
                      if (t > 0.5) SizedBox(width: _lerpDouble(0, 20, t)),
                      if (t > 0.5 && expandedElementsOpacity > 0.1)
                        _buildSecondaryButton(
                          icon: _queue?.repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          color: (_queue?.repeatMode != null && _queue!.repeatMode != 'off'
                                  ? primaryColor
                                  : textColor.withOpacity(0.5))
                              .withOpacity(expandedElementsOpacity),
                          onPressed: _isLoadingQueue ? null : _cycleRepeat,
                        ),
                    ],
                  ),
                ),

                // Volume control (expanded only)
                // GPU PERF: Use FadeTransition instead of Opacity
                if (t > 0.5)
                  Positioned(
                    left: 48,
                    right: 48,
                    top: volumeTop,
                    child: FadeTransition(
                      opacity: _expandAnimation.drive(
                        Tween(begin: 0.0, end: 1.0).chain(
                          CurveTween(curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
                        ),
                      ),
                      child: const VolumeControl(compact: false),
                    ),
                  ),

                // Collapse button (expanded only)
                // GPU PERF: Use icon color alpha instead of Opacity
                if (t > 0.3)
                  Positioned(
                    top: topPadding + 4,
                    left: 4,
                    child: IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: textColor.withOpacity(((t - 0.3) / 0.7).clamp(0.0, 1.0)),
                        size: 28,
                      ),
                      onPressed: collapse,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),

                // Favorite + Queue buttons (expanded only) - fade when queue panel opens
                // PERF: Own AnimatedBuilder - only rebuilds these 2 buttons on queue animation
                if (t > 0.3)
                  AnimatedBuilder(
                    animation: _queuePanelAnimation,
                    builder: (context, _) {
                      final queueFade = _queuePanelAnimation.value;
                      // Hide completely when queue > 0.5
                      if (queueFade >= 0.5) return const SizedBox.shrink();
                      final fadeOpacity = (1 - queueFade * 2).clamp(0.0, 1.0);
                      final expandOpacity = ((t - 0.3) / 0.7).clamp(0.0, 1.0);
                      return Stack(
                        children: [
                          // Favorite button
                          Positioned(
                            top: topPadding + 4,
                            right: 52,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(_isCurrentTrackFavorite),
                              tween: Tween(begin: 1.3, end: 1.0),
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) => Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _isCurrentTrackFavorite ? Icons.favorite : Icons.favorite_border,
                                  color: (_isCurrentTrackFavorite ? Colors.red : textColor)
                                      .withOpacity(expandOpacity * fadeOpacity),
                                  size: 24,
                                ),
                                onPressed: () => _toggleCurrentTrackFavorite(currentTrack),
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          // Queue button
                          Positioned(
                            top: topPadding + 4,
                            right: 4,
                            child: IconButton(
                              icon: Icon(
                                Icons.queue_music_rounded,
                                color: textColor.withOpacity(expandOpacity * fadeOpacity),
                                size: 24,
                              ),
                              onPressed: _toggleQueuePanel,
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                // Player name (expanded only)
                // GPU PERF: Use text color alpha instead of Opacity
                if (t > 0.5)
                  Positioned(
                    top: topPadding + 12,
                    left: 56,
                    right: 56,
                    child: IgnorePointer(
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.6 * ((t - 0.5) / 0.5).clamp(0.0, 1.0)),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Queue/Chapters panel (slides in from right)
                // For audiobooks: show chapters panel
                // For music: show queue panel
                // PERF: Own AnimatedBuilder - only rebuilds queue panel section on queue animation
                // Main player doesn't rebuild when queue slides in/out
                if (t > 0.5)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _queuePanelAnimation,
                      builder: (context, child) {
                        final queueProgress = _queuePanelAnimation.value;
                        return Offstage(
                          offstage: queueProgress == 0,
                          child: child,
                        );
                      },
                      // PERF: Child is not rebuilt - only Offstage wrapper updates
                      child: RepaintBoundary(
                        child: SlideTransition(
                          // PERF: Use cached animation instead of Tween.animate() every frame
                          position: _queueSlideAnimation,
                          child: maProvider.isPlayingAudiobook
                              ? ChaptersPanel(
                                  maProvider: maProvider,
                                  audiobook: maProvider.currentAudiobook,
                                  textColor: textColor,
                                  primaryColor: primaryColor,
                                  backgroundColor: expandedBg,
                                  topPadding: topPadding,
                                  onClose: _toggleQueuePanel,
                                )
                              : QueuePanel(
                                  maProvider: maProvider,
                                  queue: _queue,
                                  isLoading: _isLoadingQueue,
                                  textColor: textColor,
                                  primaryColor: primaryColor,
                                  backgroundColor: expandedBg,
                                  topPadding: topPadding,
                                  onClose: _toggleQueuePanel,
                                  onRefresh: _loadQueue,
                                  onDraggingChanged: (isDragging) {
                                    _isQueueDragging = isDragging;
                                  },
                                  onSwipeStart: () {
                                    // Haptic feedback when swipe gesture recognized
                                    HapticFeedback.selectionClick();
                                  },
                                  onSwipeUpdate: (_) {
                                    // No finger tracking - just wait for swipe end
                                    // This avoids jank from direct value manipulation
                                  },
                                  onSwipeEnd: (velocity, totalDx) {
                                    // Decide based on velocity and total displacement
                                    final screenWidth = MediaQuery.of(context).size.width;
                                    final swipeProgress = totalDx / screenWidth;
                                    final shouldClose = velocity > 150 || swipeProgress > 0.25;

                                    if (shouldClose) {
                                      _closeQueuePanelWithSpring();
                                    }
                                    // If not closing, panel stays open (no snap-back needed since we didn't move it)
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),

                // Volume swipe overlay (covers entire mini player when dragging volume)
                // Only visible when device reveal is open and user is dragging
                // Positioned last in Stack so it renders ON TOP of all content
                // Uses AnimatedOpacity for smooth fade in/out transition
                if (t < 0.5)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isDraggingVolume,
                      child: AnimatedOpacity(
                        opacity: _isDraggingVolume ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 120),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderRadius),
                          child: Stack(
                            children: [
                              // Unfilled (darker) background
                              Container(color: collapsedBgUnplayed),
                              // Filled (lighter) portion based on volume
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _dragVolumeLevel.clamp(0.0, 1.0),
                                  heightFactor: 1.0,
                                  child: Container(color: collapsedBg),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// Build the peek player content that slides in from the edge during drag
  /// Uses shared MiniPlayerContent for consistency
  Widget _buildPeekContent({
    required BuildContext context,
    required dynamic peekPlayer,
    required String? peekImageUrl,
    required double slideOffset,
    required double containerWidth,
    required Color backgroundColor,
    required Color textColor,
  }) {
    // Calculate sliding position
    double peekBaseOffset;

    if (_inTransition && slideOffset.abs() < 0.01) {
      peekBaseOffset = 0.0;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();
      peekBaseOffset = isFromRight
          ? containerWidth * (1 - peekProgress)
          : -containerWidth * (1 - peekProgress);
    }

    // Check if peek player has a track
    final hasTrack = _peekTrack != null && peekImageUrl != null;
    final peekTrackName = hasTrack ? _peekTrack!.name : (peekPlayer?.name ?? S.of(context)!.unknown);
    final peekArtistName = hasTrack ? (_peekTrack!.artistsString ?? '') : S.of(context)!.swipeToSwitchDevice;
    // Show player name as third line only when playing
    final peekPlayerName = hasTrack ? (peekPlayer?.name ?? '') : null;

    return Transform.translate(
      offset: Offset(peekBaseOffset, 0),
      child: MiniPlayerContent(
        primaryText: peekTrackName,
        secondaryText: peekArtistName,
        tertiaryText: peekPlayerName,
        imageUrl: hasTrack ? peekImageUrl : null,
        playerName: peekPlayer?.name ?? '',
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: containerWidth,
        slideOffset: 0, // Transform handles positioning
      ),
    );
  }


  /// Build peek player progress bar that slides in during swipe
  Widget _buildPeekProgressBar({
    required double slideOffset,
    required bool inTransition,
    required double collapsedWidth,
    required double progressAreaWidth,
    required double height,
    required double borderRadius,
    required Color color,
  }) {
    // Calculate peek progress bar position (mirrors _buildPeekContent positioning)
    double peekProgressLeft;
    if (inTransition && slideOffset.abs() < 0.01) {
      peekProgressLeft = _collapsedArtSize;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();
      peekProgressLeft = _collapsedArtSize + (isFromRight
          ? collapsedWidth * (1 - peekProgress)
          : -collapsedWidth * (1 - peekProgress));
    }

    // Get peek player's elapsed time - safely handle null/invalid values
    final peekElapsed = _peekPlayer?.currentElapsed ?? 0.0;
    final peekTotal = _peekTrack?.duration?.inSeconds ?? 0;
    if (peekTotal <= 0) return const SizedBox.shrink();
    final peekProgressValue = (peekElapsed / peekTotal).clamp(0.0, 1.0);

    return Positioned(
      left: peekProgressLeft,
      top: 0,
      width: progressAreaWidth,
      bottom: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(borderRadius),
          bottomRight: Radius.circular(borderRadius),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: progressAreaWidth * peekProgressValue,
            height: height,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, double t) {
    // Use theme-aware colors for both collapsed and expanded states
    final expandedBgColor = colorScheme.surfaceContainerHighest;
    final expandedIconColor = colorScheme.onSurface.withOpacity(0.24);
    return Container(
      color: Color.lerp(colorScheme.surfaceVariant, expandedBgColor, t),
      child: Icon(
        Icons.music_note_rounded,
        color: Color.lerp(colorScheme.onSurfaceVariant, expandedIconColor, t),
        size: _lerpDouble(24, 120, t),
      ),
    );
  }

  /// Build chapter info display for audiobooks
  Widget _buildChapterInfo(MusicAssistantProvider maProvider, Color textColor, double t) {
    final chapter = maProvider.getCurrentChapter();
    final chapterIndex = maProvider.getCurrentChapterIndex();
    final totalChapters = maProvider.currentAudiobook?.chapters?.length ?? 0;

    if (chapter == null) {
      return const SizedBox.shrink();
    }

    final chapterText = totalChapters > 0
        ? 'Chapter ${chapterIndex + 1}/$totalChapters: ${chapter.title}'
        : chapter.title;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bookmark_outline_rounded,
          size: 14,
          color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            chapterText,
            style: TextStyle(
              color: textColor.withOpacity(0.45 * ((t - 0.3) / 0.7).clamp(0.0, 1.0)),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Build audiobook-specific playback controls
  /// Collapsed: [-30s] [Play/Pause] [+30s]
  /// Expanded: [Prev Chapter] [-30s] [-10s] [Play/Pause] [+10s] [+30s] [Next Chapter]
  Widget _buildAudiobookControls({
    required MusicAssistantProvider maProvider,
    required dynamic selectedPlayer,
    required Color textColor,
    required Color primaryColor,
    required Color backgroundColor,
    required double skipButtonSize,
    required double playButtonSize,
    required double playButtonContainerSize,
    required double t,
    required double expandedElementsOpacity,
  }) {
    final hasChapters = maProvider.currentAudiobook?.chapters?.isNotEmpty ?? false;
    final isExpanded = t > 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isExpanded ? MainAxisAlignment.center : MainAxisAlignment.end,
      children: [
        // Previous Chapter (expanded only, if chapters available)
        if (isExpanded && expandedElementsOpacity > 0.1 && hasChapters)
          _buildSecondaryButton(
            icon: Icons.skip_previous_rounded,
            color: textColor.withOpacity(expandedElementsOpacity),
            onPressed: () => maProvider.seekToPreviousChapter(selectedPlayer.playerId),
          ),
        if (isExpanded && hasChapters) SizedBox(width: _lerpDouble(0, 12, t)),

        // Rewind 30 seconds
        _buildControlButton(
          icon: Icons.replay_30_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, -30),
          useAnimation: isExpanded,
        ),

        // Rewind 10 seconds (expanded only, same size as 30s)
        if (isExpanded) ...[
          SizedBox(width: _lerpDouble(0, 8, t)),
          _buildControlButton(
            icon: Icons.replay_10_rounded,
            color: textColor,
            size: skipButtonSize,
            onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, -10),
            useAnimation: true,
          ),
        ],
        SizedBox(width: _lerpDouble(0, 12, t)),

        // Play/Pause
        _buildPlayButton(
          isPlaying: selectedPlayer.isPlaying,
          textColor: textColor,
          primaryColor: primaryColor,
          backgroundColor: backgroundColor,
          size: playButtonSize,
          containerSize: playButtonContainerSize,
          progress: t,
          onPressed: () => maProvider.playPauseSelectedPlayer(),
          onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
        ),
        SizedBox(width: _lerpDouble(0, 12, t)),

        // Forward 10 seconds (expanded only, same size as 30s)
        if (isExpanded) ...[
          _buildControlButton(
            icon: Icons.forward_10_rounded,
            color: textColor,
            size: skipButtonSize,
            onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 10),
            useAnimation: true,
          ),
          SizedBox(width: _lerpDouble(0, 8, t)),
        ],

        // Forward 30 seconds
        _buildControlButton(
          icon: Icons.forward_30_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: () => maProvider.seekRelative(selectedPlayer.playerId, 30),
          useAnimation: isExpanded,
        ),

        // Next Chapter (expanded only, if chapters available)
        if (isExpanded && hasChapters) SizedBox(width: _lerpDouble(0, 12, t)),
        if (isExpanded && expandedElementsOpacity > 0.1 && hasChapters)
          _buildSecondaryButton(
            icon: Icons.skip_next_rounded,
            color: textColor.withOpacity(expandedElementsOpacity),
            onPressed: () => maProvider.seekToNextChapter(selectedPlayer.playerId),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    required bool useAnimation,
  }) {
    if (useAnimation) {
      return AnimatedIconButton(
        icon: icon,
        color: color,
        iconSize: size,
        onPressed: onPressed,
      );
    }
    return IconButton(
      icon: Icon(icon),
      color: color,
      iconSize: size,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedIconButton(
        icon: icon,
        color: color,
        iconSize: 22,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildPlayButton({
    required bool isPlaying,
    required Color textColor,
    required Color primaryColor,
    required Color backgroundColor,
    required double size,
    required double containerSize,
    required double progress,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    final bgColor = Color.lerp(Colors.transparent, primaryColor, progress);
    final iconColor = Color.lerp(textColor, backgroundColor, progress);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: containerSize,
        height: containerSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: iconColor,
          iconSize: size,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
