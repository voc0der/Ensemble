import 'dart:async';
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

  /// Trigger single bounce on mini player (called when device selector collapses)
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

  // Single bounce controller for device selector expand/collapse
  late AnimationController _singleBounceController;

  // Double bounce controller for hint
  late AnimationController _doubleBounceController;

  // State for player reveal overlay
  bool _isRevealVisible = false;

  // State for interactive hint mode (blur backdrop + wait for user action)
  bool _isHintModeActive = false;
  Timer? _hintBounceTimer;

  // Track if player reveal was triggered from onboarding (for showing extra hints)
  bool _isOnboardingReveal = false;

  // Bounce offset for mini player (used by both single and double bounce)
  final _bounceOffsetNotifier = ValueNotifier<double>(0.0);

  // Hint system state
  bool _showHints = true;
  bool _hasCompletedOnboarding = false; // First-use welcome screen
  bool _hintTriggered = false; // Prevent multiple triggers per session
  bool _waitingForConnection = false; // Waiting for connection to show mini player hints
  bool _miniPlayerHintsReady = false; // True once connected with player (can show hints)
  final _hintOpacityNotifier = ValueNotifier<double>(0.0);

  // Welcome content fade-in animation
  late AnimationController _welcomeFadeController;

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

    // Single bounce for device selector expand/collapse
    _singleBounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _singleBounceController.addListener(() {
      final t = Curves.easeOut.transform(_singleBounceController.value);
      // Single bounce: up to 10px then back to 0
      if (t < 0.5) {
        _bounceOffsetNotifier.value = 10.0 * (t * 2);           // 0 -> 10
      } else {
        _bounceOffsetNotifier.value = 10.0 * ((1.0 - t) * 2);   // 10 -> 0
      }
    });

    // Hint bounce - single gentle bounce to draw attention
    _doubleBounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _doubleBounceController.addListener(() {
      final t = Curves.easeOut.transform(_doubleBounceController.value);
      // Single bounce: up 20px then back down
      if (t < 0.5) {
        _bounceOffsetNotifier.value = 20.0 * (t * 2);           // 0 -> 20
      } else {
        _bounceOffsetNotifier.value = 20.0 * ((1.0 - t) * 2);   // 20 -> 0
      }
    });

    // Welcome content fade-in
    _welcomeFadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Load hint settings and start welcome immediately if needed
    _loadHintSettings();
  }

  Future<void> _loadHintSettings() async {
    _showHints = await SettingsService.getShowHints();
    _hasCompletedOnboarding = await SettingsService.getHasCompletedOnboarding();
    // Mark that we need to show welcome after first connection (if first use)
    if (!_hasCompletedOnboarding && mounted && !_hintTriggered) {
      setState(() {
        _waitingForConnection = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if we should enable mini player hints now that we have connection
    _checkConnectionForMiniPlayerHints();
  }

  /// Check connection state and start welcome screen if appropriate
  void _checkConnectionForMiniPlayerHints() {
    if (!_waitingForConnection || _hintTriggered || !mounted) return;

    final provider = context.read<MusicAssistantProvider>();
    if (provider.isConnected && provider.selectedPlayer != null) {
      // Connected with a player - start welcome screen now
      _waitingForConnection = false;
      _miniPlayerHintsReady = true;
      _startWelcomeScreen();
      // Start the bounce animation now that mini player is visible
      _startMiniPlayerBounce();
    }
  }

  /// Start the bounce animation for mini player hints
  void _startMiniPlayerBounce() {
    if (!_isHintModeActive || !mounted) return;
    _doubleBounceController.reset();
    _doubleBounceController.forward();

    // Repeat bounce every 2 seconds
    _hintBounceTimer?.cancel();
    _hintBounceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isHintModeActive && mounted) {
        _doubleBounceController.reset();
        _doubleBounceController.forward();
      }
    });
  }

  /// Start the welcome screen with fade-in animation
  void _startWelcomeScreen() {
    if (_hintTriggered) return;
    _hintTriggered = true;

    // Activate hint mode immediately (blur backdrop visible)
    setState(() {
      _isHintModeActive = true;
    });

    // Fade in welcome content (logo + title)
    _welcomeFadeController.forward();

    // Mini player bounce is started separately once connected via _startMiniPlayerBounce()
  }

  @override
  void dispose() {
    _hintBounceTimer?.cancel();
    _slideController.dispose();
    _singleBounceController.dispose();
    _doubleBounceController.dispose();
    _welcomeFadeController.dispose();
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

    // Track if coming from hint mode (for onboarding hints in player selector)
    final wasInHintMode = _isHintModeActive;

    // End hint mode if active (user learned the gesture!)
    _hintBounceTimer?.cancel();
    _hintBounceTimer = null;
    _hintOpacityNotifier.value = 0.0;
    _isHintModeActive = false;

    // Mark onboarding as completed if coming from welcome screen
    if (wasInHintMode) {
      SettingsService.setHasCompletedOnboarding(true);
    }

    // Trigger single bounce on expand
    _singleBounceController.reset();
    _singleBounceController.forward();

    setState(() {
      _isRevealVisible = true;
      _isOnboardingReveal = wasInHintMode;
    });
  }

  void _hidePlayerReveal() {
    if (!_isRevealVisible) return;
    _bounceOffsetNotifier.value = 0;
    setState(() {
      _isRevealVisible = false;
      _isOnboardingReveal = false;
    });
  }

  /// Dismiss with animation (for back gesture) - calls overlay's dismiss method
  void _dismissPlayerReveal() {
    if (!_isRevealVisible) return;
    // Call the overlay's dismiss method which has the slide animation
    _revealKey.currentState?.dismiss();
  }

  /// Trigger single bounce on mini player (called when device selector collapses)
  void _triggerBounce() {
    _singleBounceController.reset();
    _singleBounceController.forward();
  }

  /// End hint mode (called when user taps skip button)
  void _endHintMode() {
    if (!_isHintModeActive) return;
    _hintBounceTimer?.cancel();
    _hintBounceTimer = null;
    _hintOpacityNotifier.value = 0.0;
    _bounceOffsetNotifier.value = 0.0;
    // Mark onboarding as completed (first use only)
    SettingsService.setHasCompletedOnboarding(true);
    setState(() {
      _isHintModeActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watch provider state synchronously to catch connection changes immediately
    // This ensures the preemptive backdrop renders in the same frame as home screen
    final provider = context.watch<MusicAssistantProvider>();
    final isReadyForWelcome = provider.isConnected && provider.selectedPlayer != null;

    // Show solid backdrop when waiting for connection AND now connected (covers home screen)
    final shouldShowPreemptiveBackdrop = _waitingForConnection &&
        !_isHintModeActive &&
        isReadyForWelcome;

    // Trigger welcome screen start if we just became ready
    if (shouldShowPreemptiveBackdrop && !_hintTriggered) {
      // Schedule for post-frame to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _waitingForConnection && !_hintTriggered) {
          _waitingForConnection = false;
          _miniPlayerHintsReady = true;
          _startWelcomeScreen();
          _startMiniPlayerBounce();
        }
      });
    }

    // Handle back gesture at top level - dismiss hint mode or device list if visible
    return PopScope(
      canPop: !_isRevealVisible && !_isHintModeActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isHintModeActive) {
            _endHintMode();
          } else if (_isRevealVisible) {
            _dismissPlayerReveal();
          }
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
        // Only show when connected (hides on login screen)
        Selector<MusicAssistantProvider, bool>(
          selector: (_, provider) => provider.isConnected,
          builder: (context, isConnected, child) {
            if (!isConnected) return const SizedBox.shrink();
            return child!;
          },
          child: Positioned(
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
        ),
        // Blur backdrop for device selector (reveal mode) - static, no animation
        if (_isRevealVisible && !_isHintModeActive)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissPlayerReveal,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(
                  color: colorScheme.surface.withOpacity(0.5),
                ),
              ),
            ),
          ),

        // Preemptive solid backdrop - shows instantly when transitioning to welcome
        // This covers the home screen before the animated welcome starts
        // Uses synchronous provider.watch() check from build method for immediate response
        if (shouldShowPreemptiveBackdrop)
          Positioned.fill(
            child: Container(
              color: colorScheme.surface,
            ),
          ),

        // Blur backdrop for hint/welcome mode - animated fade from solid to semi-transparent
        if (_isHintModeActive)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              // Hold solid for 2s, then fade to 0.5 over 1s
              tween: Tween<double>(begin: 1.0, end: 0.5),
              duration: const Duration(seconds: 3),
              curve: const Interval(0.67, 1.0, curve: Curves.easeOut),
              builder: (context, opacity, child) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Container(
                    color: colorScheme.surface.withOpacity(opacity),
                  ),
                );
              },
            ),
          ),

        // Welcome message during hint mode - two positioned sections with fade-in
        // Top section: Logo and Welcome title (stays fixed at top area)
        if (_isHintModeActive)
          Positioned(
            left: 24,
            right: 24,
            // Position logo section high up - about 1/3 from top
            top: MediaQuery.of(context).size.height * 0.15,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _welcomeFadeController,
                curve: Curves.easeOut,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ensemble logo - same as settings screen
                  Image.asset(
                    'assets/images/ensemble_icon_transparent.png',
                    width: MediaQuery.of(context).size.width * 0.5,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  // Welcome title
                  Text(
                    S.of(context)!.welcomeToEnsemble,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

        // Bottom section: Hint text and Skip button (only show once mini player is visible)
        if (_isHintModeActive && _miniPlayerHintsReady)
          Positioned(
            left: 24,
            right: 24,
            // Position so skip button is ~32px above mini player, matching skip-to-miniplayer gap
            bottom: BottomSpacing.navBarHeight + BottomSpacing.miniPlayerHeight + MediaQuery.of(context).padding.bottom + 32,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _welcomeFadeController,
                curve: Curves.easeOut,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hint text
                  Text(
                    S.of(context)!.welcomeMessage,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Skip button - same gap above as below to mini player
                  TextButton(
                    onPressed: _endHintMode,
                    child: Text(
                      S.of(context)!.skip,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
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
            showOnboardingHints: _isOnboardingReveal,
          ),

        // Global player overlay - renders ON TOP so cards slide behind it
        // Use Selector instead of Consumer to avoid rebuilds during animation
        Selector<MusicAssistantProvider, ({bool isConnected, bool hasPlayer, bool hasTrack})>(
          selector: (_, provider) => (
            isConnected: provider.isConnected,
            hasPlayer: provider.selectedPlayer != null,
            hasTrack: provider.currentTrack != null,
          ),
          builder: (context, state, child) {
            // Only show player if connected and has a selected player
            if (!state.isConnected || !state.hasPlayer) {
              return const SizedBox.shrink();
            }

            // Combine slide, bounce, and hint animations with ValueListenableBuilders
            // This prevents full widget tree rebuilds - only ExpandablePlayer updates
            return ValueListenableBuilder<double>(
              valueListenable: _bounceOffsetNotifier,
              builder: (context, bounceOffset, _) {
                return ValueListenableBuilder<double>(
                  valueListenable: _hintOpacityNotifier,
                  builder: (context, hintOpacity, _) {
                    return AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, _) {
                        return ExpandablePlayer(
                          key: globalPlayerKey,
                          slideOffset: _slideAnimation.value,
                          bounceOffset: bounceOffset,
                          onRevealPlayers: _showPlayerReveal,
                          isDeviceRevealVisible: _isRevealVisible,
                          isHintVisible: hintOpacity > 0,
                        );
                      },
                    );
                  },
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
