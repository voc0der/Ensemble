import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../services/settings_service.dart';
import '../theme/theme_provider.dart';
import 'expandable_player.dart';
import 'player/player_reveal_overlay.dart';

/// Cached color with contrast adjustment
/// Avoids expensive HSL conversions during scroll
class _CachedNavColor {
  Color? _sourceColor;
  bool? _isDark;
  Color? _adjustedColor;

  Color getAdjustedColor(Color sourceColor, bool isDark) {
    // Return cached value if inputs haven't changed
    if (_sourceColor == sourceColor && _isDark == isDark && _adjustedColor != null) {
      return _adjustedColor!;
    }

    // Compute new adjusted color
    var navSelectedColor = sourceColor;
    if (isDark && navSelectedColor.computeLuminance() < 0.2) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.8)).toColor();
    } else if (!isDark && navSelectedColor.computeLuminance() > 0.8) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness - 0.3).clamp(0.2, 1.0)).toColor();
    }

    // Cache the result
    _sourceColor = sourceColor;
    _isDark = isDark;
    _adjustedColor = navSelectedColor;

    return navSelectedColor;
  }
}

final _cachedNavColor = _CachedNavColor();

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

/// Constants for bottom UI elements spacing
class BottomSpacing {
  /// Height of the bottom navigation bar
  static const double navBarHeight = 56.0;

  /// Height of mini player when visible (64px height + 12px margin)
  static const double miniPlayerHeight = 76.0;

  /// Space needed when only nav bar is visible (with some extra padding)
  static const double navBarOnly = navBarHeight + 16.0;

  /// Space needed when mini player is also visible
  static const double withMiniPlayer = navBarHeight + miniPlayerHeight + 22.0;
}

/// ValueNotifier for player expansion progress (0.0 to 1.0) and background color
class PlayerExpansionState {
  final double progress;
  final Color? backgroundColor;
  PlayerExpansionState(this.progress, this.backgroundColor);
}
final playerExpansionNotifier = ValueNotifier<PlayerExpansionState>(PlayerExpansionState(0.0, null));

/// Wrapper widget that provides a global player overlay above all navigation.
///
/// This ensures the mini player and expanded player are consistent across
/// all screens (home, library, album details, artist details, etc.) without
/// needing separate player instances in each screen.
class GlobalPlayerOverlay extends StatefulWidget {
  final Widget child;

  GlobalPlayerOverlay({
    required this.child,
  }) : super(key: _overlayStateKey);

  @override
  State<GlobalPlayerOverlay> createState() => _GlobalPlayerOverlayState();

  /// Collapse the player if it's expanded
  static void collapsePlayer() {
    globalPlayerKey.currentState?.collapse();
  }

  /// Check if the player is currently expanded
  static bool get isPlayerExpanded =>
      globalPlayerKey.currentState?.isExpanded ?? false;

  /// Get the current expansion progress (0.0 to 1.0)
  static double get expansionProgress =>
      globalPlayerKey.currentState?.expansionProgress ?? 0.0;

  /// Get the current expanded background color
  static Color? get expandedBackgroundColor =>
      globalPlayerKey.currentState?.currentExpandedBgColor;

  /// Hide the mini player temporarily (e.g., when showing device selector)
  /// The player slides down off-screen with animation
  static void hidePlayer() {
    _overlayStateKey.currentState?._setHidden(true);
  }

  /// Show the mini player again (slides back up)
  static void showPlayer() {
    _overlayStateKey.currentState?._setHidden(false);
  }

  /// Show the player reveal overlay with bounce animation
  static void showPlayerReveal() {
    _overlayStateKey.currentState?._showPlayerReveal();
  }

  /// Hide the player reveal overlay (no animation - used as callback from overlay)
  static void hidePlayerReveal() {
    _overlayStateKey.currentState?._hidePlayerReveal();
  }

  /// Dismiss the player reveal overlay with animation (for back gesture)
  static void dismissPlayerReveal() {
    _overlayStateKey.currentState?._dismissPlayerReveal();
  }

  /// Trigger the bounce animation on mini player (called when overlay dismiss starts)
  static void triggerBounce() {
    _overlayStateKey.currentState?._triggerBounce();
  }

  /// Check if the player reveal is currently visible
  static bool get isPlayerRevealVisible =>
      _overlayStateKey.currentState?._isRevealVisible ?? false;
}

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  // Controller for player reveal animation with bounce
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  // State for player reveal overlay
  bool _isRevealVisible = false;

  // Use ValueNotifier instead of setState for bounce offset
  // This prevents full widget tree rebuilds during animation
  final _bounceOffsetNotifier = ValueNotifier<double>(0.0);

  // Hint system state
  bool _showHints = true;
  bool _hintTriggered = false; // Prevent multiple triggers per session
  final _hintOpacityNotifier = ValueNotifier<double>(0.0);

  // Key for the reveal overlay
  final _revealKey = GlobalKey<PlayerRevealOverlayState>();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Bounce animation - double bounce for hint visibility
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _bounceAnimation = CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeOut,
    );

    // Use ValueNotifier instead of setState to avoid full widget rebuilds
    // This isolates the rebuild to only the widgets that depend on bounce offset
    _bounceController.addListener(() {
      final t = _bounceAnimation.value;
      // Double bounce: first bounce full (10px), second bounce smaller (6px)
      if (t < 0.25) {
        _bounceOffsetNotifier.value = 10.0 * (t * 4);           // 0 -> 10
      } else if (t < 0.5) {
        _bounceOffsetNotifier.value = 10.0 * ((0.5 - t) * 4);   // 10 -> 0
      } else if (t < 0.75) {
        _bounceOffsetNotifier.value = 6.0 * ((t - 0.5) * 4);    // 0 -> 6
      } else {
        _bounceOffsetNotifier.value = 6.0 * ((1.0 - t) * 4);    // 6 -> 0
      }
    });

    // Load hint settings
    _loadHintSettings();
  }

  Future<void> _loadHintSettings() async {
    _showHints = await SettingsService.getShowHints();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    _bounceOffsetNotifier.dispose();
    _hintOpacityNotifier.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    if (hidden) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  void _showPlayerReveal() {
    if (_isRevealVisible) return;
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
    }
    HapticFeedback.mediumImpact();
    _bounceController.reset();

    // Hide the hint immediately if it's showing
    _hintOpacityNotifier.value = 0.0;

    setState(() {
      _isRevealVisible = true;
    });
    _bounceController.forward();
  }

  void _hidePlayerReveal() {
    if (!_isRevealVisible) return;
    _bounceOffsetNotifier.value = 0;
    setState(() {
      _isRevealVisible = false;
    });
  }

  /// Dismiss with animation (for back gesture) - calls overlay's dismiss method
  void _dismissPlayerReveal() {
    if (!_isRevealVisible) return;
    // Call the overlay's dismiss method which has the slide animation
    // Note: dismiss() triggers the bounce animation internally
    _revealKey.currentState?.dismiss();
  }

  /// Trigger bounce animation on mini player
  void _triggerBounce() {
    _bounceController.reset();
    _bounceController.forward();
  }

  /// Trigger the pull-to-select hint with bounce animation
  /// Called when player first becomes available - shows on every app launch
  void _triggerPullHint() {
    if (_hintTriggered || !_showHints) return;
    _hintTriggered = true;

    // Show hint text
    _hintOpacityNotifier.value = 1.0;

    // Trigger bounce animation
    _bounceController.reset();
    _bounceController.forward().then((_) {
      // Fade out hint after lingering
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          _hintOpacityNotifier.value = 0.0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Handle back gesture at top level - dismiss device list if visible
    return PopScope(
      canPop: !_isRevealVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isRevealVisible) {
          _dismissPlayerReveal();
        }
      },
      child: Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        // Add bottom padding to account for bottom nav + mini player
        Padding(
          padding: const EdgeInsets.only(bottom: 0), // Content manages its own padding
          child: widget.child,
        ),
        // Global persistent bottom navigation bar - positioned at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ListenableBuilder(
            listenable: navigationProvider,
            builder: (context, _) {
              return Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  // Use adaptive primary color for bottom nav when adaptive theme is enabled
                  final sourceColor = themeProvider.adaptiveTheme
                      ? themeProvider.adaptivePrimaryColor
                      : colorScheme.primary;

                  // Use cached color computation to avoid expensive HSL operations during scroll
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final navSelectedColor = _cachedNavColor.getAdjustedColor(sourceColor, isDark);

                  // Base background: use adaptive surface color if available, otherwise default surface
                  final baseBgColor = (themeProvider.adaptiveTheme && themeProvider.adaptiveSurfaceColor != null)
                      ? themeProvider.adaptiveSurfaceColor!
                      : colorScheme.surface;

                  return ValueListenableBuilder<PlayerExpansionState>(
                    valueListenable: playerExpansionNotifier,
                    // Pass BottomNavigationBar as child to avoid rebuilding it every frame
                    child: BottomNavigationBar(
                      currentIndex: navigationProvider.selectedIndex,
                      onTap: (index) {
                        if (GlobalPlayerOverlay.isPlayerExpanded) {
                          GlobalPlayerOverlay.collapsePlayer();
                        }
                        navigationProvider.navigatorKey.currentState?.popUntil((route) => route.isFirst);
                        if (index == 3) {
                          GlobalPlayerOverlay.hidePlayer();
                        } else if (navigationProvider.selectedIndex == 3) {
                          GlobalPlayerOverlay.showPlayer();
                        }
                        navigationProvider.setSelectedIndex(index);
                      },
                      backgroundColor: Colors.transparent,
                      selectedItemColor: navSelectedColor,
                      unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      selectedFontSize: 12,
                      unselectedFontSize: 12,
                      items: [
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.home_outlined),
                          activeIcon: const Icon(Icons.home_rounded),
                          label: S.of(context)!.home,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.library_music_outlined),
                          activeIcon: const Icon(Icons.library_music_rounded),
                          label: S.of(context)!.library,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.search_rounded),
                          activeIcon: const Icon(Icons.search_rounded),
                          label: S.of(context)!.search,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.settings_outlined),
                          activeIcon: const Icon(Icons.settings_rounded),
                          label: S.of(context)!.settings,
                        ),
                      ],
                    ),
                    builder: (context, expansionState, navBar) {
                      // Only compute colors during animation - this is the hot path
                      final navBgColor = expansionState.progress > 0 && expansionState.backgroundColor != null
                          ? Color.lerp(baseBgColor, expansionState.backgroundColor, expansionState.progress)!
                          : baseBgColor;

                      // Use AnimatedContainer for smoother transitions instead of rebuilding
                      return Container(
                        decoration: BoxDecoration(
                          color: navBgColor,
                          boxShadow: expansionState.progress < 0.5
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, -2),
                                  ),
                                ]
                              : null,
                        ),
                        child: navBar, // Reuse pre-built navigation bar
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        // Blur backdrop when device selector is open
        if (_isRevealVisible)
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                ),
              ),
            ),
          ),

        // Player reveal overlay - renders BELOW mini player so cards slide behind it
        if (_isRevealVisible)
          PlayerRevealOverlay(
            key: _revealKey,
            onDismiss: _hidePlayerReveal,
            miniPlayerBottom: BottomSpacing.navBarHeight + MediaQuery.of(context).padding.bottom + 12,
            miniPlayerHeight: 64,
          ),

        // Global player overlay - renders ON TOP so cards slide behind it
        // Use Selector instead of Consumer to avoid rebuilds during animation
        Selector<MusicAssistantProvider, ({bool isConnected, bool hasPlayer})>(
          selector: (_, provider) => (
            isConnected: provider.isConnected,
            hasPlayer: provider.selectedPlayer != null,
          ),
          builder: (context, state, child) {
            // Only show player if connected and has a selected player
            if (!state.isConnected || !state.hasPlayer) {
              return const SizedBox.shrink();
            }

            // Trigger pull hint when player first becomes available (every app launch)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_hintTriggered && _showHints) {
                // Delay before showing hint to let UI settle
                Future.delayed(const Duration(milliseconds: 1500), () {
                  if (mounted) _triggerPullHint();
                });
              }
            });

            // Combine slide and bounce animations with ValueListenableBuilder
            // This prevents full widget tree rebuilds - only ExpandablePlayer updates
            return ValueListenableBuilder<double>(
              valueListenable: _bounceOffsetNotifier,
              builder: (context, bounceOffset, _) {
                return AnimatedBuilder(
                  animation: _slideAnimation,
                  builder: (context, _) {
                    return ExpandablePlayer(
                      key: globalPlayerKey,
                      slideOffset: _slideAnimation.value,
                      bounceOffset: bounceOffset,
                      onRevealPlayers: _showPlayerReveal,
                      isDeviceRevealVisible: _isRevealVisible,
                    );
                  },
                );
              },
            );
          },
        ),

        // Pull hint - positioned half-overlapping mini player top, bounces with it
        ValueListenableBuilder<double>(
          valueListenable: _hintOpacityNotifier,
          builder: (context, opacity, _) {
            if (opacity == 0) return const SizedBox.shrink();
            return ValueListenableBuilder<double>(
              valueListenable: _bounceOffsetNotifier,
              builder: (context, bounceOffset, _) {
                return Positioned(
                  left: 0,
                  right: 0,
                  // Position half-overlapping mini player top edge
                  bottom: BottomSpacing.navBarHeight + BottomSpacing.miniPlayerHeight + MediaQuery.of(context).padding.bottom - 12 - bounceOffset,
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 300),
                    child: Center(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              S.of(context)!.pullToSelectPlayers,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
      ),
    );
  }
}
