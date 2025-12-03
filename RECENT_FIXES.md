# Recent Fixes - December 2025

## Build 495ccce - UI Improvements

### 1. Removed Hero Animations
- Removed Hero widget animations from album and artist cards
- Fixes the "zoom" effect on bottom navigation bar during page transitions
- Cards now use smooth fade+slide transitions instead

### 2. Custom Page Transitions
- Created `FadeSlidePageRoute` for consistent navigation animations
- Uses fade with subtle 5% horizontal slide
- 300ms duration matching player animations
- Located in `lib/utils/page_transitions.dart`

### 3. Contrast Fixes for Adaptive Colors
- Added luminance-based text color selection
- Dark primary colors now get white text, light colors get black text
- Bottom nav icons automatically lighten when too dark for visibility
- Prevents unreadable text on Play buttons with dark album art colors

### 4. Glow Overscroll on Home Screen
- Added glow effect when overscrolling (matching Library behavior)
- Uses primary color for the glow
- Replaced iOS-style bounce with Android-style glow

### 5. Settings Connection Bar
- Connection status now displays as edge-to-edge bar
- Tick icon and "Connected" text on same line
- Server URL displayed below

---

## Build 9114a87 - Play Responsiveness

- Mini player appears instantly when playing (optimistic update)
- Album/artist views no longer auto-close when playing

## Build 19477f9 - Color Flash Fix

- Fixed color flash during navigation with adaptive theme
- Keeps previous adaptive color during rebuilds

## Build d1a8f67 - Animation & Nav Improvements

- Player animation reduced to 300ms (from 400ms)
- Bottom nav bar syncs color with expanded player background
- Smooth color transition during player expand/collapse

## Build 87171dc - Settings & Logo

- Logo inverts properly on light mode
- Simplified settings screen (removed IP/port fields)
- Added transparent logo matching login screen size

## Build f894675 - Auth Reconnection

- Fixed auto-reconnection with Authelia authentication
- Credentials now properly restored on cold start

## Build 10bc407 - Back Gesture Fix

- Added 40px dead zone on right edge for Android back gesture
- Prevents queue panel interference during swipe-back
