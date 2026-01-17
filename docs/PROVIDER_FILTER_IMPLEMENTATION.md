# Provider Filter Implementation Notes

## Overview

This document captures the context and learnings from an attempted implementation of provider filtering in the Ensemble app. The goal was to allow users to filter their library to show only items from a specific music provider (e.g., only one Spotify account when multiple are configured).

## The Problem

Users with multiple music provider accounts (e.g., two Spotify accounts: one personal, one family) want to filter their library view to show only items from one specific account. The Music Assistant (MA) web UI successfully implements this feature.

## What Works vs What Failed

### Works: Different Provider Types
Filtering between different provider types (e.g., Spotify vs Tidal vs Plex) works correctly. Each provider type has distinct `provider_mappings` entries.

### Failed: Multiple Accounts of Same Provider
Filtering between multiple Spotify accounts (e.g., `spotify--abc123` vs `spotify--xyz789`) does NOT work correctly. The same library items appear regardless of which Spotify account is selected.

## Root Cause Analysis

### The provider_mappings Problem

MA's `provider_mappings` field on media items does NOT indicate "which account ADDED this item to the library." Instead, it indicates "which providers CAN PLAY this item."

Example: An artist "Ari Mason" that exists ONLY in User A's Spotify library will show provider_mappings containing BOTH Spotify accounts:
```json
{
  "provider_mappings": [
    {"provider_instance": "spotify--userA_id", "item_id": "..."},
    {"provider_instance": "spotify--userB_id", "item_id": "..."}
  ]
}
```

This happens because:
1. MA's internal database stores that the artist exists
2. MA knows both Spotify accounts CAN play this artist (Spotify has the content)
3. MA doesn't track WHICH account originally added the item to the library

### MA Web UI Behavior

The MA web UI's provider filter works differently - it appears to use server-side filtering via the `provider` parameter on library_items API calls. When you select a single provider in MA settings, the API returns only items from that provider's library.

## API Investigation

### Server-Side Filtering Parameter

The MA server's `library_items` method accepts a `provider` parameter:
- Parameter name: `provider` (string or list of strings)
- Endpoint: `music/{type}/library_items` (e.g., `music/artists/library_items`)
- Expected behavior: Filter to only return items from the specified provider's library

### What We Tried

1. **Client-side filtering based on provider_mappings**
   - Result: Failed - all Spotify accounts appear in mappings regardless of which added the item

2. **Server-side filtering with `provider` parameter**
   - Result: Partially implemented but behavior was inconsistent
   - The API accepts the parameter but may not filter correctly for same-provider-type accounts

3. **Using `provider_instance_id_or_domain` parameter**
   - Result: This parameter is for getting specific items by ID, not for filtering library_items

## Code Locations

### Files Modified (in stash)

The implementation attempt is preserved in git stash:
```bash
git stash list  # Look for "provider-filter-and-dropdown-work"
git stash show -p stash@{0}  # View the changes
```

Key files that were modified:

1. **lib/providers/music_assistant_provider.dart**
   - `_disabledProviders`: List of disabled provider instance IDs (local app setting)
   - `selectedProviderForFilter`: Returns single enabled provider for server-side filtering
   - `toggleProviderEnabled()`: Toggle provider on/off and trigger re-sync
   - `loadDisabledProviders()`: Load from local settings
   - `filterByProvider()`: Client-side filtering (enhanced version)
   - `isItemAllowedByProviderFilter()`: Check if item should be visible

2. **lib/services/music_assistant_api.dart**
   - Added `provider` parameter to: `getArtists`, `getAlbums`, `getTracks`, `getRandomArtists`, `getRandomAlbums`
   - Added `MusicProvider` model parsing from `/providers` endpoint
   - `musicProviders` getter: List of available music providers

3. **lib/services/sync_service.dart**
   - Added `provider` parameter to `syncFromApi()` and `forceSync()`
   - Pass provider filter to API calls during sync

4. **lib/services/settings_service.dart**
   - `getDisabledMusicProviders()`: Get list of disabled provider IDs
   - `setDisabledMusicProviders()`: Save disabled providers
   - `toggleProviderEnabled()`: Toggle and persist

5. **lib/screens/settings_screen.dart**
   - UI for toggling individual providers on/off
   - Display provider name and instance ID

6. **lib/screens/new_library_screen.dart**
   - Integration with provider filtering

7. **lib/models/music_provider.dart** (new file)
   - Model for MA provider instances
   - Fields: `instanceId`, `domain`, `name`, `available`

## Race Condition Issue

A race condition was identified where:
1. Initial app sync starts WITHOUT provider filter
2. User toggles provider filter
3. `clearCache()` is called
4. New sync with provider filter tries to start
5. "Sync already in progress" - new sync is skipped
6. Result: Old unfiltered data remains

Fix attempted: Reset `_isSyncing = false` in `clearCache()` to allow fresh sync.

## Potential Solutions to Explore

### 1. Investigate MA Server-Side Filtering

The MA server should support filtering by provider. Need to verify:
- Does the `provider` parameter work for filtering between same-type providers?
- Is there a different parameter or API endpoint?
- Check MA source code: https://github.com/music-assistant/server

### 2. Library Sync Per Provider

Instead of syncing all items and filtering, sync each provider's library separately:
```dart
for (final provider in enabledProviders) {
  final items = await api.getAlbums(provider: provider.instanceId);
  // Store with provider association
}
```

### 3. Track Item Origin

Store which provider originally added each item:
- Modify database schema to track `source_provider`
- When syncing, record which provider the item came from
- Filter based on source, not playability

### 4. Use MA's Internal Library State

MA might have internal state about which items are in which provider's library. Investigate:
- `/music/library/items` endpoint
- Provider-specific library endpoints
- MA's database schema for library associations

### 5. Check MA User Settings

The MA web UI's provider filter might be stored in user settings:
```dart
final userInfo = await api.getCurrentUserInfo();
// Check for provider_filter or similar field
```

## Testing Notes

### Log Messages to Watch

```
🔌 Selected provider for filter: spotify--xxxxx
🔍 API getArtists args: {limit: 1000, provider: spotify--xxxxx}
🔍 API getArtists returned XXX items
🔌 filterByProvider: XXX → YYY (disabled=[...])
```

### Test Scenario

1. Configure two Spotify accounts in MA
2. Add different artists to each account's library
3. In Ensemble, select only one Spotify account
4. Verify library shows ONLY that account's items
5. Switch to other account, verify different items

### Expected vs Actual

- **Expected**: Artist "Ari Mason" (only in Account A) should NOT appear when Account B is selected
- **Actual**: Artist appears regardless of which account is selected

## MA API Reference

### Get Providers
```
Command: providers
Returns: List of provider instances with type, domain, instanceId, name, available
```

### Library Items with Filter
```
Command: music/artists/library_items
Args: {
  limit: int,
  offset: int,
  provider: string | list<string>,  // Filter to specific provider(s)
  album_artists_only: bool,
  order_by: string
}
```

### Relevant MA Source Files

- `music_assistant/server/controllers/music.py` - Library item retrieval
- `music_assistant/server/models/provider.py` - Provider model
- `music_assistant/server/providers/` - Individual provider implementations

## Conclusion

The core challenge is that MA's `provider_mappings` indicates playability, not ownership. Server-side filtering via the `provider` parameter should work but needs further investigation to understand why it doesn't differentiate between multiple accounts of the same provider type.

The implementation is preserved in the git stash for future reference. The sorting/dropdown improvements were extracted and committed separately.
