import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/timings.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../services/animation_debugger.dart';
import '../services/settings_service.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import 'animated_icon_button.dart';
import 'global_player_overlay.dart';
import 'volume_control.dart';
import 'player/player_widgets.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// This widget is designed to be used as a global overlay, positioned above
/// the bottom navigation bar. It uses smooth morphing animations where each
/// element transitions from their mini to full positions.
class ExpandablePlayer extends StatefulWidget {
  /// Slide offset for hiding the mini player (0.0 = visible, 1.0 = hidden below screen)
  final double slideOffset;

  const ExpandablePlayer({
    super.key,
    this.slideOffset = 0.0,
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

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  bool _isLoadingQueue = false;

  // Progress tracking - uses PositionTracker stream as single source of truth
  StreamSubscription<Duration>? _positionSubscription;
  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double?> _seekPositionNotifier = ValueNotifier<double?>(null);

  // Dimensions
  static const double _collapsedHeight = 64.0;
  static const double _collapsedMargin = 12.0; // Increased from 8 to 12 (4px more gap above nav bar)
  static const double _collapsedBorderRadius = 16.0;
  static const double _collapsedArtSize = 64.0;
  static const double _bottomNavHeight = 56.0;
  static const double _edgeDeadZone = 40.0; // Dead zone for Android back gesture

  // Track horizontal drag start position
  double? _horizontalDragStartX;

  // Slide animation for device switching - now supports finger-following
  late AnimationController _slideController;
  double _slideOffset = 0.0; // -1 to 1, negative = sliding left, positive = sliding right
  bool _isSliding = false;
  bool _isDragging = false; // True while finger is actively dragging

  // For peek preview - track which player we'd switch to
  dynamic _peekPlayer; // The player that would be selected if swipe commits
  String? _peekImageUrl; // Image URL for peek player's current track

  // Flag to indicate we're in the middle of a player switch transition
  // When true, we hide main content and show peek content at center
  bool _inTransition = false;

  // Track favorite state for current track
  bool _isCurrentTrackFavorite = false;
  String? _lastTrackUri; // Track which track we last checked favorite status for

  // Cached title height to avoid TextPainter.layout() every animation frame
  double? _cachedExpandedTitleHeight;
  String? _lastMeasuredTrackName;
  double? _lastMeasuredTitleWidth;

  // Provider icons setting
  bool _showProviderIcons = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Notify listeners of expansion progress changes
    _controller.addListener(_notifyExpansionProgress);

    // Animation debugging - record every frame
    _controller.addListener(_recordAnimationFrame);

    // Queue panel animation
    _queuePanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _queuePanelAnimation = CurvedAnimation(
      parent: _queuePanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Slide animation for device switching - used for snap/spring animations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        _loadQueue();
      } else if (status == AnimationStatus.dismissed) {
        // Close queue panel when player collapses
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

    // Load provider icons setting
    _loadProviderIconsSetting();
  }

  Future<void> _loadProviderIconsSetting() async {
    final showIcons = await SettingsService.getShowProviderIcons();
    if (mounted) {
      setState(() {
        _showProviderIcons = showIcons;
      });
    }
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
    _positionSubscription?.cancel();
    _queueRefreshTimer?.cancel();
    _progressNotifier.dispose();
    _seekPositionNotifier.dispose();
    super.dispose();
  }

  void _recordAnimationFrame() {
    AnimationDebugger.recordFrame(_controller.value);
  }

  void expand() {
    AnimationDebugger.startSession('playerExpand');
    _controller.forward().then((_) {
      AnimationDebugger.endSession();
    });
  }

  void collapse() {
    AnimationDebugger.startSession('playerCollapse');
    // Instantly hide queue panel when collapsing to avoid visual glitches
    // during Android's predictive back gesture
    _queuePanelController.value = 0;
    _controller.reverse().then((_) {
      AnimationDebugger.endSession();
    });
  }

  bool get isExpanded => _controller.value > 0.5;

  double get expansionProgress => _controller.value;

  Color? _currentExpandedBgColor;
  Color? get currentExpandedBgColor => _currentExpandedBgColor;

  void _notifyExpansionProgress() {
    playerExpansionNotifier.value = PlayerExpansionState(
      _controller.value,
      _currentExpandedBgColor,
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

    setState(() => _isLoadingQueue = true);

    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;

    if (player != null && maProvider.api != null) {
      final queue = await maProvider.api!.getQueue(player.playerId);
      if (mounted) {
        setState(() {
          _queue = queue;
          _isLoadingQueue = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingQueue = false);
      }
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
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.toggleShuffle(_queue!.playerId);
    await _loadQueue();
  }

  Future<void> _cycleRepeat() async {
    if (_queue == null) return;
    final maProvider = context.read<MusicAssistantProvider>();
    await maProvider.cycleRepeatMode(_queue!.playerId, _queue!.repeatMode);
    await _loadQueue();
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _toggleQueuePanel() {
    if (_queuePanelController.isAnimating) return;
    if (_queuePanelController.value == 0) {
      _queuePanelController.forward();
    } else {
      _queuePanelController.reverse();
    }
  }

  bool get isQueuePanelOpen => _queuePanelController.value > 0.5;

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

  /// Toggle favorite status for current track
  Future<void> _toggleCurrentTrackFavorite(dynamic currentTrack) async {
    if (currentTrack == null) return;

    final maProvider = context.read<MusicAssistantProvider>();
    if (maProvider.api == null) return;

    try {
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
          await maProvider.api!.removeFromFavorites('track', libraryItemId);
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
            for (final mapping in mappings) {
              if (mapping.available == true && mapping.providerInstance != 'library') {
                actualProvider = mapping.providerInstance;
                actualItemId = mapping.itemId;
                break;
              }
            }
            // Fallback to first available if no non-library found
            if (actualProvider == 'library') {
              for (final mapping in mappings) {
                if (mapping.available == true) {
                  actualProvider = mapping.providerInstance;
                  actualItemId = mapping.itemId;
                  break;
                }
              }
            }
          }
        }

        await maProvider.api!.addToFavorites('track', actualItemId, actualProvider);
      }

      // Toggle local state
      setState(() {
        _isCurrentTrackFavorite = !_isCurrentTrackFavorite;
      });

      // Invalidate home cache so favorites are updated
      maProvider.invalidateHomeCache();
    } catch (e) {
      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favorite: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Get provider icons for the current track
  List<Widget> _buildProviderIcons(dynamic currentTrack) {
    if (currentTrack == null || currentTrack.providerMappings == null) {
      return [];
    }

    final mappings = currentTrack.providerMappings as List<dynamic>?;
    if (mappings == null || mappings.isEmpty) return [];

    // Get unique providers (exclude 'library' as it's not a music source)
    final seenProviders = <String>{};
    final icons = <Widget>[];

    for (final mapping in mappings) {
      if (mapping.available != true) continue;
      final provider = (mapping.providerDomain ?? mapping.providerInstance ?? '').toString().toLowerCase();
      if (provider.isEmpty || provider == 'library' || seenProviders.contains(provider)) continue;
      seenProviders.add(provider);

      final icon = _getProviderIcon(provider);
      if (icon != null) {
        icons.add(
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: icon,
            ),
          ),
        );
      }
    }

    return icons;
  }

  /// Get icon widget for a provider
  Widget? _getProviderIcon(String provider) {
    // Common Music Assistant providers
    if (provider.contains('spotify')) {
      return const Icon(Icons.music_note_rounded, size: 16, color: Color(0xFF1DB954));
    } else if (provider.contains('subsonic') || provider.contains('opensubsonic')) {
      return const Icon(Icons.cloud_rounded, size: 16, color: Color(0xFFF9A825));
    } else if (provider.contains('tidal')) {
      return const Icon(Icons.waves_rounded, size: 16, color: Colors.white);
    } else if (provider.contains('qobuz')) {
      return const Icon(Icons.high_quality_rounded, size: 16, color: Color(0xFF2C8BFF));
    } else if (provider.contains('youtube') || provider.contains('ytmusic')) {
      return const Icon(Icons.play_circle_filled_rounded, size: 16, color: Colors.red);
    } else if (provider.contains('plex')) {
      return const Icon(Icons.smart_display_rounded, size: 16, color: Color(0xFFE5A00D));
    } else if (provider.contains('jellyfin')) {
      return const Icon(Icons.video_library_rounded, size: 16, color: Color(0xFF00A4DC));
    } else if (provider.contains('filesystem') || provider.contains('local')) {
      return const Icon(Icons.folder_rounded, size: 16, color: Colors.grey);
    } else if (provider.contains('soundcloud')) {
      return const Icon(Icons.cloud_queue_rounded, size: 16, color: Color(0xFFFF5500));
    } else if (provider.contains('deezer')) {
      return const Icon(Icons.music_note_rounded, size: 16, color: Color(0xFFEF5466));
    }
    // Unknown provider - show generic icon
    return const Icon(Icons.album_rounded, size: 16, color: Colors.white70);
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

    // Update peek player based on drag direction (must be inside setState to trigger rebuild)
    setState(() {
      _slideOffset = newSlideOffset;
      if (_slideOffset != 0) {
        _updatePeekPlayerState(maProvider, _slideOffset);
      }
    });
  }

  /// Update peek player state variables (called inside setState)
  void _updatePeekPlayerState(MusicAssistantProvider maProvider, double dragDirection) {
    // dragDirection < 0 means swiping left (next player)
    // dragDirection > 0 means swiping right (previous player)
    final isNext = dragDirection < 0;
    final newPeekPlayer = _getAdjacentPlayer(maProvider, next: isNext);

    if (newPeekPlayer?.playerId != _peekPlayer?.playerId) {
      _peekPlayer = newPeekPlayer;
      // Get the peek player's current track image if available
      if (_peekPlayer != null) {
        _peekTrack = maProvider.getCachedTrackForPlayer(_peekPlayer.playerId);
        _peekImageUrl = _peekTrack != null ? maProvider.getImageUrl(_peekTrack, size: 512) : null;
      } else {
        _peekTrack = null;
        _peekImageUrl = null;
      }
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
    _isSliding = true;

    // Mark transition BEFORE animation - this keeps peek content visible
    // and hides main content to prevent any flash
    _inTransition = true;

    final startOffset = _slideOffset;
    final targetOffset = direction < 0 ? -1.0 : 1.0;

    _slideController.reset();

    void animateToTarget() {
      if (!mounted) return;
      final curvedValue = Curves.easeOutCubic.transform(_slideController.value);
      setState(() {
        _slideOffset = startOffset + (targetOffset - startOffset) * curvedValue;
      });
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
      setState(() {
        _slideOffset = 0.0;
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
      setState(() {
        _slideOffset = startOffset * (1.0 - curvedValue);
      });
    }

    _slideController.addListener(animateBack);
    _slideController.duration = const Duration(milliseconds: 300);

    _slideController.forward().then((_) {
      if (!mounted) return;
      _slideController.removeListener(animateBack);
      setState(() {
        _slideOffset = 0.0;
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

        return AnimatedBuilder(
          animation: Listenable.merge([_expandAnimation, _queuePanelAnimation]),
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
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

    // Apply slide offset for hiding
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + bottomOffset + 20);
    final adjustedBottomOffset = bottomOffset - slideDownAmount;

    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;

    return Positioned(
      left: _collapsedMargin,
      right: _collapsedMargin,
      bottom: adjustedBottomOffset,
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
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
    // Only update if we have adaptive colors, otherwise keep previous value
    if (adaptiveScheme != null) {
      _currentExpandedBgColor = expandedBg;
    } else if (_currentExpandedBgColor == null) {
      _currentExpandedBgColor = expandedBg; // First time fallback
    }
    // When collapsed, use the darker unplayed color as base (progress bar will overlay the played portion)
    // When expanded, transition to the normal background
    final backgroundColor = Color.lerp(t < 0.5 ? collapsedBgUnplayed : collapsedBg, expandedBg, t)!;

    final collapsedTextColor = themeProvider.adaptiveTheme && adaptiveScheme != null
        ? adaptiveScheme.onPrimaryContainer
        : colorScheme.onPrimaryContainer;
    final expandedTextColor = adaptiveScheme?.onSurface ?? Colors.white;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, t)!;

    final primaryColor = adaptiveScheme?.primary ?? Colors.white;

    // Always position above bottom nav bar
    final bottomNavSpace = _bottomNavHeight + bottomPadding;
    final collapsedBottomOffset = bottomNavSpace + _collapsedMargin;
    final expandedBottomOffset = bottomNavSpace;
    final expandedHeight = screenSize.height - bottomNavSpace;

    // Apply slide offset to hide mini player (slides down off-screen)
    // Only apply when collapsed (t == 0), don't affect expanded state
    final slideDownAmount = widget.slideOffset * (_collapsedHeight + collapsedBottomOffset + 20);
    final slideAdjustedBottomOffset = t < 0.1
        ? collapsedBottomOffset - slideDownAmount
        : _lerpDouble(collapsedBottomOffset, expandedBottomOffset, t);

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

    final collapsedArtTop = 0.0;
    final expandedArtTop = topPadding + headerHeight + 16;
    final artTop = _lerpDouble(collapsedArtTop, expandedArtTop, t);

    // Typography - clear hierarchy
    // Title: bold, prominent (24px)
    // Artist: medium weight, secondary (18px expanded, was 16px)
    // Album: light, tertiary (15px expanded, was 13px)
    final titleFontSize = _lerpDouble(16.0, 24.0, t);
    final artistFontSize = _lerpDouble(14.0, 18.0, t); // Increased from 16 to 18

    final collapsedTitleLeft = _collapsedArtSize + 8; // Reduced from 12 to 8 (4px less)
    final expandedTitleLeft = contentPadding;
    final titleLeft = _lerpDouble(collapsedTitleLeft, expandedTitleLeft, t);

    final collapsedTitleTop = (_collapsedHeight - 36) / 2; // Centered vertically (adjusted for increased track/artist gap)

    final collapsedTitleWidth = screenSize.width - _collapsedArtSize - 150;
    final expandedTitleWidth = screenSize.width - (contentPadding * 2);
    final titleWidth = _lerpDouble(collapsedTitleWidth, expandedTitleWidth, t);

    // Measure actual title height for dynamic layout (CACHED to avoid layout every frame)
    final titleStyle = TextStyle(
      fontSize: 24.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    );
    // Only recalculate if track name or width changed
    if (_lastMeasuredTrackName != currentTrack.name ||
        _lastMeasuredTitleWidth != expandedTitleWidth ||
        _cachedExpandedTitleHeight == null) {
      final titlePainter = TextPainter(
        text: TextSpan(text: currentTrack.name, style: titleStyle),
        maxLines: 2,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: expandedTitleWidth);
      _cachedExpandedTitleHeight = titlePainter.height;
      _lastMeasuredTrackName = currentTrack.name;
      _lastMeasuredTitleWidth = expandedTitleWidth;
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
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
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
    final collapsedArtistTop = collapsedTitleTop + 22; // Increased gap from 18 to 22
    final expandedArtistTop = expandedTitleTop + expandedTitleHeight + titleToArtistGap;
    final artistTop = _lerpDouble(collapsedArtistTop, expandedArtistTop, t);

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

    // Queue panel slide amount (0 = hidden, 1 = fully visible)
    final queueT = _queuePanelAnimation.value;

    // Check if we have multiple players for swipe gesture
    final availablePlayers = _getAvailablePlayersSorted(maProvider);
    final hasMultiplePlayers = availablePlayers.length > 1;
    final selectedPlayerId = selectedPlayer.playerId;

    // Calculate slide offset for mini player content (only when collapsed)
    final miniPlayerSlideOffset = t < 0.1 ? _slideOffset * collapsedWidth : 0.0;

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomOffset,
      child: GestureDetector(
        // Use translucent to allow child widgets (like buttons) to receive taps
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!isExpanded) expand();
        },
        onVerticalDragUpdate: (details) {
          if (details.primaryDelta! < -10 && !isExpanded) {
            expand();
          } else if (details.primaryDelta! > 10 && isExpanded && !isQueuePanelOpen) {
            collapse();
          }
        },
        onHorizontalDragStart: (details) {
          _horizontalDragStartX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          // Only handle in collapsed mode with multiple players
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
          // Ignore swipes that started near the edges (Android back gesture zone)
          final screenWidth = MediaQuery.of(context).size.width;
          final startedInDeadZone = _horizontalDragStartX != null &&
              (_horizontalDragStartX! > screenWidth - _edgeDeadZone ||
               _horizontalDragStartX! < _edgeDeadZone);
          _horizontalDragStartX = null;

          if (startedInDeadZone) return;

          if (isExpanded) {
            // Expanded mode: swipe to open/close queue
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -300 && !isQueuePanelOpen) {
                _toggleQueuePanel();
              } else if (details.primaryVelocity! > 300 && isQueuePanelOpen) {
                _toggleQueuePanel();
              }
            }
          } else if (hasMultiplePlayers) {
            // Collapsed mode: use finger-following handler
            _handleHorizontalDragEnd(details, maProvider);
          }
        },
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
          elevation: _lerpDouble(4, 0, t),
          shadowColor: Colors.black.withOpacity(0.3),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Mini player progress bar background (collapsed only)
                // Shows played portion with brighter color, unplayed with darker
                if (t < 0.5 && currentTrack?.duration != null)
                  Positioned.fill(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _progressNotifier,
                      builder: (context, elapsedSeconds, _) {
                        final totalSeconds = currentTrack!.duration!.inSeconds;
                        if (totalSeconds <= 0) return const SizedBox.shrink();
                        final progress = (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
                        // Fade out as we expand
                        final progressOpacity = (1.0 - (t / 0.5)).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: progressOpacity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(borderRadius),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: width * progress,
                                height: height,
                                color: collapsedBg,
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
                    maProvider: maProvider,
                    peekPlayer: _peekPlayer,
                    peekImageUrl: _peekImageUrl,
                    slideOffset: _slideOffset,
                    containerWidth: collapsedWidth,
                    artSize: _collapsedArtSize,
                    titleLeft: collapsedTitleLeft,
                    titleTop: collapsedTitleTop,
                    titleWidth: collapsedTitleWidth,
                    artistTop: collapsedArtistTop,
                    titleFontSize: 16.0,
                    artistFontSize: 14.0,
                    textColor: textColor,
                    colorScheme: colorScheme,
                  ),

                // Album art - with slide animation when collapsed
                // Hidden during transition to prevent flash (peek content shows instead)
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                if (!(_inTransition && t < 0.1))
                  Positioned(
                    left: artLeft + miniPlayerSlideOffset,
                    top: artTop,
                    child: GestureDetector(
                      onTap: t > 0.5 ? () => _showFullscreenArt(context, imageUrl) : null,
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

                // Provider icons overlay (expanded only)
                if (t > 0.5 && _showProviderIcons && !(_inTransition && t < 0.1))
                  Positioned(
                    left: artLeft + artSize - 8,
                    top: artTop + 8,
                    child: Transform.translate(
                      offset: Offset(-(_buildProviderIcons(currentTrack).length * 28).toDouble(), 0),
                      child: Opacity(
                        opacity: ((t - 0.5) / 0.5).clamp(0.0, 1.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _buildProviderIcons(currentTrack),
                        ),
                      ),
                    ),
                  ),

                // Track title - with slide animation when collapsed
                // Hidden during transition to prevent flash
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                if (!(_inTransition && t < 0.1))
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
                          fontWeight: t > 0.5 ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: t > 0.5 ? -0.5 : 0,
                          height: 1.2,
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: t > 0.5 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Artist name - with slide animation when collapsed
                // Hidden during transition to prevent flash
                // GPU PERF: Use conditional instead of Opacity to avoid saveLayer
                if (!(_inTransition && t < 0.1))
                  Positioned(
                    left: titleLeft + miniPlayerSlideOffset,
                    top: artistTop,
                    child: SizedBox(
                      width: titleWidth,
                      child: Text(
                        currentTrack.artistsString,
                        style: TextStyle(
                          color: textColor.withOpacity(t > 0.5 ? 0.7 : 0.6),
                          fontSize: artistFontSize,
                          fontWeight: t > 0.5 ? FontWeight.w400 : FontWeight.normal,
                        ),
                        textAlign: t > 0.5 ? TextAlign.center : TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Album name (expanded only)
                // GPU PERF: Use color alpha instead of Opacity widget
                if (currentTrack.album != null && t > 0.3)
                  Positioned(
                    left: contentPadding,
                    right: contentPadding,
                    top: _lerpDouble(artistTop + 24, expandedAlbumTop, t),
                    child: Text(
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
                                                SnackBar(content: Text('Error seeking: $e')),
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
                Positioned(
                  left: t > 0.5 ? 0 : null,
                  right: t > 0.5 ? 0 : collapsedControlsRight - miniPlayerSlideOffset,
                  top: controlsTop,
                  child: Row(
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

                // Favorite button (expanded only) - hide when queue panel is open
                // GPU PERF: Use icon color alpha instead of Opacity
                if (t > 0.3 && queueT < 0.5)
                  Positioned(
                    top: topPadding + 4,
                    right: 52,
                    child: IconButton(
                      icon: Icon(
                        _isCurrentTrackFavorite ? Icons.favorite : Icons.favorite_border,
                        color: (_isCurrentTrackFavorite ? Colors.red : textColor)
                            .withOpacity(((t - 0.3) / 0.7).clamp(0.0, 1.0) * (1 - queueT * 2).clamp(0.0, 1.0)),
                        size: 24,
                      ),
                      onPressed: () => _toggleCurrentTrackFavorite(currentTrack),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),

                // Queue button (expanded only) - hide when queue panel is open
                // GPU PERF: Use icon color alpha instead of Opacity
                if (t > 0.3 && queueT < 0.5)
                  Positioned(
                    top: topPadding + 4,
                    right: 4,
                    child: IconButton(
                      icon: Icon(
                        Icons.queue_music_rounded,
                        color: textColor.withOpacity(((t - 0.3) / 0.7).clamp(0.0, 1.0) * (1 - queueT * 2).clamp(0.0, 1.0)),
                        size: 24,
                      ),
                      onPressed: _toggleQueuePanel,
                      padding: const EdgeInsets.all(12),
                    ),
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

                // Queue panel (slides in from right)
                if (t > 0.5 && queueT > 0)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(_queuePanelAnimation),
                        child: QueuePanel(
                          maProvider: maProvider,
                          queue: _queue,
                          isLoading: _isLoadingQueue,
                          textColor: textColor,
                          primaryColor: primaryColor,
                          backgroundColor: expandedBg,
                          topPadding: topPadding,
                          onClose: _toggleQueuePanel,
                          onRefresh: _loadQueue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build the peek player content that slides in from the edge during drag
  Widget _buildPeekContent({
    required MusicAssistantProvider maProvider,
    required dynamic peekPlayer,
    required String? peekImageUrl,
    required double slideOffset,
    required double containerWidth,
    required double artSize,
    required double titleLeft,
    required double titleTop,
    required double titleWidth,
    required double artistTop,
    required double titleFontSize,
    required double artistFontSize,
    required Color textColor,
    required ColorScheme colorScheme,
  }) {
    // Calculate sliding position
    // During transition (_inTransition = true), peek should be at center (offset 0)
    // When sliding left (negative offset), peek comes from right
    // When sliding right (positive offset), peek comes from left

    double peekBaseOffset;

    if (_inTransition && slideOffset.abs() < 0.01) {
      // During transition with slideOffset at 0, show peek at center
      peekBaseOffset = 0.0;
    } else {
      final isFromRight = slideOffset < 0;
      final peekProgress = slideOffset.abs();

      // Position calculation:
      // From right: starts at containerWidth (off right edge), moves to 0 as progress increases
      // From left: starts at -containerWidth (off left edge), moves to 0 as progress increases
      peekBaseOffset = isFromRight
          ? containerWidth * (1 - peekProgress)  // Slides in from right
          : -containerWidth * (1 - peekProgress); // Slides in from left
    }

    // Check if peek player has a track - if not, show device info instead
    final hasTrack = _peekTrack != null && peekImageUrl != null;
    final peekTrackName = hasTrack ? _peekTrack!.name : (peekPlayer?.name ?? 'Unknown');
    final peekArtistName = hasTrack ? (_peekTrack!.artistsString ?? '') : 'Swipe to switch device';

    return Stack(
      children: [
        // Peek album art / device icon
        Positioned(
          left: peekBaseOffset,
          top: 0,
          child: Container(
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
            ),
            child: hasTrack
                ? CachedNetworkImage(
                    imageUrl: peekImageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 256,
                    memCacheHeight: 256,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    placeholder: (_, __) => _buildMiniPlaceholderArt(colorScheme),
                    errorWidget: (_, __, ___) => _buildMiniPlaceholderArt(colorScheme),
                  )
                : _buildDeviceIcon(peekPlayer?.name ?? '', artSize, colorScheme),
          ),
        ),

        // Peek track title / device name
        Positioned(
          left: titleLeft + peekBaseOffset,
          top: titleTop,
          child: SizedBox(
            width: titleWidth,
            child: Text(
              peekTrackName,
              style: TextStyle(
                color: textColor,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // Peek artist name / device hint
        Positioned(
          left: titleLeft + peekBaseOffset,
          top: artistTop,
          child: SizedBox(
            width: titleWidth,
            child: Text(
              peekArtistName,
              style: TextStyle(
                color: textColor.withOpacity(0.6),
                fontSize: artistFontSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// Build device icon for non-playing peek player
  Widget _buildDeviceIcon(String playerName, double size, ColorScheme colorScheme) {
    final nameLower = playerName.toLowerCase();
    IconData icon;
    if (nameLower.contains('phone') || nameLower.contains('ensemble')) {
      icon = Icons.phone_android_rounded;
    } else if (nameLower.contains('group') || nameLower.contains('all')) {
      icon = Icons.speaker_group_rounded;
    } else if (nameLower.contains('tv') || nameLower.contains('television')) {
      icon = Icons.tv_rounded;
    } else if (nameLower.contains('cast') || nameLower.contains('chromecast')) {
      icon = Icons.cast_rounded;
    } else {
      icon = Icons.speaker_rounded;
    }

    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          color: colorScheme.onSurfaceVariant,
          size: size * 0.5,
        ),
      ),
    );
  }

  /// Simplified placeholder for mini player peek
  Widget _buildMiniPlaceholderArt(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme, double t) {
    return Container(
      color: Color.lerp(colorScheme.surfaceVariant, const Color(0xFF2a2a2a), t),
      child: Icon(
        Icons.music_note_rounded,
        color: Color.lerp(colorScheme.onSurfaceVariant, Colors.white24, t),
        size: _lerpDouble(24, 120, t),
      ),
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
      child: IconButton(
        icon: Icon(icon),
        color: color,
        iconSize: 22,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
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
