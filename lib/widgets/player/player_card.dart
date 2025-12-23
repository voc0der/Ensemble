import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../providers/music_assistant_provider.dart';
import '../../theme/design_tokens.dart';
import '../../l10n/app_localizations.dart';

/// A player card that matches the mini player's visual style.
/// Used in the player reveal overlay when swiping down or tapping the device button.
class PlayerCard extends StatelessWidget {
  final dynamic player;
  final dynamic trackInfo;
  final String? albumArtUrl;
  final bool isSelected;
  final bool isPlaying;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onPower;

  const PlayerCard({
    super.key,
    required this.player,
    this.trackInfo,
    this.albumArtUrl,
    required this.isSelected,
    required this.isPlaying,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.onPlayPause,
    this.onSkipNext,
    this.onPower,
  });

  @override
  Widget build(BuildContext context) {
    // Match mini player dimensions
    const double cardHeight = Dimensions.miniPlayerHeight; // 64px
    const double artSize = cardHeight;
    const double borderRadius = Radii.xl; // 16px - same as mini player

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: backgroundColor,
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
              child: albumArtUrl != null
                  ? CachedNetworkImage(
                      imageUrl: albumArtUrl!,
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
                            player.name,
                            style: TextStyle(
                              color: textColor,
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
                        color: textColor.withOpacity(0.6),
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
            if (player.available && player.powered && trackInfo != null) ...[
              // Play/Pause - smaller to reduce total width
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  icon: Icon(
                    isPlaying ? MdiIcons.pause : MdiIcons.play,
                    color: textColor,
                    size: 28,
                  ),
                  onPressed: onPlayPause,
                  padding: EdgeInsets.zero,
                ),
              ),
              // Skip next
              IconButton(
                icon: Icon(
                  MdiIcons.skipNext,
                  color: textColor,
                  size: 28,
                ),
                onPressed: onSkipNext,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
            // Power button - smallest, always shown when available
            if (player.available)
              IconButton(
                icon: Icon(
                  MdiIcons.power,
                  color: player.powered ? textColor : textColor.withOpacity(0.5),
                  size: 20,
                ),
                onPressed: onPower,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),

            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerIcon() {
    // Darker shade of the card background to match album art square
    final iconBgColor = Color.lerp(backgroundColor, Colors.black, 0.15)!;
    return Container(
      color: iconBgColor,
      child: Center(
        child: Icon(
          Icons.speaker_rounded,
          color: textColor.withOpacity(0.4),
          size: 28,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (!player.available) {
      return Colors.grey.withOpacity(0.5);
    }
    if (!player.powered) {
      return Colors.grey;
    }
    if (isPlaying) {
      return Colors.green;
    }
    if (trackInfo != null) {
      return Colors.orange; // Has content but paused
    }
    return Colors.grey.shade400; // Idle
  }

  String _getSubtitle(BuildContext context) {
    if (!player.available) {
      return S.of(context)!.playerStateUnavailable;
    }
    if (!player.powered) {
      return S.of(context)!.playerStateOff;
    }
    if (trackInfo != null) {
      return trackInfo.name ?? S.of(context)!.playerStateIdle;
    }
    return S.of(context)!.playerStateIdle;
  }
}
