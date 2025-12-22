# Sherwood CDC-2010 “5-Disc Changer” for Apple Music — MVP Plan (macOS)

## 0) Product thesis (don’t drift)
Build a *machine*, not a music browser:
- Apple Music is where metadata/search/browsing lives.
- This app deals only in **five discs** and **cover art**.
- The UI enforces constraints: you can’t “optimize” your listening to death.

## 1) MVP goal
Prove we can:
1) Hold 5 “disc” slots (each slot = one album-like tracklist)
2) Control Apple Music playback (play/pause/next/prev, shuffle/repeat)
3) Implement the signature Sherwood behaviors:
   - DISC 1–5 buttons
   - Play All (disc 1→5, track 1→end)
   - Disc Repeat (repeat current disc)
   - One-disc shuffle
   - 5-disc shuffle (random disc + random track with deliberate “mechanical” delay)
   - Spiral mode (all track 1s, then all track 2s, … across discs)
   - Lid-open “prepare” mode: can swap **inactive** discs while current disc keeps playing
4) Persist state (loaded discs + mode + current disc)

## 2) Non-goals (MVP)
- No search UI, no library UI, no metadata views
- No lyrics, recommendations, stats dashboards
- No crossfade, no “smart” queueing
- No perfect fidelity to Apple Music’s ever-shifting internal models
- No iOS version

## 3) Tech strategy (lean + reliable)
### UI
- SwiftUI app (macOS)
- Two primary UI states:
  - **Closed Lid (Playback Mode):** big DISC buttons + transport controls + mode indicator
  - **Open Lid (Preparation Mode):** five covers + swap controls; **no transport controls visible**

### Apple Music control layer (MVP)
Use AppleScript (via `NSAppleScript` or `OSAScript`) to control Music.app:
- `play`, `pause`, `playpause`
- `next track`, `previous track`
- set `shuffle enabled` (bool)
- set `song repeat` (off/one/all) (as supported by Music.app scripting)
- play a specific track (by persistent id / database id if possible; otherwise by playlist index)

Rationale: AppleScript is the shortest path to “it works on a real Mac today.”

## 4) Core data model (simple + persistent)
Persist to a small JSON file in Application Support.

### Entities
- `DiscSlot` (5 total)
  - `slotIndex: Int` (1–5)
  - `sourceType: "playlist"` (MVP: only playlists)
  - `playlistPersistentID: String` (or unique identifier retrievable via AppleScript)
  - `artworkPNGBase64: String` (cached cover image)
  - `trackIDs: [String]` (optional cache; can be derived live from playlist)
- `PlaybackState`
  - `activeDiscIndex: Int`
  - `mode: Mode` (enum)
  - `lidOpen: Bool`
  - `spiralPosition: (trackNumber: Int, discCursor: Int)` (for resume)
  - `playAllCursor: (discIndex: Int, trackIndex: Int)` (for resume)

### Mode enum
- `normal`
- `playAll`
- `discRepeat`
- `oneDiscShuffle`
- `fiveDiscShuffle`
- `spiral`

## 5) “Disc” meaning in MVP
A disc is an **Apple Music playlist** that represents an album’s track order.

How users load discs (MVP-friendly):
- In Music.app: user selects (or creates) an album playlist.
- In this app:
  - Button: **Load Disc from Current Playlist**
  - Or: **Load Disc from Clipboard** if clipboard contains a Music playlist URL (optional)

Why playlists for MVP:
- AppleScript can reliably enumerate playlist tracks in order.
- Spiral and Play All become deterministic.

(Phase 2 can support “load album directly” if AppleScript/MusicKit allows stable album identifiers.)

## 6) Key behaviors (match the Sherwood rules)

### 6.1 Disc buttons
- Always visible in Closed Lid: DISC 1–5
- Keyboard: ⌘1…⌘5 switches active disc
- Switching disc in Closed Lid:
  - Sets `activeDiscIndex`
  - Starts playing disc according to current mode rules (usually first track unless continuing)

### 6.2 Lid Open (Preparation Mode)
- Playback continues.
- Transport controls hidden.
- Active disc slot is locked (cannot be replaced).
- Inactive discs can be replaced (loaded from current playlist).
- Closing lid returns to Closed Lid UI, no confirmations.

### 6.3 Play All
- Plays Disc 1 → Disc 5 in order
- Within each disc, plays tracks in order
- When Disc 5 ends:
  - Stop (MVP) or optionally loop back (future option)
- Implementation approach:
  - Maintain `playAllCursor`
  - Observe track change by polling `current track` every ~0.5–1.0s (MVP)
  - When end-of-playlist reached, advance disc

### 6.4 Disc Repeat
- Repeats the current disc from track 1 after last track ends
- Implementation approach:
  - When last track finishes, play track 1 of same playlist
  - (If Music.app supports repeat-one-playlist semantics, great; otherwise emulate)

### 6.5 One-disc shuffle
- Shuffle only within the active disc
- Implementation approach:
  - Enable Music shuffle
  - Ensure queue context is restricted to the playlist
  - If Music.app shuffle leaks context, emulate by manually selecting random track indices

### 6.6 5-disc shuffle (the “whirring”)
- Each “next” selection chooses:
  1) random disc among loaded discs
  2) random track within that disc
- Add deliberate “mechanical” delay between choices (e.g., 350–700ms)
- Optional subtle sound effect (future; keep MVP silent)
- Implementation approach:
  - Disable Music shuffle
  - On track end (or on “Next”):
    - sleep delay
    - pick (disc, track)
    - play that specific track

### 6.7 Spiral mode
- Plays:
  - All Track 1s across discs in disc order (1→5),
  - then all Track 2s, etc.
- Skip discs that don’t have that track number.
- Stop when trackNumber exceeds max track count among loaded discs.
- Implementation approach:
  - Precompute per-disc track list (ordered track IDs) when entering Spiral mode.
  - Maintain `spiralPosition` (trackNumber, discCursor).
  - On each step, find next playable disc with that trackNumber.
  - Play that track; update position.

## 7) AppleScript interface (MVP spec for Codex)

Create a small Swift wrapper: `MusicController`.

Required AppleScript commands:
- Get currently running / launch Music.app
- Get current playlist selection (or current playlist of the player)
- Get playlist persistent identifier
- Get playlist tracks (ordered), plus per-track unique identifier playable via script
- Get artwork of current track (or first track of playlist) as raw data (if possible)
- Play a track by id or by “track index in playlist”

Fallback strategy if “play by id” is painful:
- Set Music’s current playlist to the target playlist, then `play track <n> of playlist <name>`
- Use stable playlist identifiers and avoid relying on names where possible.

## 8) UI layout (minimal but decisive)
### Closed Lid (Playback Mode)
- Top row: DISC 1–5 big buttons (active disc highlighted)
- Middle: Large cover art for active disc
- Bottom: Transport controls (Prev / PlayPause / Next)
- Mode strip: small indicators/toggles
  - Mode selector: Normal / Play All / Spiral / 5-Disc Shuffle
  - Toggle: Disc Repeat (mutually exclusive with Play All / Spiral? define in code)
  - Toggle: One-disc shuffle (only valid in Normal)

### Open Lid (Preparation Mode)
- Full window becomes a 5-disc “tabletop”
- Each disc shows cover art + disc number badge
- Active disc: dim + lock icon; cannot be replaced
- Inactive discs:
  - Button: “Load from Current Playlist”
  - Drag/drop target (optional if easy)
- Button: “Close Lid” (or click background)

## 9) Persistence & startup behavior
- On launch:
  - Load JSON state
  - Render covers immediately from cache
  - Do NOT auto-start playback (MVP conservative)
- If Music.app not running:
  - Show a single friendly message: “Open Music to use the changer.”

## 10) Testing checklist (manual)
- Load 5 playlists, confirm covers render
- Switch discs with buttons and ⌘1–⌘5
- Open lid while playing; confirm playback continues
- Replace an inactive disc while playing; confirm no interruption
- Play All completes 1→5 correctly
- Disc Repeat loops correctly
- Spiral mode plays track-number slices correctly
- 5-disc shuffle feels random + delayed; no crashes on missing discs
- Persist/restore after quit/relaunch

---

# Future phases (notes, not commitments)

## Phase 2 — Better “loading” (less playlist dependence)
- Load directly from selected album in Music (album identifier → track list)
- Accept drag/drop from Music of an album/playlist URL
- Improved cover caching (handle missing artwork gracefully)

## Phase 3 — More Sherwood “physicality”
- Optional mechanical SFX pack (very subtle, user-toggle)
- Gentle animations: carousel shift, disc “recessed” active slot
- Haptic-like micro-delays to make mode changes feel real

## Phase 4 — Multiple changers (named sets)
- Save/load “Changer Sets” (e.g., “Winter 1997”)
- Quick swap between sets from a small side menu
- Still no metadata browsing inside the app

## Phase 5 — Automation hooks
- Shortcuts actions:
  - Load Disc X from current playlist
  - Toggle modes
  - Open/close lid
- URL scheme:
  - `changer://load?slot=3&playlist=...`

## Phase 6 — Robust track-change detection
- Replace polling with event-driven notifications if feasible (MusicKit / distributed notifications)
- Harden behavior across OS updates

---

# “Don’t accidentally ruin it” guardrails
- Never add discovery or recommendations.
- Never show scrolling text metadata as a substitute for Apple Music.
- Never crossfade.
- Never become a general-purpose player.
- When in doubt: fewer controls, more constraint.
