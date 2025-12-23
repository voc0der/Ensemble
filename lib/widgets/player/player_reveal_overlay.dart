import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/music_assistant_provider.dart';
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

  const PlayerRevealOverlay({
    super.key,
    required this.onDismiss,
    required this.miniPlayerBottom,
    required this.miniPlayerHeight,
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

  // Cache extracted colors per player for per-device accent colors
  final Map<String, ColorScheme?> _playerColors = {};

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      duration: const Duration(milliseconds: 150),
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
    super.dispose();
  }

  /// Animate reveal (called from parent)
  void reveal() {
    _revealController.forward();
  }

  /// Animate dismissal and call callback when done
  void dismiss() {
    // Trigger settle bounce on mini player when cards are ~70% collapsed
    // This creates the effect of cards "landing" on the mini player
    bool bounceFired = false;
    void checkBounce() {
      if (!bounceFired && _revealController.value < 0.3) {
        bounceFired = true;
        GlobalPlayerOverlay.triggerBounce();
      }
    }

    _revealController.addListener(checkBounce);
    _revealController.reverse().then((_) {
      _revealController.removeListener(checkBounce);
      widget.onDismiss();
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      // Negate delta so swipe down = cards move down (toward dismissal)
      _dragOffset -= details.primaryDelta ?? 0;
      // Clamp: allow moving down (positive) freely, limit moving up to 20px
      _dragOffset = _dragOffset.clamp(-20.0, double.infinity);
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

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

        return AnimatedBuilder(
          animation: _revealAnimation,
          builder: (context, child) {
            final t = _revealAnimation.value;

            return Stack(
              children: [
                // Backdrop - tap to dismiss
                Positioned.fill(
                  child: GestureDetector(
                    onTap: dismiss,
                    child: Container(
                      color: Colors.black.withOpacity(0.6 * _backdropAnimation.value),
                    ),
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
                        // Build player cards - all slide from behind mini player
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

                          return Transform.translate(
                            offset: Offset(0, slideOffset),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: PlayerCard(
                                player: player,
                                trackInfo: playerTrack,
                                albumArtUrl: albumArtUrl,
                                isSelected: false,
                                isPlaying: isPlaying,
                                backgroundColor: cardBgColor,
                                textColor: cardTextColor,
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  maProvider.selectPlayer(player);
                                  dismiss();
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
