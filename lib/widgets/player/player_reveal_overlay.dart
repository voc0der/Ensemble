import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/music_assistant_provider.dart';
import '../../services/settings_service.dart';
import '../../theme/design_tokens.dart';
import '../../theme/theme_provider.dart';
import '../../theme/palette_helper.dart';
import '../../constants/timings.dart';
import '../global_player_overlay.dart';
import 'player_card.dart';

/// Overlay that reveals all available players with a staggered slide-up animation.
/// Triggered by swiping down on the mini player or tapping the device button.
class PlayerRevealOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final double miniPlayerBottom; // Bottom position of mini player
  final double miniPlayerHeight;
  final bool showOnboardingHints; // Show additional hints for first-time users
  final bool miniPlayerInPrecisionMode; // When true, darken all cards
  final ValueChanged<bool>? onPlayerListPrecisionModeChanged; // Callback when any card enters/exits precision mode

  const PlayerRevealOverlay({
    super.key,
    required this.onDismiss,
    required this.miniPlayerBottom,
    required this.miniPlayerHeight,
    this.showOnboardingHints = false,
    this.miniPlayerInPrecisionMode = false,
    this.onPlayerListPrecisionModeChanged,
  });

  @override
  State<PlayerRevealOverlay> createState() => PlayerRevealOverlayState();
}

class PlayerRevealOverlayState extends State<PlayerRevealOverlay>
    with TickerProviderStateMixin {
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;
  late Animation<double> _backdropAnimation;

  Timer? _refreshTimer;

  // Track vertical drag for dismissal
  double _dragOffset = 0;
  bool _isDragging = false;

  // Scroll controller for when player list overflows
  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = false;

  // Cache extracted colors per player for per-device accent colors
  final Map<String, ColorScheme?> _playerColors = {};

  // Hint system
  bool _showHints = true;

  // Precision mode - track which player card is in precision mode (null = none)
  String? _precisionModePlayerId;

  void _onPrecisionModeChanged(String playerId, bool isActive) {
    setState(() {
      _precisionModePlayerId = isActive ? playerId : null;
    });
    // Notify parent so mini player can also darken
    widget.onPlayerListPrecisionModeChanged?.call(isActive);
  }

  /// Create a saturation matrix for ColorFilter
  /// saturation: 1.0 = normal, 0.0 = grayscale
  List<double> _saturationMatrix(double saturation) {
    final s = saturation;
    return [
      0.2126 + 0.7874 * s, 0.7152 - 0.7152 * s, 0.0722 - 0.0722 * s, 0, 0,
      0.2126 - 0.2126 * s, 0.7152 + 0.2848 * s, 0.0722 - 0.0722 * s, 0, 0,
      0.2126 - 0.2126 * s, 0.7152 - 0.7152 * s, 0.0722 + 0.9278 * s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  @override
  void initState() {
    super.initState();

    // Load hint settings
    SettingsService.getShowHints().then((value) {
      if (mounted) setState(() => _showHints = value);
    });

    _revealController = AnimationController(
      vsync: this,
    );

    // Quick smooth animation with subtle overshoot
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _backdropAnimation = CurvedAnimation(
      parent: _revealController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    // Preload all player track info and extract colors
    _preloadColorsForPlayers();

    // Start reveal animation
    _revealController.duration = const Duration(milliseconds: 200);
    _revealController.forward();

    // Auto-refresh player data
    _refreshTimer = Timer.periodic(Timings.playerPollingInterval, (_) {
      if (mounted) {
        final provider = context.read<MusicAssistantProvider>();
        provider.refreshPlayers();
        provider.preloadAllPlayerTracks().then((_) => _preloadColorsForPlayers());
      }
    });
  }

  /// Extract accent colors from album art for each player
  Future<void> _preloadColorsForPlayers() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await maProvider.preloadAllPlayerTracks();

    final players = maProvider.availablePlayers;
    for (final player in players) {
      if (_playerColors.containsKey(player.playerId)) continue;

      final track = maProvider.getCachedTrackForPlayer(player.playerId);
      if (track == null) continue;

      final imageUrl = maProvider.getImageUrl(track, size: 128);
      if (imageUrl == null) continue;

      try {
        final imageProvider = NetworkImage(imageUrl);
        final schemes = await PaletteHelper.extractColorSchemes(imageProvider);
        if (mounted && schemes != null) {
          final colorScheme = isDark ? schemes.$2 : schemes.$1;
          setState(() {
            _playerColors[player.playerId] = colorScheme;
          });
        }
      } catch (_) {
        // Ignore color extraction errors
      }
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Animate reveal (called from parent)
  void reveal() {
    _revealController.duration = const Duration(milliseconds: 200);
    _revealController.forward();
  }

  /// Animate dismissal and call callback when done
  void dismiss() {
    // Trigger single bounce on mini player when cards are ~70% collapsed
    // This creates the effect of cards "landing" on the mini player
    bool bounceFired = false;
    void checkBounce() {
      if (!bounceFired && _revealController.value < 0.3) {
        bounceFired = true;
        GlobalPlayerOverlay.triggerBounce();
      }
    }

    _revealController.duration = const Duration(milliseconds: 150);
    _revealController.addListener(checkBounce);
    _revealController.reverse().then((_) {
      _revealController.removeListener(checkBounce);
      widget.onDismiss();
    });
  }

  /// Check if scroll is at top (or not scrollable)
  bool get _isAtTop {
    if (!_isScrollable) return true;
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset <= 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;

    // If scrollable and not at top, let scroll handle it
    if (_isScrollable && !_isAtTop) {
      // Scroll the list
      if (_scrollController.hasClients) {
        final newOffset = _scrollController.offset - delta;
        _scrollController.jumpTo(newOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      }
      return;
    }

    // At top: check if trying to scroll down (view more) or dismiss
    if (_isScrollable && delta < 0 && _scrollController.hasClients) {
      // Swiping up (delta negative) = scroll down to see more players
      final newOffset = _scrollController.offset - delta;
      _scrollController.jumpTo(newOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
      return;
    }

    // Only process dismiss gesture when swiping DOWN (positive delta = finger moving down)
    // Ignore swipe up when not scrollable - cards should stay fixed
    if (delta <= 0) return;

    // Swiping down = dismiss gesture
    setState(() {
      _isDragging = true;
      _dragOffset += delta;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // If not dragging (was scrolling), don't dismiss
    if (!_isDragging) return;

    // Dismiss if dragged down enough or with enough velocity
    if (_dragOffset > 100 || velocity > 500) {
      HapticFeedback.lightImpact();
      // Reset drag offset before dismiss so animation starts from correct position
      setState(() {
        _isDragging = false;
        _dragOffset = 0;
      });
      dismiss();
    } else {
      // Spring back
      setState(() {
        _isDragging = false;
        _dragOffset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Back gesture is handled at GlobalPlayerOverlay level
    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final allPlayers = maProvider.availablePlayers;
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Filter out the selected player - it's already shown in the mini player
        final players = allPlayers
            .where((p) => p.playerId != selectedPlayer?.playerId)
            .toList();

        // Default card colors - used when player doesn't have extracted colors
        final defaultBgColor = colorScheme.primaryContainer;
        final defaultTextColor = colorScheme.onPrimaryContainer;

        // Calculate total stack height for animation
        const cardHeight = 64.0;
        const cardSpacing = 12.0;
        final totalStackHeight = players.length * cardHeight + (players.length - 1) * cardSpacing;

        // Calculate max available height (80% of screen minus mini player area)
        final screenHeight = MediaQuery.of(context).size.height;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        final bottomPadding = widget.miniPlayerBottom + widget.miniPlayerHeight + 20;
        final maxListHeight = (screenHeight - statusBarHeight - bottomPadding) * 0.8;

        // Determine if scrolling is needed
        final needsScroll = totalStackHeight > maxListHeight;
        // Update scrollable state (used by gesture handlers)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isScrollable != needsScroll) {
            _isScrollable = needsScroll;
          }
        });

        return AnimatedBuilder(
          animation: _revealAnimation,
          builder: (context, child) {
            final t = _revealAnimation.value;

            return Stack(
              children: [
                // Backdrop - tap to dismiss (darkness handled by GlobalPlayerOverlay)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),

                // Player cards - positioned above mini player
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: widget.miniPlayerBottom + widget.miniPlayerHeight + 8 - _dragOffset,
                  child: GestureDetector(
                    onVerticalDragUpdate: _handleVerticalDragUpdate,
                    onVerticalDragEnd: _handleVerticalDragEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Hint above player list - different for onboarding vs regular use
                        // Onboarding: show first-time hint (how to select)
                        // Regular: show sync hint (tap and hold to sync)
                        if (players.isNotEmpty && (_showHints || widget.showOnboardingHints))
                          Builder(
                            builder: (context) {
                              // Calculate slide offset to match the topmost card
                              const baseOffset = 80.0;
                              final hintDistanceToTravel = baseOffset + (players.length * (cardHeight + cardSpacing));
                              final hintSlideOffset = hintDistanceToTravel * (1.0 - t);

                              // Show different hint for onboarding vs regular use
                              final isOnboarding = widget.showOnboardingHints;

                              Widget buildHintRow(IconData icon, String text) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 18,
                                      color: colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: colorScheme.onSurface.withOpacity(0.7),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Transform.translate(
                                offset: Offset(0, hintSlideOffset),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: isOnboarding
                                        ? buildHintRow(Icons.touch_app_outlined, S.of(context)!.selectPlayerHint)
                                        : Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              buildHintRow(Icons.lightbulb_outline, S.of(context)!.holdToSync),
                                              const SizedBox(height: 4),
                                              buildHintRow(Icons.lightbulb_outline, S.of(context)!.swipeToAdjustVolume),
                                            ],
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        // Build player cards - scrollable when overflow, otherwise static
                        // Using ListView.builder for many players: only builds visible items
                        // This significantly improves animation performance with 10+ players
                        if (needsScroll)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxListHeight),
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              itemCount: players.length,
                              // Fixed height per item for optimal scroll performance
                              itemExtent: cardHeight + cardSpacing,
                              itemBuilder: (context, index) {
                                final player = players[index];
                                final isPlaying = player.state == 'playing';
                                final playerTrack = maProvider.getCachedTrackForPlayer(player.playerId);
                                String? albumArtUrl;
                                if (playerTrack != null && player.available && player.powered) {
                                  albumArtUrl = maProvider.getImageUrl(playerTrack, size: 128);
                                }
                                final playerColorScheme = _playerColors[player.playerId];
                                final cardBgColor = playerColorScheme?.primaryContainer ?? defaultBgColor;
                                final cardTextColor = playerColorScheme?.onPrimaryContainer ?? defaultTextColor;

                                // Animation: slide from behind mini player
                                // Only calculate for items that will be built (visible ones)
                                const baseOffset = 80.0;
                                final reverseIndex = players.length - 1 - index;
                                final distanceToTravel = baseOffset + (reverseIndex * (cardHeight + cardSpacing));
                                final slideOffset = distanceToTravel * (1.0 - t);

                                // Darken cards when:
                                // 1. Another card is in precision mode, OR
                                // 2. Mini player is in precision mode (darken ALL cards)
                                final isInPrecisionMode = _precisionModePlayerId == player.playerId;
                                final shouldDarken = widget.miniPlayerInPrecisionMode ||
                                    (_precisionModePlayerId != null && !isInPrecisionMode);

                                return Transform.translate(
                                  offset: Offset(0, slideOffset),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: cardSpacing),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 1.0, end: shouldDarken ? 0.5 : 1.0),
                                      duration: const Duration(milliseconds: 200),
                                      builder: (context, saturation, child) {
                                        return ColorFiltered(
                                          colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
                                          child: child,
                                        );
                                      },
                                      child: Stack(
                                        children: [
                                          PlayerCard(
                                            player: player,
                                            trackInfo: playerTrack,
                                            albumArtUrl: albumArtUrl,
                                            isSelected: false,
                                            isPlaying: isPlaying,
                                            isGrouped: maProvider.isPlayerManuallySynced(player.playerId),
                                            backgroundColor: cardBgColor,
                                            textColor: cardTextColor,
                                            onTap: () {
                                              HapticFeedback.mediumImpact();
                                              maProvider.selectPlayer(player);
                                              dismiss();
                                            },
                                            onLongPress: () {
                                              HapticFeedback.mediumImpact();
                                              maProvider.togglePlayerSync(player.playerId);
                                            },
                                            onPlayPause: () {
                                              if (isPlaying) {
                                                maProvider.pausePlayer(player.playerId);
                                              } else {
                                                maProvider.resumePlayer(player.playerId);
                                              }
                                            },
                                            onSkipNext: () => maProvider.nextTrack(player.playerId),
                                            onPower: () => maProvider.togglePower(player.playerId),
                                            onVolumeChange: (volume) => maProvider.setVolume(player.playerId, (volume * 100).round()),
                                            onPrecisionModeChanged: (isActive) => _onPrecisionModeChanged(player.playerId, isActive),
                                          ),
                                          // Dark overlay when another card is in precision mode
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: AnimatedOpacity(
                                                opacity: shouldDarken ? 1.0 : 0.0,
                                                duration: const Duration(milliseconds: 200),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    borderRadius: BorderRadius.circular(16), // Match card radius
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        else
                        // Non-scrollable list for when players fit
                        ...List.generate(players.length, (index) {
                          final player = players[index];
                          final isPlaying = player.state == 'playing';

                          // Get track info for this player
                          final playerTrack = maProvider.getCachedTrackForPlayer(player.playerId);

                          // Get album art URL - use track directly like mini player does
                          String? albumArtUrl;
                          if (playerTrack != null && player.available && player.powered) {
                            albumArtUrl = maProvider.getImageUrl(playerTrack, size: 128);
                          }

                          // Use per-player colors if available, otherwise use defaults
                          final playerColorScheme = _playerColors[player.playerId];
                          final cardBgColor = playerColorScheme?.primaryContainer ?? defaultBgColor;
                          final cardTextColor = playerColorScheme?.onPrimaryContainer ?? defaultTextColor;

                          // Animation: all cards start hidden behind mini player
                          // and fan out to their final positions with spring physics
                          const baseOffset = 80.0;
                          final reverseIndex = players.length - 1 - index;
                          final distanceToTravel = baseOffset + (reverseIndex * (cardHeight + cardSpacing));

                          // Use the elastic animation value directly (already has bounce)
                          final slideOffset = distanceToTravel * (1.0 - t);

                          // Darken cards when:
                          // 1. Another card is in precision mode, OR
                          // 2. Mini player is in precision mode (darken ALL cards)
                          final isInPrecisionMode = _precisionModePlayerId == player.playerId;
                          final shouldDarken = widget.miniPlayerInPrecisionMode ||
                              (_precisionModePlayerId != null && !isInPrecisionMode);

                          return Transform.translate(
                            offset: Offset(0, slideOffset),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 1.0, end: shouldDarken ? 0.5 : 1.0),
                                duration: const Duration(milliseconds: 200),
                                builder: (context, saturation, child) {
                                  return ColorFiltered(
                                    colorFilter: ColorFilter.matrix(_saturationMatrix(saturation)),
                                    child: child,
                                  );
                                },
                                child: Stack(
                                  children: [
                                    PlayerCard(
                                      player: player,
                                      trackInfo: playerTrack,
                                      albumArtUrl: albumArtUrl,
                                      isSelected: false,
                                      isPlaying: isPlaying,
                                      isGrouped: maProvider.isPlayerManuallySynced(player.playerId),
                                      backgroundColor: cardBgColor,
                                      textColor: cardTextColor,
                                      onTap: () {
                                        HapticFeedback.mediumImpact();
                                        maProvider.selectPlayer(player);
                                        dismiss();
                                      },
                                      onLongPress: () {
                                        HapticFeedback.mediumImpact();
                                        debugPrint('🔗 Long-press on ${player.name} (${player.playerId})');
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Syncing ${player.name}...'),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                        maProvider.togglePlayerSync(player.playerId);
                                      },
                                      onPlayPause: () {
                                        if (isPlaying) {
                                          maProvider.pausePlayer(player.playerId);
                                        } else {
                                          maProvider.resumePlayer(player.playerId);
                                        }
                                      },
                                      onSkipNext: () {
                                        maProvider.nextTrack(player.playerId);
                                      },
                                      onPower: () {
                                        maProvider.togglePower(player.playerId);
                                      },
                                      onVolumeChange: (volume) => maProvider.setVolume(player.playerId, (volume * 100).round()),
                                      onPrecisionModeChanged: (isActive) => _onPrecisionModeChanged(player.playerId, isActive),
                                    ),
                                    // Dark overlay when another card is in precision mode
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: AnimatedOpacity(
                                          opacity: shouldDarken ? 1.0 : 0.0,
                                          duration: const Duration(milliseconds: 200),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(16), // Match card radius
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
