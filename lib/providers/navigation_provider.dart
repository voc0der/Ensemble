import 'package:flutter/material.dart';

/// Global navigation state for bottom navigation bar
class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 0;

  /// Global navigator key for pushing routes from anywhere
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Callback to focus search when search tab is selected
  VoidCallback? onSearchTabSelected;

  int get selectedIndex => _selectedIndex;

  void setSelectedIndex(int index) {
    final previousIndex = _selectedIndex;
    if (previousIndex != index) {
      _selectedIndex = index;
      notifyListeners();

      // Trigger search focus callback when switching to search tab
      if (index == 2 && onSearchTabSelected != null) {
        // Use post-frame callback to ensure SearchScreen is built first
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onSearchTabSelected?.call();
        });
      }
    }
  }

  /// Pop all routes and return to the home tab
  void popToHome() {
    // Pop all routes above the root
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setSelectedIndex(0);
  }
}

/// Global instance for easy access
final navigationProvider = NavigationProvider();
