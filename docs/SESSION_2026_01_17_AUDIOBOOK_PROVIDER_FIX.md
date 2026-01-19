# Audiobook Provider Filtering Fix

## Date: January 17, 2026 (Continuation)

## Overview

This session focused on fixing provider filtering issues discovered after the initial provider filtering improvements:
1. Audiobooks were not responding to provider filter changes (browse API ignoring `providerInstanceIds`)
2. UI not updating instantly when toggling providers (missing `notifyListeners()` call)
3. Audiobook tabs not rebuilding on provider changes (using `context.read` instead of `Selector`)

---

## Problem Statement

After implementing capability-based provider filtering for the music library, two issues remained:

### Issue 1: Audiobooks Not Filtering During Sync

The bug report showed:
```
📊 Source tracking: 252 albums, 87 artists have provider info
📚 Total audiobooks from browse: 186
```

- Albums and artists had provider source tracking
- Audiobooks had NO provider source tracking (not listed)
- All 186 audiobooks were returned regardless of provider selection

### Issue 2: UI Not Updating Instantly

When toggling providers in the library menu:
- Music tabs weren't updating immediately
- Audiobooks required manual pull-to-refresh
- Changes only appeared after ~600ms (debounce timer)

---

## Root Cause Analysis

### Cause 1: Browse API Ignoring Provider Filter

In `lib/services/music_assistant_api.dart`, when ABS library filtering is enabled, the `getAudiobooks()` function uses the browse API but was **ignoring** the `providerInstanceIds` parameter:

```dart
// BEFORE: providerInstanceIds was ignored when using browse API
if (enabledLibraries != null && enabledLibraries.isNotEmpty) {
  return await _getAudiobooksFromBrowse(enabledLibraries, favoriteOnly: favoriteOnly);
}
```

### Cause 2: `notifyListeners()` Called Too Late

In `lib/providers/music_assistant_provider.dart`, the `toggleProviderEnabled()` function only called `notifyListeners()` **inside** the 600ms debounce timer:

```dart
// BEFORE: notifyListeners only called after 600ms debounce
_providerFilterDebounceTimer = Timer(const Duration(milliseconds: 600), () {
  forceLibrarySync();
  notifyListeners();  // Too late! UI should update immediately
});
```

### Cause 3: Audiobook Tabs Not Listening for Changes

The audiobook tabs used `context.read<MusicAssistantProvider>()` which doesn't trigger rebuilds when the provider changes:

```dart
// BEFORE: context.read doesn't listen for changes
Widget _buildBooksAuthorsTab(BuildContext context, S l10n) {
  final maProvider = context.read<MusicAssistantProvider>();
  final enabledProviders = maProvider.enabledProviderIds.toSet();
  // ... widget doesn't rebuild when enabledProviders changes
}
```

---

## Solutions

### Fix 1: Browse API Provider Filtering

**File:** `lib/services/music_assistant_api.dart` (lines 760-785)

Added logic to filter library paths by provider ID before browsing:

```dart
if (enabledLibraries != null && enabledLibraries.isNotEmpty) {
  _logger.log('📚 getAudiobooks: enabledLibraries=$enabledLibraries, providerInstanceIds=$providerInstanceIds');

  // If specific providers are requested, filter libraries to only matching providers
  // Library paths start with provider ID (e.g., "audiobookshelf--abc123://lb...")
  var librariesToBrowse = enabledLibraries;
  if (providerInstanceIds != null && providerInstanceIds.isNotEmpty) {
    librariesToBrowse = enabledLibraries.where((libPath) {
      // Extract provider ID from library path (everything before "://")
      final providerEnd = libPath.indexOf('://');
      if (providerEnd == -1) return false;
      final providerId = libPath.substring(0, providerEnd);
      return providerInstanceIds.contains(providerId);
    }).toList();

    // If no libraries match the requested providers, return empty
    if (librariesToBrowse.isEmpty) {
      return [];
    }
  }
  return await _getAudiobooksFromBrowse(librariesToBrowse, favoriteOnly: favoriteOnly);
}
```

### Fix 2: Immediate `notifyListeners()` Call

**File:** `lib/providers/music_assistant_provider.dart` (line 1149)

Moved `notifyListeners()` to fire immediately after `_enabledProviderIds` changes:

```dart
// Reload the enabled providers
final savedEnabled = await SettingsService.getEnabledMusicProviders();
_enabledProviderIds = savedEnabled ?? [];

// Notify listeners IMMEDIATELY so UI rebuilds with client-side filtering
// This enables instant UI updates using cached data with source tracking
notifyListeners();

// Cancel any pending debounce timer
_providerFilterDebounceTimer?.cancel();

// Start debounced sync - waits 600ms for user to finish toggling
// This refreshes the cache with new data from enabled providers
_providerFilterDebounceTimer = Timer(const Duration(milliseconds: 600), () {
  _logger.log('🔄 Debounce complete, starting library sync...');
  forceLibrarySync();
});
```

### Fix 3: Audiobook Tabs Use Selector

**File:** `lib/screens/new_library_screen.dart`

Wrapped `_buildBooksAuthorsTab` and `_buildAllBooksTab` in `Selector` to rebuild when `enabledProviderIds` changes:

```dart
Widget _buildBooksAuthorsTab(BuildContext context, S l10n) {
  // Use Selector to rebuild when enabledProviderIds changes
  return Selector<MusicAssistantProvider, Set<String>>(
    selector: (_, provider) => provider.enabledProviderIds.toSet(),
    builder: (context, enabledProviders, _) {
      final syncService = SyncService.instance;

      // Client-side filtering using SyncService source tracking for instant updates
      var audiobooks = syncService.hasSourceTracking && enabledProviders.isNotEmpty
          ? syncService.getAudiobooksFilteredByProviders(enabledProviders)
          : List<Audiobook>.from(_audiobooks);

      // ... rest of widget
    },
  );
}
```

### Fix 4: Enhanced Sync Logging

**File:** `lib/services/sync_service.dart`

Added audiobook counts to logging:

```dart
// Per-provider log (line 237)
_logger.log('  📥 Got ${albums.length} albums, ${artists.length} artists, ${audiobooks.length} audiobooks from $providerId');

// Source tracking summary (line 323)
_logger.log('📊 Source tracking: ${_albumSourceProviders.length} albums, ${_artistSourceProviders.length} artists, ${_audiobookSourceProviders.length} audiobooks have provider info');
```

---

## Data Flow After Fixes

```
┌─────────────────────────────────────────────────────────────────┐
│                    User Toggles Provider                         │
│                                                                  │
│   1. toggleProviderEnabled() called                             │
│   2. _enabledProviderIds updated                                │
│   3. notifyListeners() called IMMEDIATELY                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Selectors Detect Change                       │
│                                                                  │
│   Music tabs: Selector<..., (List, bool, Set<String>)>         │
│   Audiobook tabs: Selector<..., Set<String>>                    │
│                                                                  │
│   → All tabs rebuild immediately                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                Client-Side Filtering (Instant)                   │
│                                                                  │
│   syncService.getAlbumsFilteredByProviders(enabledProviders)    │
│   syncService.getArtistsFilteredByProviders(enabledProviders)   │
│   syncService.getAudiobooksFilteredByProviders(enabledProviders)│
│                                                                  │
│   → Uses EXISTING cache with source tracking                    │
│   → Instant UI update, no network required                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Background Sync (After 600ms Debounce)              │
│                                                                  │
│   - Refreshes cache with new data from enabled providers        │
│   - Updates source tracking                                      │
│   - Only needed when ENABLING providers (to fetch new data)     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Files Changed

| File | Changes |
|------|---------|
| `lib/services/music_assistant_api.dart` | Added provider filtering to browse API path in `getAudiobooks()`, added debug logging |
| `lib/services/sync_service.dart` | Added audiobook counts to per-provider and summary logs |
| `lib/providers/music_assistant_provider.dart` | Moved `notifyListeners()` to fire immediately on provider toggle |
| `lib/screens/new_library_screen.dart` | Wrapped audiobook tabs in `Selector` to rebuild on provider changes |

---

## Expected Behavior After Fixes

1. **Instant UI Updates:** When you toggle a provider, the library immediately updates using client-side filtering
2. **Audiobook Source Tracking:** Audiobooks now have provider source tracking (visible in logs)
3. **Audiobook Tab Rebuilds:** Both audiobook tabs (Authors and All Books) rebuild instantly on provider toggle
4. **Music Tab Consistency:** Music tabs continue to work as before, now with immediate rebuilds

---

## Testing Checklist

- [ ] Toggle a music provider, verify instant UI update (no 600ms delay)
- [ ] Toggle between different Spotify accounts, verify correct filtering
- [ ] Sync with ABS library filtering enabled
- [ ] Verify audiobooks appear in source tracking log
- [ ] Toggle ABS provider off in library menu
- [ ] Verify audiobooks list becomes empty immediately (no pull-to-refresh needed)
- [ ] Toggle ABS provider back on
- [ ] Verify audiobooks reappear after sync completes
- [ ] Test with multiple providers (Spotify audiobooks + ABS)

---

## Related Documentation

- `docs/SESSION_2026_01_17_PROVIDER_FILTERING.md` - Initial provider filtering implementation
- `docs/PER_PROVIDER_SYNC_IMPLEMENTATION.md` - Per-provider sync architecture

---

## Known Limitations

1. **Series Tab:** The Series tab still doesn't filter by provider. Series are fetched as `AudiobookSeries` objects without per-provider tracking.

2. **Mixed Provider Scenario:** If user has both Spotify audiobooks and ABS audiobooks, and ABS library filtering is enabled, Spotify audiobooks may not be fetched because the browse API path is taken. This is a pre-existing architectural limitation.

3. **Enabling Providers:** When ENABLING a previously disabled provider, the UI updates immediately but shows empty until the background sync completes (because the cache doesn't have that provider's data yet). This is expected behavior.
