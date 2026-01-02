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
  // 2-line layout (evenly spaced): player name, hint
  // Height 72 / 3 = 24px spacing. Line 1 center at 24, Line 2 center at 48
  static const double primaryTop2Line = 14.0; // 24 - (18/2) = 15, adjusted to 14
  static const double secondaryTop2Line = 40.0; // raised slightly from 42
  static const double textRightPadding = 12.0;
  static const double powerButtonSize = 40.0; // Power button tap area
  static const double iconSize = 28.0;
  static const double iconOpacity = 0.4;
  static const double secondaryTextOpacity = 0.6;
  static const double primaryFontSize = 18.0; // Increased from 16
  static const double primaryFontSize2Line = 18.0; // Larger for 2-line layout
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

  /// Tertiary text line (player name when playing)
  /// If provided, uses 3-line layout; if null, uses centered 2-line layout
  final String? tertiaryText;

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

  /// Callback for power button tap (only shown in 2-line mode when provided)
  final VoidCallback? onPowerToggle;

  /// Whether the player is currently powered on
  final bool isPoweredOn;

  const MiniPlayerContent({
    super.key,
    required this.primaryText,
    this.secondaryText,
    this.tertiaryText,
    this.imageUrl,
    required this.playerName,
    required this.backgroundColor,
    required this.textColor,
    required this.width,
    this.slideOffset = 0.0,
    this.isHint = false,
    this.showProgress = false,
    this.progress = 0.0,
    this.onPowerToggle,
    this.isPoweredOn = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasSecondaryLine = secondaryText != null && secondaryText!.isNotEmpty;
    final hasTertiaryLine = tertiaryText != null && tertiaryText!.isNotEmpty;
    final is2LineMode = !hasTertiaryLine;
    final showPowerButton = is2LineMode && onPowerToggle != null;
    final slidePixels = slideOffset * width;

    // Use 3-line layout when tertiary exists, 2-line centered otherwise
    final primaryTop = hasTertiaryLine ? MiniPlayerLayout.primaryTop : MiniPlayerLayout.primaryTop2Line;
    final secondaryTop = hasTertiaryLine ? MiniPlayerLayout.secondaryTop : MiniPlayerLayout.secondaryTop2Line;

    // Calculate right padding (extra space for power button in 2-line mode)
    final rightPadding = showPowerButton
        ? MiniPlayerLayout.powerButtonSize + 8.0
        : MiniPlayerLayout.textRightPadding;

    // Darkened background for icon area (matches DeviceSelectorBar)
    final iconAreaBackground = Color.lerp(backgroundColor, Colors.black, 0.15)!;

    // Font size for primary text (larger in 2-line mode)
    final primaryFontSize = is2LineMode
        ? MiniPlayerLayout.primaryFontSize2Line
        : MiniPlayerLayout.primaryFontSize;

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
                ? primaryTop
                : (MiniPlayerLayout.height - primaryFontSize) / 2,
            right: rightPadding - slidePixels,
            child: Text(
              primaryText,
              style: TextStyle(
                color: textColor,
                fontSize: primaryFontSize,
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
              top: secondaryTop,
              right: rightPadding - slidePixels,
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

          // Tertiary text line (player name, only for 3-line layout)
          if (hasTertiaryLine)
            Positioned(
              left: MiniPlayerLayout.textLeft + slidePixels,
              top: MiniPlayerLayout.tertiaryTop,
              right: MiniPlayerLayout.textRightPadding - slidePixels,
              child: Text(
                tertiaryText!,
                style: TextStyle(
                  color: textColor,
                  fontSize: MiniPlayerLayout.tertiaryFontSize,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Power button (only for 2-line mode when callback provided)
          // Matches PlayerCard power button style
          if (showPowerButton)
            Positioned(
              right: 8.0 - slidePixels,
              top: (MiniPlayerLayout.height - MiniPlayerLayout.powerButtonSize) / 2,
              child: IconButton(
                onPressed: onPowerToggle,
                icon: Icon(
                  Icons.power_settings_new_rounded,
                  color: isPoweredOn ? textColor : textColor.withOpacity(0.5),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
