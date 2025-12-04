import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/global_player_overlay.dart';
import 'new_home_screen.dart';
import 'new_library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    // Register search focus callback with navigation provider
    navigationProvider.onSearchTabSelected = () {
      _searchScreenKey.currentState?.requestFocus();
    };
  }

  @override
  void dispose() {
    // Clean up callback
    navigationProvider.onSearchTabSelected = null;
    super.dispose();
  }

  void _showExitSnackBar() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Press back again to minimize'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: navigationProvider,
      builder: (context, _) {
        final selectedIndex = navigationProvider.selectedIndex;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            // If global player is expanded, collapse it first
            if (GlobalPlayerOverlay.isPlayerExpanded) {
              GlobalPlayerOverlay.collapsePlayer();
              return;
            }

            // If not on home tab, navigate to home
            if (selectedIndex != 0) {
              // If leaving Settings, show player again
              if (selectedIndex == 3) {
                GlobalPlayerOverlay.showPlayer();
              }
              navigationProvider.setSelectedIndex(0);
              return;
            }

            // On home tab - check for double press to minimize
            final now = DateTime.now();
            if (_lastBackPress != null &&
                now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
              // Double press detected - minimize app (move to background)
              // This keeps the app running and connection alive
              SystemNavigator.pop();
            } else {
              // First press, show message
              _lastBackPress = now;
              _showExitSnackBar();
            }
          },
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            // No bottomNavigationBar here - it's now in GlobalPlayerOverlay
            body: Stack(
              children: [
                // Home and Library use IndexedStack for state preservation
                Offstage(
                  offstage: selectedIndex > 1,
                  child: IndexedStack(
                    index: selectedIndex.clamp(0, 1),
                    children: const [
                      NewHomeScreen(),
                      NewLibraryScreen(),
                    ],
                  ),
                ),
                // Search and Settings are conditionally rendered (removed from tree when not visible)
                if (selectedIndex == 2)
                  SearchScreen(key: _searchScreenKey),
                if (selectedIndex == 3)
                  const SettingsScreen(),
              ],
            ),
          ),
        );
      },
    );
  }
}
