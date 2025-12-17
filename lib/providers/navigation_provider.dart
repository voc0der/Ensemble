import 'package:flutter/material.dart';

/// Media type for the library (Music, Books, Podcasts)
enum LibraryMediaType { music, books, podcasts }

/// Global navigation state for bottom navigation bar
class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 0;
  LibraryMediaType _libraryMediaType = LibraryMediaType.music;

  /// Global navigator key for pushing routes from anywhere
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Callback to focus search when search tab is selected
  VoidCallback? onSearchTabSelected;

  int get selectedIndex => _selectedIndex;
  LibraryMediaType get libraryMediaType => _libraryMediaType;

  void setLibraryMediaType(LibraryMediaType type) {
    if (_libraryMediaType != type) {
      _libraryMediaType = type;
      notifyListeners();
    }
  }

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
