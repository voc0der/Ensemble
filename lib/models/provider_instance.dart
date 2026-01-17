/// Represents a music provider instance from Music Assistant.
///
/// Each provider (like Spotify, Tidal) can have multiple instances
/// (e.g., two different Spotify accounts). This class represents
/// a single provider instance with its unique ID.
class ProviderInstance {
  /// Unique identifier for this provider instance (e.g., "spotify--abc123")
  final String instanceId;

  /// The provider domain/type (e.g., "spotify", "tidal", "qobuz")
  final String domain;

  /// Display name for this instance (e.g., "Spotify (John's Account)")
  final String name;

  /// Whether this provider is currently available/connected
  final bool available;

  ProviderInstance({
    required this.instanceId,
    required this.domain,
    required this.name,
    required this.available,
  });

  /// Known music provider domains that provide library content
  static const Set<String> musicProviderDomains = {
    // Streaming services
    'spotify',
    'tidal',
    'qobuz',
    'deezer',
    'ytmusic',
    'soundcloud',
    'apple_music',
    'amazon_music',
    // Self-hosted / local
    'plex',
    'subsonic',
    'opensubsonic',
    'jellyfin',
    'emby',
    'navidrome',
    'audiobookshelf',
    'filesystem',
    // Other
    'tunein',
    'radiobrowser',
    'snapcast',
    'fully_kiosk',
  };

  /// Whether this is a music provider (vs. player provider, metadata provider, etc.)
  bool get isMusicProvider => musicProviderDomains.contains(domain);

  factory ProviderInstance.fromJson(Map<String, dynamic> json) {
    return ProviderInstance(
      instanceId: json['instance_id'] as String? ?? '',
      domain: json['domain'] as String? ?? json['type'] as String? ?? '',
      name: json['name'] as String? ?? json['instance_id'] as String? ?? 'Unknown',
      available: json['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instance_id': instanceId,
      'domain': domain,
      'name': name,
      'available': available,
    };
  }

  @override
  String toString() => 'ProviderInstance($instanceId: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderInstance &&
          runtimeType == other.runtimeType &&
          instanceId == other.instanceId;

  @override
  int get hashCode => instanceId.hashCode;
}
