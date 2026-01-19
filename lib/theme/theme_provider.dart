import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import 'palette_helper.dart';
import 'package:ensemble/services/image_cache_service.dart';

final _themeLogger = DebugLogger();

/// Global function to update adaptive colors from an image URL
/// This can be called from anywhere in the app (e.g., when tapping an album/artist)
/// Sets isOnDetailScreen=true so nav bar will also use adaptive colors
Future<void> updateAdaptiveColorsFromImage(BuildContext context, String? imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return;

  try {
    final colorSchemes = await PaletteHelper.extractColorSchemes(CachedNetworkImageProvider(imageUrl, cacheManager: AuthenticatedCacheManager.instance));
    if (colorSchemes != null && context.mounted) {
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2, isFromDetailScreen: true);
    }
  } catch (e) {
    // Silently fail - colors will update when track plays
    _themeLogger.debug('Failed to extract colors on tap: $e', context: 'Theme');
  }
}

/// Clear adaptive colors and return to default theme colors
/// Call this when navigating back from album/artist detail screens
void clearAdaptiveColorsOnBack(BuildContext context) {
  final themeProvider = context.read<ThemeProvider>();
  themeProvider.clearAdaptiveColors();
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _useMaterialTheme = false;
  bool _adaptiveTheme = true;
  Color _customColor = const Color(0xFF604CEC);

  // Adaptive colors extracted from current album art
  AdaptiveColors? _adaptiveColors;
  ColorScheme? _adaptiveLightScheme;
  ColorScheme? _adaptiveDarkScheme;

  // Track if we're on a detail screen (vs just player-extracted colors)
  // When true, nav bar should use adaptive colors even when player is collapsed
  bool _isOnDetailScreen = false;

  ThemeProvider() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  bool get useMaterialTheme => _useMaterialTheme;
  bool get adaptiveTheme => _adaptiveTheme;
  Color get customColor => _customColor;

  // Adaptive color getters
  AdaptiveColors? get adaptiveColors => _adaptiveColors;
  ColorScheme? get adaptiveLightScheme => _adaptiveLightScheme;
  ColorScheme? get adaptiveDarkScheme => _adaptiveDarkScheme;
  bool get isOnDetailScreen => _isOnDetailScreen;

  /// Get the current adaptive primary color (for bottom nav highlight, etc.)
  Color get adaptivePrimaryColor => _adaptiveColors?.primary ?? _customColor;

  /// Get the current adaptive surface color (for bottom nav background, etc.)
  /// Returns a subtle tinted surface based on the adaptive colors
  /// NOTE: Prefer getAdaptiveSurfaceColorFor() which respects light/dark mode
  Color? get adaptiveSurfaceColor {
    if (_adaptiveColors == null) return null;
    // Use the miniPlayer color but darkened for a subtle tinted background
    final hsl = HSLColor.fromColor(_adaptiveColors!.miniPlayer);
    return hsl.withLightness((hsl.lightness * 0.4).clamp(0.08, 0.15)).toColor();
  }

  /// Get adaptive surface color for the given brightness (light/dark mode aware)
  /// Returns the same color as the expanded player background (scheme.surface)
  Color? getAdaptiveSurfaceColorFor(Brightness brightness) {
    // Pick scheme based on current mode
    final scheme = brightness == Brightness.dark
        ? _adaptiveDarkScheme
        : _adaptiveLightScheme;

    if (scheme == null) return null;

    // Use surface - same as expanded player background (line 1234 in expandable_player.dart)
    return scheme.surface;
  }

  Future<void> _loadSettings() async {
    final themeModeString = await SettingsService.getThemeMode();
    _themeMode = _parseThemeMode(themeModeString);

    _useMaterialTheme = await SettingsService.getUseMaterialTheme();
    _adaptiveTheme = await SettingsService.getAdaptiveTheme();

    final colorString = await SettingsService.getCustomColor();
    if (colorString != null) {
      _customColor = _parseColor(colorString);
    }

    notifyListeners();
  }

  ThemeMode _parseThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Color _parseColor(String colorString) {
    try {
      // Remove # if present
      final hex = colorString.replaceAll('#', '');
      // Add FF for alpha if not present
      final hexWithAlpha = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(hexWithAlpha, radix: 16));
    } catch (e) {
      return const Color(0xFF604CEC); // Default color
    }
  }

  String _colorToString(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.saveThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setUseMaterialTheme(bool enabled) async {
    _useMaterialTheme = enabled;
    await SettingsService.saveUseMaterialTheme(enabled);
    notifyListeners();
  }

  Future<void> setAdaptiveTheme(bool enabled) async {
    _adaptiveTheme = enabled;
    await SettingsService.saveAdaptiveTheme(enabled);
    notifyListeners();
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await SettingsService.saveCustomColor(_colorToString(color));
    notifyListeners();
  }

  /// Update adaptive colors from album art
  /// [isFromDetailScreen] - if true, this is from navigating to a detail screen
  /// and the nav bar should use adaptive colors even when player is collapsed
  void updateAdaptiveColors(ColorScheme? lightScheme, ColorScheme? darkScheme, {bool isFromDetailScreen = false}) {
    _adaptiveLightScheme = lightScheme;
    _adaptiveDarkScheme = darkScheme;

    // Only set detail screen flag if explicitly from a detail screen navigation
    // Player-extracted colors should NOT set this flag
    if (isFromDetailScreen) {
      _isOnDetailScreen = true;
    }

    // Extract AdaptiveColors from the schemes
    if (darkScheme != null) {
      _adaptiveColors = AdaptiveColors(
        primary: darkScheme.primary,
        surface: darkScheme.surface,
        onSurface: darkScheme.onSurface,
        miniPlayer: darkScheme.primaryContainer,
      );
    } else {
      _adaptiveColors = null;
    }

    notifyListeners();
  }

  /// Clear adaptive colors (when navigating back from detail screen or no track playing)
  void clearAdaptiveColors() {
    _adaptiveColors = null;
    _adaptiveLightScheme = null;
    _adaptiveDarkScheme = null;
    _isOnDetailScreen = false;
    notifyListeners();
  }
}
