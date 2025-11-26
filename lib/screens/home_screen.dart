import 'package:flutter/material.dart';
import '../widgets/mini_player.dart';
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
  int _selectedIndex = 0;
  final GlobalKey<SearchScreenState> _searchScreenKey = GlobalKey<SearchScreenState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        setState(() {
          _selectedIndex = 0;
        });
      },
      child: Scaffold(
        backgroundColor: colorScheme.background,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            const NewHomeScreen(),
            const NewLibraryScreen(),
            // Wrap SearchScreen in ExcludeFocus to prevent it from grabbing focus when hidden
            ExcludeFocus(
              excluding: _selectedIndex != 2,
              child: SearchScreen(
                key: _searchScreenKey,
                isSearchActive: _selectedIndex == 2,
              ),
            ),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini player
            const MiniPlayer(),

            // Bottom navigation bar
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  if (_selectedIndex == index) return;

                  // Always dismiss keyboard when switching tabs
                  FocusScope.of(context).unfocus();

                  setState(() {
                    _selectedIndex = index;
                  });

                  // Focus search field if Search tab is selected
                  if (index == 2) {
                    // Small delay to ensure the widget is visible before requesting focus
                    Future.delayed(const Duration(milliseconds: 300), () {
                      _searchScreenKey.currentState?.focusSearchField();
                    });
                  }
                },
                backgroundColor: Colors.transparent,
                selectedItemColor: colorScheme.primary,
                unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.library_music_outlined),
                    activeIcon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.search_rounded),
                    activeIcon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings_rounded),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
