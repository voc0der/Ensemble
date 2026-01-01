import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_assistant_provider.dart';
import '../../theme/design_tokens.dart';
import '../../l10n/app_localizations.dart';

/// A player card that matches the mini player's visual style.
/// Used in the player reveal overlay when swiping down or tapping the device button.
/// Supports horizontal swipe to adjust volume with a two-tone overlay.
class PlayerCard extends StatefulWidget {
  final dynamic player;
  final dynamic trackInfo;
  final String? albumArtUrl;
  final bool isSelected;
  final bool isPlaying;
  final bool isGrouped;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onPower;
  final ValueChanged<double>? onVolumeChange;

  // Pastel yellow for grouped players
  static const Color groupBorderColor = Color(0xFFFFF59D);

  const PlayerCard({
    super.key,
    required this.player,
    this.trackInfo,
    this.albumArtUrl,
    required this.isSelected,
    required this.isPlaying,
    this.isGrouped = false,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.onLongPress,
    this.onPlayPause,
    this.onSkipNext,
    this.onPower,
    this.onVolumeChange,
  });

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  bool _isDraggingVolume = false;
  double _dragVolumeLevel = 0.0;
  double _dragStartX = 0.0;
  double _cardWidth = 0.0;
  int _lastVolumeUpdateTime = 0;
  static const int _volumeThrottleMs = 150; // Only send volume updates every 150ms

  @override
  Widget build(BuildContext context) {
    // Match mini player dimensions
    const double cardHeight = Dimensions.miniPlayerHeight;
    const double artSize = cardHeight;
    const double borderRadius = Radii.xl; // 16px - same as mini player

    // Colors for volume overlay (same as mini player progress bar)
    final filledColor = widget.backgroundColor;
    final unfilledColor = Color.lerp(widget.backgroundColor, Colors.black, 0.3)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        _cardWidth = constraints.maxWidth;

        return GestureDetector(
          onTap: _isDraggingVolume ? null : widget.onTap,
          onLongPress: _isDraggingVolume ? null : widget.onLongPress,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          // Use Stack to render border ON TOP of content, preventing album art clipping
          child: Stack(
            children: [
              // Main card content (hidden when dragging volume)
              if (!_isDraggingVolume)
                _buildCardContent(cardHeight, artSize, borderRadius),

              // Volume overlay (shown when dragging)
              if (_isDraggingVolume)
                Container(
                  height: cardHeight,
                  decoration: BoxDecoration(
                    color: unfilledColor,
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _dragVolumeLevel.clamp(0.0, 1.0),
                      heightFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: filledColor,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(borderRadius),
                            bottomLeft: Radius.circular(borderRadius),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Border overlay - renders ON TOP to prevent clipping by album art
              if (widget.isGrouped)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(color: PlayerCard.groupBorderColor, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardContent(double cardHeight, double artSize, double borderRadius) {
    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Album art or speaker icon - same size for consistent text alignment
          SizedBox(
            width: artSize,
            height: artSize,
            child: widget.albumArtUrl != null
                ? CachedNetworkImage(
                    imageUrl: widget.albumArtUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, __) => _buildSpeakerIcon(),
                    errorWidget: (_, __, ___) => _buildSpeakerIcon(),
                  )
                : _buildSpeakerIcon(),
          ),

          // Player info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Player name
                  Row(
                    children: [
                      // Status indicator
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _getStatusColor(),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.player.name,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                            decoration: TextDecoration.none,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Track name or status
                  Text(
                    _getSubtitle(context),
                    style: TextStyle(
                      color: widget.textColor.withOpacity(0.6),
                      fontSize: 14,
                      fontFamily: 'Roboto',
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Transport controls - compact sizing to align with mini player
          // Play/Pause and Next only shown when powered with content
          if (widget.player.available && widget.player.powered && widget.trackInfo != null) ...[
            // Play/Pause - slight nudge right
            Transform.translate(
              offset: const Offset(3, 0),
              child: SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: Icon(
                    widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: widget.textColor,
                    size: 28,
                  ),
                  onPressed: widget.onPlayPause,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            // Skip next - nudged right to close gap with power
            Transform.translate(
              offset: const Offset(6, 0),
              child: IconButton(
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: widget.textColor,
                  size: 28,
                ),
                onPressed: widget.onSkipNext,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
          // Power button - smallest
          if (widget.player.available)
            IconButton(
              icon: Icon(
                Icons.power_settings_new_rounded,
                color: widget.player.powered ? widget.textColor : widget.textColor.withOpacity(0.5),
                size: 20,
              ),
              onPressed: widget.onPower,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    // Get current volume from player
    final currentVolume = (widget.player.volumeLevel ?? 0).toDouble() / 100.0;
    setState(() {
      _isDraggingVolume = true;
      _dragVolumeLevel = currentVolume;
    });
    HapticFeedback.lightImpact();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingVolume || _cardWidth <= 0) return;

    // Calculate volume change based on drag distance
    // Full card width = 100% volume range
    final dragDelta = details.delta.dx;
    final volumeDelta = dragDelta / _cardWidth;

    final newVolume = (_dragVolumeLevel + volumeDelta).clamp(0.0, 1.0);

    // Always update visual
    if ((newVolume - _dragVolumeLevel).abs() > 0.001) {
      setState(() {
        _dragVolumeLevel = newVolume;
      });

      // Throttle API calls to prevent flooding
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastVolumeUpdateTime >= _volumeThrottleMs) {
        _lastVolumeUpdateTime = now;
        widget.onVolumeChange?.call(newVolume);
      }
    }
  }

  void _onDragEnd(DragEndDetails details) {
    // Send final volume on release
    widget.onVolumeChange?.call(_dragVolumeLevel);
    setState(() {
      _isDraggingVolume = false;
    });
    HapticFeedback.lightImpact();
  }

  void _onDragCancel() {
    setState(() {
      _isDraggingVolume = false;
    });
  }

  Widget _buildSpeakerIcon() {
    // Darker shade of the card background to match album art square
    final iconBgColor = Color.lerp(widget.backgroundColor, Colors.black, 0.15)!;
    return Container(
      color: iconBgColor,
      child: Center(
        child: Icon(
          Icons.speaker_rounded,
          color: widget.textColor.withOpacity(0.4),
          size: 28,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (!widget.player.available) {
      return Colors.grey.withOpacity(0.5);
    }
    if (!widget.player.powered) {
      return Colors.grey;
    }
    if (widget.isPlaying) {
      return Colors.green;
    }
    if (widget.trackInfo != null) {
      return Colors.orange; // Has content but paused
    }
    return Colors.grey.shade400; // Idle
  }

  String _getSubtitle(BuildContext context) {
    if (!widget.player.available) {
      return S.of(context)!.playerStateUnavailable;
    }
    if (!widget.player.powered) {
      return S.of(context)!.playerStateOff;
    }
    if (widget.trackInfo != null) {
      return widget.trackInfo.name ?? S.of(context)!.playerStateIdle;
    }
    return S.of(context)!.playerStateIdle;
  }
}
