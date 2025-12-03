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

## Critical Issue: Corrupted Player Config Crashes MA Server

**Discovered**: 2025-12-02

### Symptoms

- Music Assistant server enters a restart loop
- 404 errors when trying to access MA web UI
- Docker shows: `musicassistant   Restarting (1) X seconds ago`
- Logs show:
  ```
  KeyError: 'provider'
  File "config.py", line 1319, in _migrate
      player_provider = player_config["provider"]
  ```

### Root Cause

Some ghost player entries in `settings.json` can become corrupted and lose required fields (like `provider`). When MA starts, it tries to migrate/load these configs and crashes because required fields are missing.

**Example of corrupted entries** (missing `provider` field):
```json
"ma_wjpkuwuzv7": {
  "default_name": "This Device"
},
"ensemble_43d1f583-a0ef-4945-8447-01bb803eeea9": {
  "default_name": "Chris' Phone"
}
```

**Example of valid entry** (has `provider` field):
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

### How to Fix

1. **Stop MA** (if not already in restart loop):
   ```bash
   docker stop musicassistant
   ```

2. **Backup settings.json**:
   ```bash
   cp /home/home-server/docker/music-assistant/data/settings.json \
      /home/home-server/docker/music-assistant/data/settings.json.backup-corrupt-fix
   ```

3. **Remove corrupted entries** (entries missing `provider` field):
   ```bash
   # Filter out entries that don't have a provider field
   cat /home/home-server/docker/music-assistant/data/settings.json | \
     jq '.players |= with_entries(select(.value | has("provider")))' > /tmp/settings_fixed.json
   ```

4. **Apply the fix** (need root or docker):
   ```bash
   # Via docker volume mount
   docker run --rm \
     -v /home/home-server/docker/music-assistant/data:/data \
     -v /tmp:/tmp \
     alpine cp /tmp/settings_fixed.json /data/settings.json
   ```

5. **Start MA**:
   ```bash
   docker start musicassistant
   ```

6. **Verify**:
   ```bash
   # Should show "Up X seconds" not "Restarting"
   docker ps | grep music

   # Should return 200
   curl -s http://192.168.4.120:8095/ -o /dev/null -w "%{http_code}"
   ```

### Prevention

The corruption likely occurs when:
- The app disconnects abruptly during player registration
- MA server restarts while builtin player is mid-registration
- Network issues during player state updates

The app's ghost adoption and cleanup mechanisms try to prevent accumulation, but corrupted entries can still occur server-side.

### Quick Diagnostic

To check for corrupted entries without stopping MA:
```bash
cat /home/home-server/docker/music-assistant/data/settings.json | \
  jq '.players | to_entries[] | select(.value | has("provider") | not) | .key'
```

This will list any player IDs that are missing the `provider` field.

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

---

## Root Cause #5: Overly Complex ID Management (2025-12-02)

**Location**: `lib/services/device_id_service.dart`

**The Problem**:
The ID management logic was more complex than the reference KMP client implementation:
- Multiple storage keys (`local_player_id`, `builtin_player_id`)
- Migration paths between legacy and current keys
- Potential race conditions in multi-key synchronization
- More code = more edge cases = more bugs

**KMP Client Pattern** (Simple & Correct):
```kotlin
settings.getStringOrNull("local_player_id") ?: Uuid.random().toString().also {
    settings.putString("local_player_id", it)
}
```

**The Fix** (Commit: `80f9777`):
1. **Simplified to Single Storage Key**:
   - Removed `builtin_player_id` from DeviceIdService
   - Unified `SettingsService.getBuiltinPlayerId()` to use `local_player_id`
   - Single source of truth, no dual-key synchronization

2. **Removed Migration Logic**:
   - No more checking legacy keys
   - Generate once on first access, store once
   - Matches KMP client's lazy generation pattern

3. **Cleaner Code Path**:
```dart
// NEW - Simple and clean
final existingId = prefs.getString(_keyLocalPlayerId);
if (existingId != null && existingId.startsWith('ensemble_')) {
    return existingId;
}
final playerId = 'ensemble_${_uuid.v4()}';
await prefs.setString(_keyLocalPlayerId, playerId);
return playerId;
```

---

## Root Cause #6: No Registration Verification (2025-12-02)

**Location**: `lib/services/music_assistant_api.dart`, `registerBuiltinPlayer()`

**The Problem**:
The app sent a registration command to MA but never verified it succeeded:
- No check that player was actually created
- No validation of player state after registration
- If registration partially failed, app wouldn't know
- Corrupted entries could be created silently

**The Fix** (Commit: `80f9777`):
Added post-registration verification:
```dart
// Send registration
await _sendCommand('builtin_player/register', ...);

// VERIFY: Wait for server to process, then check
await Future.delayed(const Duration(milliseconds: 500));
final players = await getPlayers();
final registeredPlayer = players.where((p) => p.playerId == playerId).firstOrNull;

if (registeredPlayer == null) {
    _logger.log('⚠️ WARNING: Player registered but not found in player list');
} else if (!registeredPlayer.available) {
    _logger.log('⚠️ WARNING: Player registered but marked unavailable');
} else {
    _logger.log('✅ Verification passed: Player is available in MA');
}
```

This provides early warning if registration fails or creates incomplete entries.

---

## Root Cause #7: Complex Connection Flow (2025-12-02)

**Location**: `lib/services/music_assistant_api.dart`, `connect()`

**The Problem**:
The WebSocket connection logic mixed session IDs with player IDs:
- Used temp session ID for fresh installs, then switched to player ID
- Confusing: "Is this session ID or player ID?"
- Added unnecessary complexity to connection flow
- Made debugging harder

**The Fix** (Commit: `80f9777`):
Separated concerns clearly:
```dart
// WebSocket connection uses its own session ID
final clientId = 'session_${_uuid.v4()}';
_logger.log('Using WebSocket session ID: $clientId');

// Player ID is managed separately during registration
// DeviceIdService handles player ID generation/retrieval
```

**Benefits**:
- WebSocket session ID is always unique per connection
- Player ID is always managed by DeviceIdService
- No confusion between the two concepts
- Clearer logs, easier debugging

---

## Comprehensive Fix Summary (2025-12-02)

**Commit**: `80f9777` - "fix: comprehensive ghost player fixes - simplify ID management and add verification"

### Changes Made

1. **DeviceIdService** (`lib/services/device_id_service.dart`):
   - Removed dual-key storage (`builtin_player_id`)
   - Removed migration logic
   - Single key: `local_player_id`
   - Simplified to match KMP client pattern

2. **SettingsService** (`lib/services/settings_service.dart`):
   - Unified `_keyBuiltinPlayerId` to point to `local_player_id`
   - Maintains API compatibility while using single storage

3. **MusicAssistantAPI** (`lib/services/music_assistant_api.dart`):
   - Separated WebSocket session ID from player ID
   - Added registration verification with player list check
   - Better logging of registration response
   - Warns if player not found or unavailable after registration

4. **MusicAssistantProvider** (`lib/providers/music_assistant_provider.dart`):
   - Simplified `_registerLocalPlayer()` flow
   - Better error handling with try-catch and rethrow
   - Improved ghost adoption with fresh install check
   - Clearer 5-step connection flow with comments
   - Enhanced logging at each step

### What's Fixed

✅ **Simpler ID Management**: Single source of truth, no migration complexity
✅ **Registration Verification**: Detect failed/incomplete registration early
✅ **Better Error Handling**: Critical errors propagate, non-fatal errors logged
✅ **Clearer Code**: Separation of concerns, better comments
✅ **Improved Logging**: Each step logged clearly for debugging
✅ **Ghost Adoption**: Only runs on fresh installs, happens before ID generation

### What's NOT Fixed (MA Server Limitations)

❌ **API Ghost Deletion**: No API endpoint to permanently delete player configs
❌ **Corruption Prevention**: MA server can still create incomplete entries on crash
❌ **Server-Side Validation**: MA doesn't validate player configs before saving

These are server-side issues that require either:
1. MA server updates to add proper API deletion
2. MA server to validate configs before persisting
3. Manual cleanup via `settings.json` editing

---

## Updated Current State (After 2025-12-02 Fixes)

### What's Fixed (Complete)
- ✅ **Simplified ID Management**: Matches KMP client pattern, single storage key
- ✅ **Registration Verification**: Detects failures early with post-registration checks
- ✅ **Clean Connection Flow**: WebSocket session ID separate from player ID
- ✅ **Ghost Adoption**: Works correctly on fresh installs
- ✅ **Better Logging**: Clear visibility into what's happening at each step
- ✅ **Error Handling**: Critical errors throw, non-fatal errors handled gracefully
- ✅ **Cross-Device Isolation**: Events filtered by player_id (fixed in earlier commit)
- ✅ **No New Ghost Creation**: Multiple fixes prevent ghost accumulation

### What's Improved (Better But Not Perfect)
- 🟡 **Corruption Prevention**: Better error handling reduces chance, but MA server can still create bad entries on crash/network failure
- 🟡 **Code Maintainability**: Much cleaner code, but still has ghost adoption complexity

### What's Not Possible (MA Server Limitations)
- ❌ **Permanent API Deletion**: MA server doesn't provide API to delete player configs
- ❌ **Server-Side Validation**: MA doesn't validate configs before persisting them
- ❌ **Atomic Registration**: No transaction support, partial state can occur on crash

### Required Manual Maintenance
If corrupted entries appear (missing `provider` field), manual cleanup required:
```bash
# Backup
cp /home/home-server/docker/music-assistant/data/settings.json settings.json.backup

# Remove entries missing 'provider' field
cat settings.json | jq '.players |= with_entries(select(.value | has("provider")))' > settings_fixed.json
mv settings_fixed.json settings.json

# Restart MA
docker restart musicassistant
```

---

## Testing Validation (Updated 2025-12-02)

### Pre-Deployment Testing Checklist

Before declaring this fix production-ready, test:

- [ ] Fresh install creates ONE player with `ensemble_` prefix
- [ ] Player ID persists across app restarts (check logs for "Using existing player ID")
- [ ] Network disconnect/reconnect doesn't create new ghost
- [ ] Reinstall with same owner name adopts existing ghost (check logs for "Adopting ghost")
- [ ] Reinstall with different owner name creates new player (no ghost to adopt)
- [ ] Registration verification logs appear in output
- [ ] Check MA `settings.json` - verify all `ensemble_*` entries have `provider: "builtin_player"`
- [ ] No corrupted entries appear after multiple app launches
- [ ] Ghost cleanup runs after registration (check logs)
- [ ] WebSocket connection succeeds with session ID
- [ ] Player appears as "available" in MA player list

### Log Markers to Look For

✅ **Good Signs**:
```
Using existing player ID: ensemble_xxx
Using WebSocket session ID: session_yyy
Registering player with MA: id=ensemble_xxx, name=Chris' Phone
✅ Builtin player registered successfully
✅ Verification passed: Player is available in MA
```

⚠️ **Warning Signs**:
```
⚠️ WARNING: Player registered but not found in player list
⚠️ WARNING: Player registered but marked unavailable
```

❌ **Error Signs**:
```
❌ CRITICAL: Player registration failed: <error>
❌ Error registering built-in player: <error>
```

---

## Updated Files Modified List

| File | Changes | Commits |
|------|---------|---------|
| `lib/services/device_id_service.dart` | Simplified to single key, removed migration logic | `80f9777` (2025-12-02) |
| `lib/services/settings_service.dart` | Unified builtin_player_id to point to local_player_id | `80f9777` (2025-12-02) |
| `lib/services/music_assistant_api.dart` | Added registration verification, separated session/player IDs, connection guard, config/players/save, 3-step deletion | `80f9777`, `6db0e56`, `c2522fb` (2025-12-02) |
| `lib/providers/music_assistant_provider.dart` | Improved registration flow, better error handling, ghost adoption, cross-device filtering | `80f9777` (2025-12-02), `6e73011` (earlier) |
| `lib/screens/login_screen.dart` | "Your Name" field (earlier commit) | Previous commits |
| `lib/screens/settings_screen.dart` | Ghost cleanup UI (earlier commit, limited effectiveness) | Previous commits |

---

## Root Cause #8: Incomplete Player Config Persistence (2025-12-02) - THE FINAL FIX

**Location**: `lib/services/music_assistant_api.dart`, `registerBuiltinPlayer()`

**The Problem**:
The `builtin_player/register` API creates a player in MA's runtime, but **does not always persist a complete config** to `settings.json`. This resulted in entries like:

```json
// CORRUPTED - Missing required fields
"ensemble_6896c1f6-c735-4158-a0bb-74f12f81384e": {
  "default_name": "Chris' Phone",
  "provider": "builtin_player"
}
```

When complete configs look like:
```json
// CORRECT - All required fields present
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

**Symptoms**:
- Error 999: `Field "player_id" of type str is missing in PlayerConfig instance`
- Playback fails completely
- MA server may enter restart loop if too many corrupted entries

**The Fix** (Commit: `6db0e56`):
After `builtin_player/register`, explicitly call `config/players/save` to ensure the config is properly persisted:

```dart
// Register the player
await _sendCommand('builtin_player/register', args: {
  'player_id': playerId,
  'player_name': name,
});

// CRITICAL: Explicitly save the player config to ensure all fields are persisted
try {
  _logger.log('💾 Saving player config to ensure persistence...');
  await _sendCommand('config/players/save', args: {
    'player_id': playerId,
    'values': <String, dynamic>{},
  });
  _logger.log('✅ Player config saved successfully');
} catch (e) {
  _logger.log('⚠️ Could not save player config: $e');
}
```

**Why This Works**:
- `config/players/save` triggers MA to fully persist the player config
- All required fields (`player_id`, `enabled`, `available`, `values`) are written
- Subsequent playback requests find a complete config

**Verified**: 2025-12-02 - New player created with complete config, playback works!

---

## Root Cause #9: Ghost Deletion Using Wrong API (2025-12-02)

**Location**: `lib/services/music_assistant_api.dart`, `cleanupGhostPlayers()`

**The Problem**:
The cleanup function only used `players/remove` which removes from runtime but not from `settings.json`. Ghosts kept reappearing.

**The Fix** (Commit: `c2522fb`):
Restored 3-step deletion process:

```dart
// Step 1: Unregister builtin player (disconnect it)
await _sendCommand('builtin_player/unregister', args: {'player_id': playerId});

// Step 2: Remove from player manager (runtime)
await _sendCommand('players/remove', args: {'player_id': playerId});

// Step 3: Remove persistent config (this is the key step!)
await _sendCommand('config/players/remove', args: {'player_id': playerId});
```

**Note**: Step 3 may fail for some player types, but the attempt is made.

---

## Final State: GHOST PLAYERS FIXED! ✅ (2025-12-02)

### What's Now Working

| Feature | Status | Verified |
|---------|--------|----------|
| Single player ID per device | ✅ Fixed | 2025-12-02 |
| ID persists across app restarts | ✅ Fixed | 2025-12-02 |
| No ghost creation on reconnect | ✅ Fixed | 2025-12-02 |
| Complete config persistence | ✅ Fixed | 2025-12-02 |
| Playback works | ✅ Fixed | 2025-12-02 |
| Ghost adoption on reinstall | ✅ Fixed | 2025-12-01 |
| Cross-device isolation | ✅ Fixed | 2025-12-01 |
| 3-step ghost deletion | ✅ Fixed | 2025-12-02 |

### Key Commits (Final Fix)

| Commit | Description |
|--------|-------------|
| `6db0e56` | Call `config/players/save` after registration to ensure complete config |
| `c2522fb` | Restore 3-step ghost deletion with `config/players/remove` |
| `80f9777` | Comprehensive fixes: simplified ID management, registration verification |

### Verification

New player created with complete config:
```json
{
  "key": "ensemble_aaaddd1a-7f09-40e2-a309-122249cef767",
  "player_id": "ensemble_aaaddd1a-7f09-40e2-a309-122249cef767",
  "provider": "builtin_player",
  "enabled": true,
  "available": true,
  "name": "Chris' Phone"
}
```

✅ All required fields present
✅ Playback works
✅ No more error 999

---

## Summary: The Ghost Player Saga

This issue took **15+ commits** and **deep investigation** to fully resolve. The root causes were:

1. **ID Generation Issues** (Root Causes #1-4): Multiple paths could generate new IDs
2. **Complex Code** (Root Causes #5-7): Overly complex ID/connection management
3. **Incomplete Persistence** (Root Cause #8): MA server didn't always save complete configs
4. **Wrong Deletion API** (Root Cause #9): Using runtime-only removal instead of config removal

**The final fix** was discovering that `builtin_player/register` doesn't always persist a complete config, and explicitly calling `config/players/save` after registration ensures all fields are written.

**Lesson Learned**: When in doubt, explicitly save the config. Don't assume registration implies persistence.

---

## Root Cause #10: Ghost Adoption Only Checked Unavailable Players (2025-12-02)

**Location**: `lib/services/music_assistant_api.dart`, `findAdoptableGhostPlayer()`

**The Problem**:
The ghost adoption function only looked for players with `available=false`:

```dart
// OLD CODE - BROKEN
for (final player in allPlayers) {
  if (!player.available) {  // <-- BUG: Only unavailable players!
    final nameMatch = ...
```

But properly registered players can remain `available=true` even after the app disconnects (if MA hasn't timed them out yet). When the user cleared app storage and reconnected:

1. Existing "Chris' Phone" player was `available=true`
2. `findAdoptableGhostPlayer` skipped it (looking only for unavailable)
3. App generated NEW player ID → ghost created

**Symptoms**:
```
👻 Fresh install detected, searching for adoptable ghost for "Chris"...
🔍 Looking for players named: "Chris' Phone" or "Chris's Phone"
🔍 No adoptable ghost player found  // <-- Wrong! Chris' Phone exists!
👻 No matching ghost player found - will generate new ID
Generated new player ID: ensemble_8556a5a6...
```

**The Fix** (Commit: pending):
Changed to check ALL players with matching name, prioritizing by:
1. `ensemble_` prefix + unavailable (priority 3) - best match
2. `ensemble_` prefix + available (priority 2) - still good, adopt it!
3. Other unavailable players (priority 1) - fallback

```dart
// NEW CODE - FIXED
for (final player in allPlayers) {
  final nameMatch = player.name == expectedName1 || ...

  if (nameMatch) {
    final isEnsemblePlayer = player.playerId.startsWith('ensemble_');
    final isUnavailable = !player.available;

    // Priority scoring: ensemble prefix (2 points) + unavailable (1 point)
    final priority = (isEnsemblePlayer ? 2 : 0) + (isUnavailable ? 1 : 0);

    _logger.log('🔍 Found matching player: ${player.name} (${player.playerId}) '
               'available=${player.available} priority=$priority');

    if (priority > matchPriority) {
      matchedPlayer = player;
      matchPriority = priority;
    }
  }
}
```

**Key Insight**: Ghost adoption should reuse ANY existing `ensemble_*` player for that owner, regardless of availability status. The player is ours, we should take it back!

---

## Updated Final State (2025-12-03)

| Feature | Status | Verified |
|---------|--------|----------|
| Single player ID per device | ✅ Fixed | 2025-12-02 |
| ID persists across app restarts | ✅ Fixed | 2025-12-02 |
| No ghost creation on reconnect | ✅ Fixed | 2025-12-02 |
| Complete config persistence | ✅ Fixed | 2025-12-02 |
| Playback works | ✅ Fixed | 2025-12-02 |
| Ghost adoption on reinstall | ✅ Fixed | 2025-12-02 (Root Cause #10) |
| Ghost adoption of AVAILABLE players | ✅ Fixed | 2025-12-02 |
| Cross-device isolation | ✅ Fixed | 2025-12-01 |
| 3-step ghost deletion via API | ❌ Does NOT work | 2025-12-03 |
| Manual settings.json cleanup | ✅ Only reliable method | 2025-12-03 |

---

## Critical Finding: API Deletion Does NOT Persist (2025-12-03)

### The Problem

Despite what the API responses suggest, **none of the deletion APIs actually remove players from `settings.json`**. They only affect runtime state.

**Tested deletion methods:**
```
1. config/players/save (enabled: false)  → Response: success → Still in settings.json ❌
2. builtin_player/unregister             → Response: success → Still in settings.json ❌
3. players/remove                        → Response: success → Still in settings.json ❌
4. config/players/remove                 → Response: success → Still in settings.json ❌
```

All four steps return successful responses, but the player entry remains in `settings.json`. On MA restart, ghosts reappear.

### Why Previous Testing Appeared to Work

Earlier testing showed two ghosts "deleted" - but they were actually:
1. Removed from runtime (so they disappeared from player list temporarily)
2. Still present in settings.json
3. Reappeared after some time or MA activity

### Confirmed: Only Manual Deletion Works

The ghost MD was correct all along. The **only** way to permanently delete ghost players:

```bash
# 1. Backup
cp /home/home-server/docker/music-assistant/data/settings.json settings.json.backup

# 2. Remove specific ghost (replace GHOST_ID with actual ID)
cat settings.json | jq 'del(.players["GHOST_ID"])' > settings_fixed.json
mv settings_fixed.json settings.json

# 3. Restart MA
docker restart musicassistant
```

### Debug Screen Tools (2025-12-03)

Added tools to help identify ghosts (even if deletion doesn't persist):

**View All Players** - Color coded display:
- 🟢 Green = Current device (your player)
- 🔴 Red = Ghost player (duplicate app player)
- 🟠 Orange = Unavailable/Corrupt player
- Shows player ID, provider, and availability

**Clean Up Ghosts** - Attempts API deletion:
- Will remove from runtime (temporary)
- Does NOT persist after MA restart
- Useful for temporary relief

**Repair Corrupt** - Attempts to fix corrupt configs:
- Detects error 999 (missing player_id field)
- Tries to re-save config
- Falls back to deletion attempt

### Multi-Device Corruption Issue

**Scenario discovered 2025-12-02:**
1. New device (Kat's Phone) installs app
2. Registration interrupted (network, app backgrounded, etc.)
3. MA saves incomplete config (missing `player_id` field)
4. Error 999 affects ALL builtin players
5. Other devices (Chris' Phone) can't play

**Current protection:**
- `config/players/save` called after registration (line 1270)
- Verification check after registration (line 1284)
- But if app closes before save completes, corruption still possible

**Future consideration:**
- Startup health check to auto-repair corrupt configs
- Needs testing with second device

---

## Alternative Approach: Squeezelite

One way to avoid ghost player issues entirely would be to use Squeezelite for audio playback instead of `builtin_player`:

**Advantages:**
- `slimproto` provider has mature player lifecycle handling
- Players identified by MAC address - no ghost accumulation
- Better audio quality, gapless playback
- Sync with other Squeezebox players

**Disadvantages:**
- Requires bundling native Squeezelite binary for Android
- More complex audio pipeline
- Battery usage (Squeezelite runs continuously)
- Significant architectural change

**Status:** Under consideration, not implemented

