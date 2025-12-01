import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'debug_logger.dart';

/// Service to generate unique per-installation player IDs
/// Uses random UUID to ensure each installation has a unique ID
/// This prevents the critical bug where multiple devices of the same model
/// would share the same player ID and trigger playback on all devices
class DeviceIdService {
  static const String _keyLocalPlayerId = 'local_player_id';
  static const String _legacyKeyBuiltinPlayerId = 'builtin_player_id';
  static final _logger = DebugLogger();
  static const _uuid = Uuid();

  /// Get or generate a unique player ID for this installation
  /// ID is generated once and persisted across app restarts
  /// Format: ensemble_<uuid>
  static Future<String> getOrCreateDevicePlayerId() async {
    final prefs = await SharedPreferences.getInstance();

    // Check primary storage first
    final existingId = prefs.getString(_keyLocalPlayerId);
    if (existingId != null && existingId.startsWith('ensemble_')) {
      _logger.log('Using existing player ID: $existingId');
      return existingId;
    }

    // Check legacy storage (for backward compatibility)
    final legacyId = prefs.getString(_legacyKeyBuiltinPlayerId);
    if (legacyId != null && legacyId.startsWith('ensemble_')) {
      _logger.log('Migrating from legacy storage: $legacyId');
      await prefs.setString(_keyLocalPlayerId, legacyId);
      return legacyId;
    }

    // Generate new ID
    final playerId = 'ensemble_${_uuid.v4()}';
    await _savePlayerId(prefs, playerId);
    _logger.log('Generated new player ID: $playerId');
    return playerId;
  }

  /// Adopt an existing player ID (used when claiming a ghost player)
  static Future<void> adoptPlayerId(String playerId) async {
    final prefs = await SharedPreferences.getInstance();
    await _savePlayerId(prefs, playerId);
    _logger.log('Adopted player ID: $playerId');
  }

  /// Check if this is a fresh installation (no player ID stored yet)
  static Future<bool> isFreshInstallation() async {
    final prefs = await SharedPreferences.getInstance();
    final hasId = prefs.getString(_keyLocalPlayerId) != null ||
                  prefs.getString(_legacyKeyBuiltinPlayerId) != null;
    return !hasId;
  }

  /// Save player ID to both storage keys for compatibility
  static Future<void> _savePlayerId(SharedPreferences prefs, String playerId) async {
    await prefs.setString(_keyLocalPlayerId, playerId);
    await prefs.setString(_legacyKeyBuiltinPlayerId, playerId);
  }
}
