# Ghost Players Analysis & Fixes

## Overview

This document captures the deep analysis and fixes applied to solve the "ghost player" problem in the Ensemble app - where multiple duplicate player entries accumulate in Music Assistant.

## The Problem

When using the app, ghost players (unavailable duplicate entries like "Chris' Phone") kept accumulating in Music Assistant. The player list would show:
- Chris' Phone (ensemble_xxx) - Available: false
- Chris' Phone (ensemble_yyy) - Available: false
- Chris' Phone (ensemble_zzz) - Available: false
- Chris' Phone (ensemble_current) - Available: true

New ghost players were created on each app launch/reconnect.

---

## Root Cause #1: Legacy ID Check Triggering New UUID Generation

**Location**: `lib/services/music_assistant_api.dart`, line 85

**The Bug**:
```dart
// OLD CODE - BROKEN
if (clientId == null || await DeviceIdService.isUsingLegacyId()) {
    clientId = await DeviceIdService.migrateToDeviceId();
}
```

Even when a valid `clientId` existed, the `isUsingLegacyId()` check could return `true` and trigger migration, which generated a **brand new UUID** every time.

**The Fix**:
```dart
// NEW CODE - FIXED
if (clientId == null) {
    clientId = await DeviceIdService.migrateToDeviceId();
}
```

Only generate a new ID if `clientId` is truly `null`.

**Commit**: `6320bb6` - "fix: prevent ghost player accumulation - ROOT CAUSE FIX"

---

## Root Cause #2: Not Reusing Existing builtin_player_id

**Location**: `lib/services/device_id_service.dart`, `getOrCreateDevicePlayerId()`

**The Bug**:
The function checked `local_player_id` first, but if that was null, it would generate a NEW ID even if `builtin_player_id` already contained a valid `ensemble_*` ID.

```dart
// OLD CODE - BROKEN
final existingId = prefs.getString(_keyLocalPlayerId);
if (existingId != null && existingId.startsWith('ensemble_')) {
    return existingId;
}
// Would fall through and generate NEW UUID even if builtin_player_id existed!
```

**The Fix**:
```dart
// NEW CODE - FIXED
// Check local_player_id first
final existingId = prefs.getString(_keyLocalPlayerId);
if (existingId != null && existingId.startsWith('ensemble_')) {
    return existingId;
}

// Check builtin_player_id (may exist without local_player_id)
final legacyBuiltinId = prefs.getString(_legacyKeyBuiltinPlayerId);
if (legacyBuiltinId != null && legacyBuiltinId.startsWith('ensemble_')) {
    // Reuse it and sync to local_player_id
    await prefs.setString(_keyLocalPlayerId, legacyBuiltinId);
    return legacyBuiltinId;
}

// Only generate new ID if we truly have nothing
```

**Commit**: `2fca436` - "fix: reuse existing builtin_player_id instead of generating new one"

---

## Root Cause #3: No Connection Guard

**Location**: `lib/services/music_assistant_api.dart`, `connect()`

**The Bug**:
Multiple simultaneous connection attempts could each generate new IDs.

**The Fix**:
Added a `Completer<void>? _connectionInProgress` guard so concurrent callers wait for the same connection instead of starting new ones.

```dart
if (_connectionInProgress != null) {
    return _connectionInProgress!.future;
}
_connectionInProgress = Completer<void>();
```

**Commit**: `6320bb6` - "fix: prevent ghost player accumulation - ROOT CAUSE FIX"

---

## Root Cause #4: ID Generated Before Ghost Adoption Could Run

**Location**: `lib/services/music_assistant_api.dart`, `connect()` and `lib/providers/music_assistant_provider.dart`

**The Bug**:
On fresh installations (reinstall), the app was supposed to "adopt" an existing ghost player ID instead of creating a new one. However, the timing was wrong:

1. `connect()` was called
2. **Line 97-99**: If no `clientId` existed, a NEW UUID was immediately generated
3. Connection established
4. `_tryAdoptGhostPlayer()` ran - but too late, ID was already generated!

This meant every reinstall created a new ghost player.

**The Fix**:
Defer ID generation until after ghost adoption has a chance to run:

1. In `connect()`, use a temporary session ID for fresh installs:
```dart
if (clientId == null) {
    // Fresh install - use a temporary session ID for now
    clientId = 'session_${_uuid.v4()}';
    _logger.log('Fresh install - using temporary session ID: $clientId');
}
```

2. In `_registerLocalPlayer()`, generate the real ID only if adoption didn't provide one:
```dart
var playerId = await SettingsService.getBuiltinPlayerId();
if (playerId == null) {
    // No ID yet (fresh install, no ghost was adopted) - generate now
    playerId = await DeviceIdService.getOrCreateDevicePlayerId();
    await SettingsService.setBuiltinPlayerId(playerId);
}
```

**Flow After Fix**:
1. `connect()` uses temp session ID
2. Connection established
3. `_tryAdoptGhostPlayer()` runs - finds matching ghost, adopts its ID
4. `_registerLocalPlayer()` uses adopted ID (or generates new if no ghost found)

**Commit**: `925155c` - "fix: defer player ID generation to allow ghost adoption on fresh installs"

---

## Ghost Player Adoption System

When the app is reinstalled, SharedPreferences are wiped and the app appears as a "fresh installation". To prevent creating yet another ghost player, the app implements a ghost adoption system:

### How It Works

1. **Detection**: `DeviceIdService.isFreshInstallation()` checks if any player ID exists in storage
2. **Search**: `findAdoptableGhostPlayer(ownerName)` looks for unavailable players matching the owner's name pattern (e.g., "Chris' Phone")
3. **Adoption**: `DeviceIdService.adoptPlayerId(id)` stores the ghost's ID as this installation's ID
4. **Registration**: The app registers with MA using the adopted ID, "reviving" the ghost

### Name Matching Logic

The adoption system looks for players named:
- `{OwnerName}' Phone` (for names ending in 's', e.g., "Chris' Phone")
- `{OwnerName}'s Phone` (for other names, e.g., "Mom's Phone")

Case-insensitive matching is used.

### Priority

If multiple ghosts match, `ensemble_` prefixed IDs are preferred (most recent app version).

---

## How to Delete Ghost Players

### Understanding MA's Storage

Ghost players exist in **two places**:

1. **In-memory** (runtime) - Players that have registered but aren't persisted
2. **settings.json** - Players that have been saved to config

The API methods (`players/remove`, `builtin_player/unregister`, `config/players/remove`) only affect the runtime state, not the persisted config. This is why ghosts kept reappearing.

### The Permanent Solution: Direct File Editing + Restart

To permanently delete ghost players:

1. **Stop or access the MA container**:
   ```bash
   docker exec musicassistant cat /data/settings.json | jq '.players | keys[]'
   ```

2. **Identify ghost entries** (look for `ensemble_`, `massiv_`, `ma_` prefixes)

3. **Edit settings.json to remove ghost entries**:
   ```bash
   # Backup first!
   cp /path/to/data/settings.json /path/to/data/settings.json.backup

   # Remove specific ghost players using jq
   cat settings.json | jq 'del(.players["ensemble_xxx"])' > settings_cleaned.json
   mv settings_cleaned.json settings.json
   ```

4. **Restart MA to clear in-memory ghosts**:
   ```bash
   docker restart musicassistant
   ```

### File Locations

| Location | Path |
|----------|------|
| Container internal | `/data/settings.json` |
| Host mount (typical) | `/home/home-server/docker/music-assistant/data/settings.json` |

### What Gets Stored in settings.json

Only players that MA has "seen" and saved config for. Example entry:
```json
"ensemble_4be5077a-2a21-42c3-9d06-2eaf48ae8ca7": {
  "values": {},
  "provider": "builtin_player",
  "player_id": "ensemble_4be5077a-2a21-42c3-9d06-2eaf48ae8ca7",
  "enabled": true,
  "name": null,
  "available": true,
  "default_name": "Kat's Phone"
}
```

### Why API Methods Don't Work

**API Behavior**:
- `players/remove` - Removes from runtime player manager, but player reappears if client reconnects
- `builtin_player/unregister` - Disconnects the player session
- `config/players/remove` - Returns error "Player configuration does not exist" for builtin players

**From MA Documentation**:
> "Deleted players which become or are still available will get rediscovered and will return to the list on MA restart or player provider reload."

### Previous Cleanup Attempts That Failed

We tried multiple API approaches:
1. `players/remove` - Server returns success but players persist
2. `builtin_player/unregister` - Only disconnects, doesn't delete
3. `config/players/remove` - Fails because no config exists for builtin players

**Conclusion**: The only way to permanently delete ghosts is to edit `settings.json` directly and restart MA.

---

## Storage Keys Used

| Key | Purpose | Service |
|-----|---------|---------|
| `local_player_id` | Primary player ID storage | DeviceIdService |
| `builtin_player_id` | Legacy/compatibility key | SettingsService |
| `device_player_id` | Old legacy key (deprecated) | DeviceIdService |

Both `local_player_id` and `builtin_player_id` should contain the same value after fixes are applied.

---

## ID Format Evolution

1. **Original**: `massiv_<hardware_hash>` - Based on device fingerprint (caused same ID on same-model phones)
2. **Current**: `ensemble_<uuid>` - Random UUID per installation (unique per app install)

---

## Commits in Chronological Order

1. `c772555` - "fix: use UUID for unique player identification per installation"
2. `468f815` - "Auto-cleanup ghost players on connect using builtin_player/unregister"
3. `1711132` - "Hide unavailable ghost players from player selector"
4. `6b47f40` - "Add ghost player prevention and cleanup"
5. `d262707` - "Add deep ghost player cleanup using config API"
6. `c1f52d5` - "fix: detect ghost players by ensemble_ prefix, not just builtin_player provider"
7. `da3750b` - "fix: use player list instead of config API for ghost detection"
8. `6320bb6` - "fix: prevent ghost player accumulation - ROOT CAUSE FIX"
9. `2fca436` - "fix: reuse existing builtin_player_id instead of generating new one"
10. `6e73011` - "fix: filter builtin_player events by player_id to prevent cross-device playback"
11. `925155c` - "fix: defer player ID generation to allow ghost adoption on fresh installs"

---

## Current State (After Fixes)

### What's Fixed
- ✅ New player IDs no longer generated on each reconnect
- ✅ Existing `builtin_player_id` is reused if `local_player_id` is missing
- ✅ Connection guard prevents duplicate ID generation from concurrent connects
- ✅ Unavailable ghost players are hidden from the player selector UI
- ✅ Cross-device playback isolation (events filtered by player_id)
- ✅ Ghost adoption on reinstall (adopts existing ghost instead of creating new) - **VERIFIED 2025-12-01**
- ✅ Permanent ghost deletion via settings.json editing + restart - **VERIFIED 2025-12-01**

### What's Not Possible via API
- ❌ Permanently deleting ghost players via MA API (by design)
- ❌ Config-level removal via API (builtin players return "no config exists")

### Existing Ghosts
Old ghost players can be cleaned up by:
1. Editing `/data/settings.json` to remove ghost entries
2. Restarting the MA container to clear in-memory ghosts
3. On reinstall, one ghost will be "adopted" and revived (preventing new ghost creation)

---

## Testing Checklist

### Normal Operation
- [ ] Fresh install generates ONE player ID and reuses it across app restarts
- [ ] Killing and reopening app doesn't create new ghost
- [ ] Network disconnect/reconnect doesn't create new ghost
- [ ] Check logs for "Using existing" vs "Generated new" messages
- [ ] Player list shows only available players (ghosts hidden)

### Ghost Adoption (Reinstall Test) - **VERIFIED 2025-12-01**
- [x] Note current player count before reinstall (was 12 "Chris' Phone" entries)
- [x] Uninstall app completely
- [x] Reinstall and connect with same owner name ("Chris")
- [x] Check logs for "Found matching ghost" and "Adopting ghost player ID"
- [x] Verify NO new ghost player was created (still 12 entries, one adopted/revived)
- [x] Verify the adopted ghost is now available

### Cross-Device Isolation - **VERIFIED 2025-12-01**
- [x] Install on two phones with different owner names (Chris, Kat)
- [x] Play on Phone A
- [x] Verify Phone B does NOT start playing
- [x] Check Phone B logs for "🚫 Ignoring event for different player"

### Ghost Deletion (Server-Side Cleanup) - **VERIFIED 2025-12-01**
- [x] Backup settings.json before editing
- [x] Use jq to remove ghost entries from settings.json
- [x] Restart MA container
- [x] Verify ghosts are gone from player list

---

## Related Issue: Cross-Device Playback

A separate but related issue was that playing on one phone would trigger playback on another phone.

**Root Cause**: App processed ALL `builtin_player` events without checking if the event was for its own player.

**Fix**: Filter events by `player_id` in `_handleLocalPlayerEvent()`:
```dart
if (eventPlayerId != null && myPlayerId != null && eventPlayerId != myPlayerId) {
    _logger.log('🚫 Ignoring event for different player');
    return;
}
```

**Commit**: `6e73011` - "fix: filter builtin_player events by player_id to prevent cross-device playback"

---

## Files Modified

| File | Changes |
|------|---------|
| `lib/services/device_id_service.dart` | UUID generation, reuse existing IDs |
| `lib/services/music_assistant_api.dart` | Connection guard, removed legacy ID check, event enrichment |
| `lib/providers/music_assistant_provider.dart` | Ghost filtering, event player_id filtering |
| `lib/services/settings_service.dart` | Owner name storage |
| `lib/screens/login_screen.dart` | "Your Name" field |
| `lib/screens/settings_screen.dart` | Ghost cleanup UI (limited effectiveness) |
