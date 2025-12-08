import 'package:flutter/material.dart';
import '../animated_icon_button.dart';
import '../../theme/design_tokens.dart';

/// Playback control buttons (shuffle, previous, play/pause, next, repeat)
class PlayerControls extends StatelessWidget {
  final bool isPlaying;
  final bool? shuffle;
  final String? repeatMode;
  final Color textColor;
  final Color primaryColor;
  final Color backgroundColor;
  final double skipButtonSize;
  final double playButtonSize;
  final double playButtonContainerSize;
  final double progress; // Animation progress 0-1
  final double expandedElementsOpacity;
  final bool isLoadingQueue;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback? onStop;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onCycleRepeat;

  const PlayerControls({
    super.key,
    required this.isPlaying,
    this.shuffle,
    this.repeatMode,
    required this.textColor,
    required this.primaryColor,
    required this.backgroundColor,
    required this.skipButtonSize,
    required this.playButtonSize,
    required this.playButtonContainerSize,
    required this.progress,
    required this.expandedElementsOpacity,
    required this.isLoadingQueue,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.onStop,
    this.onToggleShuffle,
    this.onCycleRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final t = progress;
    final isExpanded = t > 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isExpanded ? MainAxisAlignment.center : MainAxisAlignment.end,
      children: [
        // Shuffle (expanded only)
        if (isExpanded)
          Opacity(
            opacity: expandedElementsOpacity,
            child: _buildSecondaryButton(
              icon: Icons.shuffle_rounded,
              color: shuffle == true ? primaryColor : textColor.withOpacity(0.5),
              onPressed: isLoadingQueue ? null : onToggleShuffle,
            ),
          ),
        if (isExpanded) SizedBox(width: _lerpDouble(0, 20, t)),

        // Previous
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: onPrevious,
          useAnimation: isExpanded,
        ),
        SizedBox(width: _lerpDouble(0, 20, t)),

        // Play/Pause
        _buildPlayButton(),
        SizedBox(width: _lerpDouble(0, 20, t)),

        // Next
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          color: textColor,
          size: skipButtonSize,
          onPressed: onNext,
          useAnimation: isExpanded,
        ),

        // Repeat (expanded only)
        if (isExpanded) SizedBox(width: _lerpDouble(0, 20, t)),
        if (isExpanded)
          Opacity(
            opacity: expandedElementsOpacity,
            child: _buildSecondaryButton(
              icon: repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: repeatMode != null && repeatMode != 'off'
                  ? primaryColor
                  : textColor.withOpacity(0.5),
              onPressed: isLoadingQueue ? null : onCycleRepeat,
            ),
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
      padding: Spacing.paddingAll4,
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

  Widget _buildPlayButton() {
    final bgColor = Color.lerp(Colors.transparent, primaryColor, progress);
    final iconColor = Color.lerp(textColor, backgroundColor, progress);

    return GestureDetector(
      onLongPress: onStop,
      child: Container(
        width: playButtonContainerSize,
        height: playButtonContainerSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: iconColor,
          iconSize: playButtonSize,
          onPressed: onPlayPause,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
