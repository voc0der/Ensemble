import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shared constants for mini player layout
class MiniPlayerLayout {
  static const double height = 72.0;
  static const double artSize = 72.0;
  static const double textLeftOffset = 10.0; // Gap between art and text
  static const double textLeft = artSize + textLeftOffset; // 82px
  // 3-line layout: track, artist, player
  static const double primaryTop = 7.0;
  static const double secondaryTop = 27.0;
  static const double tertiaryTop = 46.0;
  static const double textRightPadding = 12.0;
  static const double iconSize = 28.0;
  static const double iconOpacity = 0.4;
  static const double secondaryTextOpacity = 0.6;
  static const double primaryFontSize = 16.0;
  static const double secondaryFontSize = 14.0;
  static const double tertiaryFontSize = 14.0;
  static const FontWeight primaryFontWeight = FontWeight.w500;
}

/// Unified mini player content widget used by:
/// - DeviceSelectorBar (non-playing state)
/// - ExpandablePlayer collapsed state (playing state)
/// - Peek content during swipe gestures
class MiniPlayerContent extends StatelessWidget {
  /// Primary text line (track name or device name)
  final String primaryText;

  /// Secondary text line (artist name or "Swipe to switch device")
  /// If null, primary text will be vertically centered
  final String? secondaryText;

  /// Album art URL - if null, shows device icon
  final String? imageUrl;

  /// Player name for icon selection when no image
  final String playerName;

  /// Background color for the content area
  final Color backgroundColor;

  /// Text color
  final Color textColor;

  /// Width of the content area
  final double width;

  /// Horizontal slide offset for swipe animation (-1 to 1)
  final double slideOffset;

  /// Whether secondary text is a hint (shows lightbulb icon)
  final bool isHint;

  /// Whether to show the progress bar overlay (for playing state)
  final bool showProgress;

  /// Progress value 0.0 to 1.0 (only used if showProgress is true)
  final double progress;

  const MiniPlayerContent({
    super.key,
    required this.primaryText,
    this.secondaryText,
    this.imageUrl,
    required this.playerName,
    required this.backgroundColor,
    required this.textColor,
    required this.width,
    this.slideOffset = 0.0,
    this.isHint = false,
    this.showProgress = false,
    this.progress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final hasSecondaryLine = secondaryText != null && secondaryText!.isNotEmpty;
    final slidePixels = slideOffset * width;

    // Calculate text width (leaves room for right padding)
    final textWidth = width - MiniPlayerLayout.textLeft - MiniPlayerLayout.textRightPadding;

    // Darkened background for icon area (matches DeviceSelectorBar)
    final iconAreaBackground = Color.lerp(backgroundColor, Colors.black, 0.15)!;

    return SizedBox(
      width: width,
      height: MiniPlayerLayout.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Progress bar background (only for playing state)
          if (showProgress && progress > 0)
            Positioned(
              left: MiniPlayerLayout.artSize + slidePixels,
              top: 0,
              bottom: 0,
              width: (width - MiniPlayerLayout.artSize) * progress,
              child: Container(color: backgroundColor),
            ),

          // Art / Icon area - centered vertically
          Positioned(
            left: slidePixels,
            top: (MiniPlayerLayout.height - MiniPlayerLayout.artSize) / 2,
            child: SizedBox(
              width: MiniPlayerLayout.artSize,
              height: MiniPlayerLayout.artSize,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 256,
                      memCacheHeight: 256,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => _buildIconArea(iconAreaBackground),
                      errorWidget: (_, __, ___) => _buildIconArea(iconAreaBackground),
                    )
                  : _buildIconArea(iconAreaBackground),
            ),
          ),

          // Primary text line
          Positioned(
            left: MiniPlayerLayout.textLeft + slidePixels,
            top: hasSecondaryLine
                ? MiniPlayerLayout.primaryTop
                : (MiniPlayerLayout.height - MiniPlayerLayout.primaryFontSize) / 2,
            right: MiniPlayerLayout.textRightPadding - slidePixels,
            child: Text(
              primaryText,
              style: TextStyle(
                color: textColor,
                fontSize: MiniPlayerLayout.primaryFontSize,
                fontWeight: MiniPlayerLayout.primaryFontWeight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Secondary text line (with optional hint icon)
          if (hasSecondaryLine)
            Positioned(
              left: MiniPlayerLayout.textLeft + slidePixels,
              top: MiniPlayerLayout.secondaryTop,
              right: MiniPlayerLayout.textRightPadding - slidePixels,
              child: isHint
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: textColor.withOpacity(MiniPlayerLayout.secondaryTextOpacity),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            secondaryText!,
                            style: TextStyle(
                              color: textColor.withOpacity(MiniPlayerLayout.secondaryTextOpacity),
                              fontSize: MiniPlayerLayout.secondaryFontSize,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      secondaryText!,
                      style: TextStyle(
                        color: textColor.withOpacity(MiniPlayerLayout.secondaryTextOpacity),
                        fontSize: MiniPlayerLayout.secondaryFontSize,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
        ],
      ),
    );
  }

  /// Build the icon area with device-appropriate icon
  Widget _buildIconArea(Color background) {
    return Container(
      color: background,
      child: Center(
        child: Icon(
          _getPlayerIcon(playerName),
          color: textColor.withOpacity(MiniPlayerLayout.iconOpacity),
          size: MiniPlayerLayout.iconSize,
        ),
      ),
    );
  }

  /// Get appropriate icon based on player name
  static IconData _getPlayerIcon(String playerName) {
    final nameLower = playerName.toLowerCase();
    if (nameLower.contains('phone') || nameLower.contains('ensemble') || nameLower.contains('mobile')) {
      return Icons.phone_android_rounded;
    } else if (nameLower.contains('group') || nameLower.contains('sync') || nameLower.contains('all')) {
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
