# Provider Filtering Improvements

## Date: January 17, 2026

## Overview

This session focused on improving the provider filtering system across the app, building on the per-provider sync implementation. Key improvements include a cleaner capability-based architecture, fixing filter visibility bugs, and extending filtering to the audiobooks library.

---

## Changes Made

### 1. Provider Capability Mapping

**File:** `lib/models/provider_instance.dart`

Replaced the clunky item-count-based filtering with a static capability map that defines what content types each provider domain supports.

```dart
static const Map<String, Set<String>> providerCapabilities = {
  // Music streaming services
  'spotify': {'artists', 'albums', 'tracks', 'playlists', 'audiobooks'},
  'tidal': {'artists', 'albums', 'tracks', 'playlists'},
  'qobuz': {'artists', 'albums', 'tracks', 'playlists'},
  'deezer': {'artists', 'albums', 'tracks', 'playlists'},
  'ytmusic': {'artists', 'albums', 'tracks', 'playlists'},
  'soundcloud': {'artists', 'albums', 'tracks', 'playlists'},
  'apple_music': {'artists', 'albums', 'tracks', 'playlists'},
  'amazon_music': {'artists', 'albums', 'tracks', 'playlists'},

  // Self-hosted media servers (can have music and audiobooks)
  'plex': {'artists', 'albums', 'tracks', 'playlists', 'audiobooks'},
  'jellyfin': {'artists', 'albums', 'tracks', 'playlists', 'audiobooks'},
  'emby': {'artists', 'albums', 'tracks', 'playlists', 'audiobooks'},

  // Music-only servers
  'subsonic': {'artists', 'albums', 'tracks', 'playlists'},
  'opensubsonic': {'artists', 'albums', 'tracks', 'playlists'},
  'navidrome': {'artists', 'albums', 'tracks', 'playlists'},
  'filesystem': {'artists', 'albums', 'tracks', 'playlists'},

  // Audiobook-only providers
  'audiobookshelf': {'audiobooks'},

  // Radio providers
  'tunein': {'radio'},
  'radiobrowser': {'radio'},

  // Player/system providers (no library content)
  'snapcast': <String>{},
  'fully_kiosk': <String>{},
};
```

**Added helper methods:**
```dart
Set<String> get supportedContentTypes => providerCapabilities[domain] ?? <String>{};
bool supportsContentType(String category) => supportedContentTypes.contains(category);
```

**Benefits:**
- Radio providers never show in Artists tab (by design, not by count)
- Works immediately, even with empty libraries
- Disabled providers still show in menu (if they support the content type)
- Clean separation of concerns

---

### 2. Updated Provider Filtering in MusicAssistantProvider

**File:** `lib/providers/music_assistant_provider.dart`

Updated `getRelevantProvidersForCategory()` to filter by capability:

```dart
List<(ProviderInstance, int)> getRelevantProvidersForCategory(String category) {
  // ... get counts ...

  final result = <(ProviderInstance, int)>[];
  for (final provider in _availableMusicProviders) {
    // Only include providers that support this content type
    if (provider.supportsContentType(category)) {
      final count = counts[provider.instanceId] ?? 0;
      result.add((provider, count));
    }
  }
  // ...
}
```

---

### 3. Simplified Library Menu Provider Filter

**File:** `lib/screens/new_library_screen.dart`

Simplified the options menu overlay to show all providers that support the current category:

**Before (clunky):**
```dart
if (widget.relevantProviders.where((p) {
  final hasItems = p.$2 > 0;
  final isDisabledByUser = widget.enabledProviderIds.isNotEmpty &&
      !widget.enabledProviderIds.contains(p.$1.instanceId);
  return hasItems || isDisabledByUser;
}).length > 1) ...[
```

**After (clean):**
```dart
// relevantProviders is pre-filtered by capability
if (widget.relevantProviders.length > 1) ...[
  // Show all providers that support this category
  ...widget.relevantProviders.map((providerData) {
```

---

### 4. Removed Provider Toggles from Settings Screen

**File:** `lib/screens/settings_screen.dart`

Removed the "Music Providers" section entirely since provider filtering is now handled in the library menu:

- Removed `_providerEnabled` state variable
- Removed provider loading code from `_loadSettings()`
- Removed the entire Music Providers UI section (~100 lines)

**Rationale:** Single source of truth - provider toggles now only appear in the library menu where they're contextually relevant.

---

### 5. Fixed Audiobooks Library Provider Filtering

**File:** `lib/screens/new_library_screen.dart`

The audiobooks tabs were not filtering by provider - they loaded data once and displayed it without responding to provider changes.

**Fixed `_buildBooksAuthorsTab()`:**
```dart
final syncService = SyncService.instance;
final enabledProviders = maProvider.enabledProviderIds.toSet();

// Client-side filtering using SyncService source tracking
var audiobooks = syncService.hasSourceTracking && enabledProviders.isNotEmpty
    ? syncService.getAudiobooksFilteredByProviders(enabledProviders)
    : List<Audiobook>.from(_audiobooks);

// Filter by favorites if enabled
if (_showFavoritesOnly) {
  audiobooks = audiobooks.where((a) => a.favorite == true).toList();
}

// Group filtered audiobooks by author (dynamic, not cached)
final groupedByAuthor = <String, List<Audiobook>>{};
for (final book in audiobooks) {
  final authorName = book.authorsString;
  groupedByAuthor.putIfAbsent(authorName, () => []).add(book);
}
```

**Fixed `_buildAllBooksTab()`:**
- Same provider filtering pattern
- Dynamic sorting after filtering
- Updated PageStorageKey to include provider count for proper rebuild

---

## Bug Fixes

### Provider Filter Menu Disappearing

**Problem:** When providers were deselected, the background sync would clear the cache and only fetch data for enabled providers. Disabled providers then had 0 items, and the menu required `> 1 providers WITH items` to show. The entire Providers section would disappear.

**Solution:** Changed to capability-based filtering. The menu now shows all providers that support the category, regardless of item count.

### Audiobooks Not Filtering by Provider

**Problem:** Audiobooks tabs loaded data once into `_audiobooks` and displayed it without provider filtering. Toggling providers in the menu had no effect.

**Solution:** Added inline provider filtering during build (same pattern as music tabs).

---

## Files Changed

| File | Changes |
|------|---------|
| `lib/models/provider_instance.dart` | Added `providerCapabilities` map and helper methods |
| `lib/providers/music_assistant_provider.dart` | Updated `getRelevantProvidersForCategory()` to filter by capability |
| `lib/screens/new_library_screen.dart` | Simplified menu filter logic, added audiobook provider filtering |
| `lib/screens/settings_screen.dart` | Removed Music Providers section |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Provider Capability Map                       │
│         (ProviderInstance.providerCapabilities)                  │
│                                                                  │
│   spotify → {artists, albums, tracks, playlists, audiobooks}    │
│   audiobookshelf → {audiobooks}                                 │
│   tunein → {radio}                                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│            getRelevantProvidersForCategory(category)             │
│                                                                  │
│   - Filters _availableMusicProviders by capability              │
│   - Returns only providers that support the category            │
│   - Includes item counts for display                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Library Menu (Options)                        │
│                                                                  │
│   - Shows providers section if > 1 providers support category   │
│   - All relevant providers shown (can toggle on/off)            │
│   - Instant UI update via setState()                            │
│   - Background sync after 1.5s debounce                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Tab Build Methods                              │
│                                                                  │
│   - Get enabledProviderIds from MusicAssistantProvider          │
│   - Filter data using SyncService source tracking               │
│   - Display filtered results                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Known Limitations

1. **Series Tab:** The Series tab in audiobooks doesn't filter by provider yet. Series are fetched separately as `AudiobookSeries` objects and don't have the same source tracking as individual audiobooks.

2. **First Sync Required:** Source tracking only works after at least one sync with providers enabled.

---

## Testing Checklist

- [x] Music tabs filter by provider correctly
- [x] Provider menu shows only relevant providers per category
- [x] Radio providers don't appear in Artists/Albums tabs
- [x] Spotify appears in Audiobooks tab (has audiobooks)
- [x] Audiobooks Authors tab filters by provider
- [x] Audiobooks All Books tab filters by provider
- [ ] Audiobooks Series tab filters by provider (not implemented)
- [x] Disabled providers can be re-enabled from menu
- [x] Settings screen no longer has provider toggles

---

## Related Documentation

- `docs/PER_PROVIDER_SYNC_IMPLEMENTATION.md` - Original per-provider sync implementation
