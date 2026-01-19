# Per-Provider Sync Implementation

## Date: January 17, 2026

## Overview

This document details the implementation of per-provider sync with source tracking, enabling instant client-side filtering that properly differentiates between multiple accounts of the same provider type (e.g., two different Spotify accounts).

## Problem Statement

### The Core Issue

When a user has multiple accounts of the same provider type (e.g., two Spotify accounts: "Chris Laycock" and "Bababagoly"), the existing provider filter couldn't differentiate between them.

**Why?** Music Assistant's `provider_mappings` field on media items shows which providers **CAN PLAY** an item, not which provider **ADDED** it. When both Spotify accounts can play the same artist, both appear in `provider_mappings`, making client-side filtering impossible.

### Previous Approach (Failed)

The initial implementation tried to filter client-side using `provider_mappings`:

```dart
bool isItemAllowedByProviderFilter(MediaItem item) {
  final mappings = item.providerMappings;
  for (final mapping in mappings) {
    if (_providerFilter.contains(mapping.providerInstance)) {
      return true;
    }
  }
  return false;
}
```

**Result:** Both Spotify accounts showed the same items because `provider_mappings` contained both account IDs for shared content.

### Race Condition Issue

Additionally, when rapidly toggling providers, a race condition occurred:
1. User toggles Provider A off
2. Sync starts for remaining providers
3. User toggles Provider B off before sync completes
4. First sync completes with wrong filter state
5. UI shows incorrect results

## Solution: Per-Provider Sync with Source Tracking

### Concept

Instead of relying on `provider_mappings`, we:
1. **Sync each provider separately** using the MA API's `provider` parameter
2. **Tag each item** with which provider instance(s) returned it
3. **Store source tracking** in the local database
4. **Filter client-side** using the source tracking data (instant)
5. **Background sync** keeps data fresh without blocking UI

### Why This Works

When we call the MA API with `provider: ["spotify--RKnr3jKx"]`, the server returns **only items from that specific account's library**. By syncing each provider separately and remembering which provider returned each item, we can accurately filter.

## Implementation Details

### 1. Database Schema Update

**File:** `lib/database/database.dart`

Added `sourceProviders` column to `LibraryCache` table:

```dart
class LibraryCache extends Table {
  // ... existing columns ...

  /// Provider instance IDs that provided this item (JSON array)
  /// Used for client-side filtering by source provider
  TextColumn get sourceProviders => text().withDefault(const Constant('[]'))();
}
```

**Schema version:** 5 → 6

**Migration:**
```dart
if (from < 6) {
  await customStatement(
    "ALTER TABLE library_cache ADD COLUMN source_providers TEXT NOT NULL DEFAULT '[]'"
  );
}
```

### 2. Database Service Updates

**File:** `lib/services/database_service.dart`

Added `sourceProvider` parameter to `cacheItem()`:

```dart
Future<void> cacheItem<T>({
  required String itemType,
  required String itemId,
  required Map<String, dynamic> data,
  String? sourceProvider,  // NEW: tracks which provider this item came from
})
```

Added new method to retrieve items with source tracking:

```dart
Future<List<(Map<String, dynamic>, List<String>)>> getCachedItemsWithProviders(String itemType)
```

Returns tuples of `(itemData, sourceProviderIds)`.

### 3. SyncService Rewrite

**File:** `lib/services/sync_service.dart`

#### New Fields

```dart
// Source provider tracking for client-side filtering
Map<String, List<String>> _albumSourceProviders = {};
Map<String, List<String>> _artistSourceProviders = {};
Map<String, List<String>> _audiobookSourceProviders = {};
Map<String, List<String>> _playlistSourceProviders = {};
```

#### Per-Provider Sync Logic

```dart
Future<void> syncFromApi(MusicAssistantAPI api, {
  bool force = false,
  List<String>? providerInstanceIds,
}) async {
  // If specific providers are requested, sync each separately
  if (providerInstanceIds != null && providerInstanceIds.isNotEmpty) {
    for (final providerId in providerInstanceIds) {
      // Fetch from this specific provider
      final results = await Future.wait([
        api.getAlbums(limit: 1000, providerInstanceIds: [providerId]),
        api.getArtists(limit: 1000, providerInstanceIds: [providerId]),
        // ... etc
      ]);

      // Track source provider for each item
      for (final album in albums) {
        albumMap[album.itemId] = album;
        _albumSourceProviders.putIfAbsent(album.itemId, () => []);
        if (!_albumSourceProviders[album.itemId]!.contains(providerId)) {
          _albumSourceProviders[album.itemId]!.add(providerId);
        }
      }
    }
  }
}
```

#### Client-Side Filtering Methods

```dart
/// Filter albums by source provider (instant, no network)
List<Album> getAlbumsFilteredByProviders(Set<String> enabledProviderIds) {
  if (enabledProviderIds.isEmpty || _albumSourceProviders.isEmpty) {
    return _cachedAlbums;
  }
  return _cachedAlbums.where((album) {
    final sources = _albumSourceProviders[album.itemId];
    if (sources == null || sources.isEmpty) return true; // No tracking = show
    return sources.any((s) => enabledProviderIds.contains(s));
  }).toList();
}

// Similar methods for artists, audiobooks, playlists
```

### 4. Library Screen Updates

**File:** `lib/screens/new_library_screen.dart`

#### Hybrid Provider Toggle Handler

```dart
void _handleProviderToggle(String providerId, bool enabled) {
  final maProvider = context.read<MusicAssistantProvider>();

  // Instant UI update via global provider toggle
  maProvider.toggleProviderEnabled(providerId, enabled);
  setState(() {}); // Rebuild with client-side filtering

  // Background sync after 1.5s debounce
  _providerFilterDebounce?.cancel();
  _providerFilterDebounce = Timer(const Duration(milliseconds: 1500), () async {
    if (mounted) {
      await maProvider.forceLibrarySync();
      if (mounted) setState(() {});
    }
  });
}
```

#### Updated Tab Builders

Artists tab now uses source tracking:

```dart
Widget _buildArtistsTab(BuildContext context, S l10n) {
  return Selector<MusicAssistantProvider, (List<Artist>, bool, Set<String>)>(
    selector: (_, provider) => (
      provider.artists,
      provider.isLoading,
      provider.enabledProviderIds.toSet()
    ),
    builder: (context, data, _) {
      final (allArtists, isLoading, enabledProviders) = data;

      // Client-side filtering using SyncService source tracking
      final syncService = SyncService.instance;
      final filteredArtists = syncService.hasSourceTracking && enabledProviders.isNotEmpty
          ? syncService.getArtistsFilteredByProviders(enabledProviders)
          : allArtists;

      // ... rest of build
    },
  );
}
```

Similar updates for albums, playlists, and audiobooks tabs.

### 5. Provider Instance Model

**File:** `lib/models/provider_instance.dart` (new file)

```dart
class ProviderInstance {
  final String instanceId;  // e.g., "spotify--abc123"
  final String domain;      // e.g., "spotify"
  final String name;        // e.g., "Spotify (John's Account)"
  final bool available;

  /// Known music provider domains
  static const Set<String> musicProviderDomains = {
    'spotify', 'tidal', 'qobuz', 'deezer', 'ytmusic', 'soundcloud',
    'apple_music', 'amazon_music', 'plex', 'subsonic', 'opensubsonic',
    'jellyfin', 'emby', 'navidrome', 'audiobookshelf', 'filesystem',
    'tunein', 'radiobrowser', 'snapcast', 'fully_kiosk',
  };

  bool get isMusicProvider => musicProviderDomains.contains(domain);
}
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     User Toggles Provider                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. MusicAssistantProvider.toggleProviderEnabled()              │
│     - Updates enabledProviderIds                                │
│     - Triggers setState() for instant UI update                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. UI Rebuilds Immediately                                     │
│     - Selector detects enabledProviderIds change                │
│     - Calls SyncService.getArtistsFilteredByProviders()         │
│     - Filters using source tracking (instant, no network)       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Background Sync (after 1.5s debounce)                       │
│     - forceLibrarySync() called                                 │
│     - Syncs each enabled provider separately                    │
│     - Updates source tracking in database                       │
│     - UI refreshes with fresh data                              │
└─────────────────────────────────────────────────────────────────┘
```

## Files Changed

| File | Changes |
|------|---------|
| `lib/database/database.dart` | Added `sourceProviders` column, schema v6, migration |
| `lib/database/database.g.dart` | Auto-generated from schema changes |
| `lib/services/database_service.dart` | Added `sourceProvider` param, `getCachedItemsWithProviders()` |
| `lib/services/sync_service.dart` | Per-provider sync, source tracking maps, filtering methods |
| `lib/screens/new_library_screen.dart` | Hybrid toggle handler, updated tab builders |
| `lib/models/provider_instance.dart` | New model for provider instances |

## Testing Checklist

- [ ] Fresh install: First sync should populate source tracking
- [ ] Toggle single provider: UI updates instantly
- [ ] Toggle multiple providers rapidly: Debounce prevents race conditions
- [ ] Two Spotify accounts: Toggling one only shows that account's items
- [ ] Mixed providers: Toggling Spotify doesn't affect Audiobookshelf items
- [ ] Legacy cache: Items without source tracking show regardless of filter
- [ ] Pull to refresh: Refreshes source tracking data

## Known Limitations

1. **First sync required:** Source tracking only works after at least one sync with providers enabled
2. **Network cost:** Per-provider sync makes N API calls (one per provider) vs. 1 call for all providers
3. **Items in multiple accounts:** If the same item exists in both Spotify accounts, it will show when either is enabled

## Future Improvements

1. **Incremental sync:** Only sync changed items instead of full library
2. **Provider-specific cache age:** Different sync intervals per provider
3. **Offline source tracking:** Persist source tracking independently of full cache

## Branch

All changes are on the `feature/per-provider-sync` branch.

```bash
git checkout feature/per-provider-sync
```

## Commit

```
feat: Add per-provider sync with source tracking for instant filtering

- Add sourceProviders column to database schema (v6) for tracking which
  provider instance each item came from
- Update SyncService to sync each enabled provider separately and tag
  items with their source provider
- Add client-side filtering methods that use source tracking to properly
  differentiate between multiple accounts of the same provider type
- Update library UI to use instant client-side filtering with background
  sync for data freshness
```
