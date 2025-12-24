import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// A compact device selector bar shown when no track is playing
class DeviceSelectorBar extends StatelessWidget {
  final dynamic selectedPlayer;
  final dynamic peekPlayer;
  final bool hasMultiplePlayers;
  final Color backgroundColor;
  final Color textColor;
  final double width;
  final double height;
  final double borderRadius;
  final double slideOffset;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const DeviceSelectorBar({
    super.key,
    required this.selectedPlayer,
    this.peekPlayer,
    required this.hasMultiplePlayers,
    required this.backgroundColor,
    required this.textColor,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.slideOffset,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: hasMultiplePlayers ? onHorizontalDragStart : null,
      onHorizontalDragUpdate: hasMultiplePlayers ? onHorizontalDragUpdate : null,
      onHorizontalDragEnd: hasMultiplePlayers ? onHorizontalDragEnd : null,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.3),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: Stack(
              children: [
                // Peek player content (shows when dragging)
                if (slideOffset.abs() > 0.01 && peekPlayer != null)
                  _buildPeekContent(context),

                // Current player content
                Transform.translate(
                  offset: Offset(slideOffset * width, 0),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      children: [
                        // Speaker icon - same size as album art for consistent text alignment
                        Positioned(
                          left: 0,
                          top: 0,
                          child: SizedBox(
                            width: height,
                            height: height,
                            child: Container(
                              color: Color.lerp(backgroundColor, Colors.black, 0.15),
                              child: Center(
                                child: Icon(
                                  _getPlayerIcon(selectedPlayer.name),
                                  color: textColor.withOpacity(0.4),
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Primary line (device name)
                        Positioned(
                          left: height + 10,
                          top: hasMultiplePlayers ? 13 : (height - 16) / 2,
                          right: 12,
                          child: Text(
                            selectedPlayer.name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Secondary line (swipe hint)
                        if (hasMultiplePlayers)
                          Positioned(
                            left: height + 10,
                            top: 33,
                            right: 12,
                            child: Text(
                              S.of(context)!.swipeToSwitchDevice,
                              style: TextStyle(
                                color: textColor.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
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

  /// Build peek player content that slides in from the edge
  Widget _buildPeekContent(BuildContext context) {
    final isFromRight = slideOffset < 0;
    final peekProgress = slideOffset.abs();

    // Calculate peek position - slides in as main content slides out
    final peekBaseOffset = isFromRight
        ? width * (1 - peekProgress)
        : -width * (1 - peekProgress);

    return Transform.translate(
      offset: Offset(peekBaseOffset, 0),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            // Speaker icon - same size as album art for consistent text alignment
            Positioned(
              left: 0,
              top: 0,
              child: SizedBox(
                width: height,
                height: height,
                child: Container(
                  color: Color.lerp(backgroundColor, Colors.black, 0.15),
                  child: Center(
                    child: Icon(
                      _getPlayerIcon(peekPlayer.name),
                      color: textColor.withOpacity(0.4),
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
            // Primary line (device name)
            Positioned(
              left: height + 10,
              top: hasMultiplePlayers ? 13 : (height - 16) / 2,
              right: 12,
              child: Text(
                peekPlayer.name,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Secondary line (swipe hint)
            if (hasMultiplePlayers)
              Positioned(
                left: height + 10,
                top: 33,
                right: 12,
                child: Text(
                  S.of(context)!.swipeToSwitchDevice,
                  style: TextStyle(
                    color: textColor.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Get appropriate icon for player based on name
  IconData _getPlayerIcon(String playerName) {
    final nameLower = playerName.toLowerCase();
    if (nameLower.contains('phone') || nameLower.contains('ensemble')) {
      return Icons.phone_android_rounded;
    } else if (nameLower.contains('group')) {
      return Icons.speaker_group_rounded;
    } else if (nameLower.contains('tv') || nameLower.contains('television')) {
      return Icons.tv_rounded;
    } else if (nameLower.contains('cast') || nameLower.contains('chromecast')) {
      return Icons.cast_rounded;
    } else {
      return Icons.speaker_rounded;
    }
  }
}
