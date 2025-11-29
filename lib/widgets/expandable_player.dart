import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../models/player.dart';
import '../screens/queue_screen.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import 'animated_icon_button.dart';
import 'volume_control.dart';

/// A unified player widget that seamlessly expands from mini to full-screen.
///
/// This replaces the separate MiniPlayer and NowPlayingScreen with a single
/// component that animates smoothly between collapsed and expanded states.
class ExpandablePlayer extends StatefulWidget {
  const ExpandablePlayer({super.key});

  @override
  State<ExpandablePlayer> createState() => ExpandablePlayerState();
}

class ExpandablePlayerState extends State<ExpandablePlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  // Adaptive theme colors extracted from album art
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _lastImageUrl;

  // Queue state
  PlayerQueue? _queue;
  bool _isLoadingQueue = false;

  // Progress timer for elapsed time updates
  Timer? _progressTimer;
  double? _seekPosition;

  // Collapsed height - more compact mini player
  static const double _collapsedHeight = 64.0;
  static const double _collapsedMargin = 8.0;
  static const double _collapsedBorderRadius = 16.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        _loadQueue();
        _startProgressTimer();
      } else if (status == AnimationStatus.dismissed) {
        _progressTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  void expand() {
    _controller.forward();
  }

  void collapse() {
    _controller.reverse();
  }

  bool get isExpanded => _controller.value > 0.5;

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && isExpanded) {
        setState(() {});
      }
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
        NetworkImage(imageUrl),
      );

      if (colorSchemes != null && mounted) {
        setState(() {
          _lightColorScheme = colorSchemes.$1;
          _darkColorScheme = colorSchemes.$2;
        });
      }
    } catch (e) {
      print('Failed to extract colors: $e');
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Consumer<MusicAssistantProvider>(
      builder: (context, maProvider, child) {
        final selectedPlayer = maProvider.selectedPlayer;
        final currentTrack = maProvider.currentTrack;

        // Don't show if no track or player
        if (currentTrack == null || selectedPlayer == null) {
          return const SizedBox.shrink();
        }

        final imageUrl = maProvider.getImageUrl(currentTrack, size: 512);

        // Extract colors for adaptive theme
        if (themeProvider.adaptiveTheme && imageUrl != null) {
          _extractColors(imageUrl);
        }

        return AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, _) {
            return _buildPlayer(
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

  Widget _buildPlayer(
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

    // Get adaptive colors if available
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    // Interpolate colors based on expansion
    final expandProgress = _expandAnimation.value;

    // Background color transitions from primaryContainer to adaptive/dark background
    final collapsedBg = colorScheme.primaryContainer;
    final expandedBg = adaptiveScheme?.surface ?? const Color(0xFF1a1a1a);
    final backgroundColor = Color.lerp(collapsedBg, expandedBg, expandProgress)!;

    // Text/icon colors
    final collapsedTextColor = colorScheme.onPrimaryContainer;
    final expandedTextColor = adaptiveScheme?.onSurface ?? Colors.white;
    final textColor = Color.lerp(collapsedTextColor, expandedTextColor, expandProgress)!;

    // Primary accent color for buttons/sliders
    final primaryColor = adaptiveScheme?.primary ?? Colors.white;

    // Calculate dimensions based on expansion
    final collapsedWidth = screenSize.width - (_collapsedMargin * 2);
    final expandedWidth = screenSize.width;
    final width = lerpDouble(collapsedWidth, expandedWidth, expandProgress);

    final collapsedTotalHeight = _collapsedHeight;
    final expandedTotalHeight = screenSize.height;
    final height = lerpDouble(collapsedTotalHeight, expandedTotalHeight, expandProgress);

    // Margins shrink to zero when expanded
    final horizontalMargin = lerpDouble(_collapsedMargin, 0, expandProgress);
    final bottomMargin = lerpDouble(_collapsedMargin, 0, expandProgress);

    // Border radius shrinks when expanded
    final borderRadius = lerpDouble(_collapsedBorderRadius, 0, expandProgress);

    // Album art size
    final collapsedArtSize = _collapsedHeight;
    final expandedArtSize = screenSize.width * 0.75;
    final artSize = lerpDouble(collapsedArtSize, expandedArtSize, expandProgress);

    return Positioned(
      left: horizontalMargin,
      right: horizontalMargin,
      bottom: bottomMargin,
      child: GestureDetector(
        onTap: () {
          if (!isExpanded) expand();
        },
        onVerticalDragUpdate: (details) {
          // Swipe up to expand, down to collapse
          if (details.primaryDelta! < -10 && !isExpanded) {
            expand();
          } else if (details.primaryDelta! > 10 && isExpanded) {
            collapse();
          }
        },
        child: Material(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius!),
          elevation: lerpDouble(4, 0, expandProgress)!,
          shadowColor: Colors.black.withOpacity(0.3),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                // Main content
                _buildContent(
                  context,
                  maProvider,
                  selectedPlayer,
                  currentTrack,
                  imageUrl,
                  expandProgress,
                  artSize!,
                  textColor,
                  primaryColor,
                  backgroundColor,
                  topPadding,
                  bottomPadding,
                  screenSize,
                ),

                // Collapse button (only visible when expanded)
                if (expandProgress > 0.3)
                  Positioned(
                    top: topPadding + 8,
                    left: 8,
                    child: Opacity(
                      opacity: ((expandProgress - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.keyboard_arrow_down, color: textColor, size: 32),
                        onPressed: collapse,
                      ),
                    ),
                  ),

                // Queue button (only visible when expanded)
                if (expandProgress > 0.3)
                  Positioned(
                    top: topPadding + 8,
                    right: 8,
                    child: Opacity(
                      opacity: ((expandProgress - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: IconButton(
                        icon: Icon(Icons.queue_music, color: textColor),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const QueueScreen()),
                          );
                        },
                      ),
                    ),
                  ),

                // Player name (only visible when expanded)
                if (expandProgress > 0.5)
                  Positioned(
                    top: topPadding + 16,
                    left: 0,
                    right: 0,
                    child: Opacity(
                      opacity: ((expandProgress - 0.5) / 0.5).clamp(0.0, 1.0),
                      child: Text(
                        selectedPlayer.name,
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                        textAlign: TextAlign.center,
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

  Widget _buildContent(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    double expandProgress,
    double artSize,
    Color textColor,
    Color primaryColor,
    Color backgroundColor,
    double topPadding,
    double bottomPadding,
    Size screenSize,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (expandProgress < 0.3) {
      // Collapsed (mini player) layout
      return _buildCollapsedLayout(
        context,
        maProvider,
        selectedPlayer,
        currentTrack,
        imageUrl,
        textColor,
        colorScheme,
      );
    } else if (expandProgress > 0.7) {
      // Expanded (full screen) layout
      return _buildExpandedLayout(
        context,
        maProvider,
        selectedPlayer,
        currentTrack,
        imageUrl,
        artSize,
        textColor,
        primaryColor,
        backgroundColor,
        topPadding,
        bottomPadding,
        screenSize,
      );
    } else {
      // Transition state - crossfade between layouts
      final transitionProgress = ((expandProgress - 0.3) / 0.4).clamp(0.0, 1.0);
      return Stack(
        children: [
          Opacity(
            opacity: 1 - transitionProgress,
            child: _buildCollapsedLayout(
              context,
              maProvider,
              selectedPlayer,
              currentTrack,
              imageUrl,
              textColor,
              colorScheme,
            ),
          ),
          Opacity(
            opacity: transitionProgress,
            child: _buildExpandedLayout(
              context,
              maProvider,
              selectedPlayer,
              currentTrack,
              imageUrl,
              artSize,
              textColor,
              primaryColor,
              backgroundColor,
              topPadding,
              bottomPadding,
              screenSize,
            ),
          ),
        ],
      );
    }
  }

  Widget _buildCollapsedLayout(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    Color textColor,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        // Album art - square, full height
        SizedBox(
          width: _collapsedHeight,
          height: _collapsedHeight,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(_collapsedBorderRadius),
              bottomLeft: Radius.circular(_collapsedBorderRadius),
            ),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 128,
                    cacheHeight: 128,
                    errorBuilder: (_, __, ___) => _buildPlaceholderArt(colorScheme),
                  )
                : _buildPlaceholderArt(colorScheme),
          ),
        ),
        const SizedBox(width: 12),

        // Track info
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentTrack.name,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                currentTrack.artistsString,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Compact controls
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          color: textColor,
          size: 28,
          onPressed: () => maProvider.previousTrackSelectedPlayer(),
        ),
        _buildPlayPauseButton(
          isPlaying: selectedPlayer.isPlaying,
          color: textColor,
          size: 34,
          onPressed: () => maProvider.playPauseSelectedPlayer(),
          onLongPress: () => maProvider.stopPlayer(selectedPlayer.playerId),
        ),
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          color: textColor,
          size: 28,
          onPressed: () => maProvider.nextTrackSelectedPlayer(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildExpandedLayout(
    BuildContext context,
    MusicAssistantProvider maProvider,
    dynamic selectedPlayer,
    dynamic currentTrack,
    String? imageUrl,
    double artSize,
    Color textColor,
    Color primaryColor,
    Color backgroundColor,
    double topPadding,
    double bottomPadding,
    Size screenSize,
  ) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          top: topPadding + 40,
          left: 24,
          right: 24,
          bottom: 16,
        ),
        child: Column(
          children: [
            const Spacer(),

            // Large album art
            Center(
              child: Container(
                width: artSize,
                height: artSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 1024,
                          cacheHeight: 1024,
                          errorBuilder: (_, __, ___) => _buildLargePlaceholderArt(),
                        )
                      : _buildLargePlaceholderArt(),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Track info
            Text(
              currentTrack.name,
              style: TextStyle(
                color: textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              currentTrack.artistsString,
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (currentTrack.album != null) ...[
              const SizedBox(height: 4),
              Text(
                currentTrack.album!.name,
                style: TextStyle(
                  color: textColor.withOpacity(0.5),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 32),

            // Progress bar
            if (currentTrack.duration != null) ...[
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: (_seekPosition ?? selectedPlayer.currentElapsedTime)
                      .clamp(0, currentTrack.duration!.inSeconds.toDouble()),
                  max: currentTrack.duration!.inSeconds.toDouble(),
                  onChanged: (value) => setState(() => _seekPosition = value),
                  onChangeStart: (value) => setState(() => _seekPosition = value),
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
                      if (mounted) setState(() => _seekPosition = null);
                    }
                  },
                  activeColor: primaryColor,
                  inactiveColor: primaryColor.withOpacity(0.24),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration((_seekPosition ?? selectedPlayer.currentElapsedTime).toInt()),
                      style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                    ),
                    Text(
                      _formatDuration(currentTrack.duration!.inSeconds),
                      style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ] else
              LinearProgressIndicator(
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            const SizedBox(height: 16),

            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: _queue?.shuffle == true ? primaryColor : textColor.withOpacity(0.5),
                  ),
                  iconSize: 24,
                  onPressed: _isLoadingQueue ? null : _toggleShuffle,
                ),
                const SizedBox(width: 12),
                AnimatedIconButton(
                  icon: Icons.skip_previous_rounded,
                  color: textColor,
                  iconSize: 42,
                  onPressed: () => maProvider.previousTrackSelectedPlayer(),
                ),
                const SizedBox(width: 12),
                _buildLargePlayPauseButton(
                  isPlaying: selectedPlayer.isPlaying,
                  primaryColor: primaryColor,
                  backgroundColor: backgroundColor,
                  onPressed: () => maProvider.playPauseSelectedPlayer(),
                ),
                const SizedBox(width: 12),
                AnimatedIconButton(
                  icon: Icons.skip_next_rounded,
                  color: textColor,
                  iconSize: 42,
                  onPressed: () => maProvider.nextTrackSelectedPlayer(),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    _queue?.repeatMode == 'one' ? Icons.repeat_one : Icons.repeat,
                    color: _queue?.repeatMode != null && _queue!.repeatMode != 'off'
                        ? primaryColor
                        : textColor.withOpacity(0.5),
                  ),
                  iconSize: 24,
                  onPressed: _isLoadingQueue ? null : _cycleRepeat,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Volume control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const VolumeControl(compact: false),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceVariant,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildLargePlaceholderArt() {
    return Container(
      color: const Color(0xFF2a2a2a),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white24,
        size: 120,
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon),
      color: color,
      iconSize: size,
      onPressed: onPressed,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildPlayPauseButton({
    required bool isPlaying,
    required Color color,
    required double size,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        color: color,
        iconSize: size,
        onPressed: onPressed,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildLargePlayPauseButton({
    required bool isPlaying,
    required Color primaryColor,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: primaryColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        color: backgroundColor,
        iconSize: 42,
        onPressed: onPressed,
      ),
    );
  }
}

double? lerpDouble(double a, double b, double t) {
  return a + (b - a) * t;
}
