import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyWebSocketPort = 'websocket_port';
  static const String _keyDefaultServer = 'ma.serverscloud.org';

  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? _keyDefaultServer;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, url);
  }

  // Get custom WebSocket port (null means use default logic)
  static Future<int?> getWebSocketPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyWebSocketPort);
  }

  // Set custom WebSocket port (null to use default logic)
  static Future<void> setWebSocketPort(int? port) async {
    final prefs = await SharedPreferences.getInstance();
    if (port == null) {
      await prefs.remove(_keyWebSocketPort);
    } else {
      await prefs.setInt(_keyWebSocketPort, port);
    }
  }

  static Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
