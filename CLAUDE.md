# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

AI Island is a macOS native "Dynamic Island" overlay for AI coding agents. It renders a non-activating panel at the MacBook notch (or top-center on external monitors) that monitors, approves permissions, answers questions, and jumps to terminal sessions for AI tools like Claude Code, Codex, Gemini CLI, Cursor, etc.

## Build Commands

```bash
swift build                          # Debug build (both AIIsland app + aibridge CLI)
swift build -c release               # Release build
swift build --product AIIsland       # Build just the main app
swift build --product aibridge       # Build just the bridge CLI
swift test                           # Run tests
```

Binaries land in `.build/debug/` or `.build/release/`.

## Architecture

### Three Targets (Package.swift)

1. **AIIslandProtocol** (library) — Shared Codable types used by both app and bridge. The canonical type definitions live in `Protocol.swift`. Never duplicate types elsewhere.

2. **AIBridge** (CLI executable `aibridge`) — Lightweight binary invoked by AI tool hook scripts. Reads event JSON from stdin, connects to `~/.aiisland/island.sock` Unix domain socket, sends an NDJSON message, and for permission/ask events blocks until it receives a response. Must start in <10ms. Exits silently on socket errors (never breaks the agent).

3. **AIIsland** (macOS app executable) — The main overlay app. Runs as an agent app (no dock icon, menu bar only). Listens on the Unix socket, manages sessions, and renders the Dynamic Island panel.

### Wire Protocol

Communication between bridge and app uses **NDJSON** (newline-delimited JSON) over a **Unix domain socket** at `~/.aiisland/island.sock`.

- **Bridge → App**: `BridgeMessage` with flat `AgentEvent` enum + separate `MessagePayload` enum carrying typed payloads
- **App → Bridge**: `AppResponse` with `ResponseAction` (.allow/.deny/.chooseOption)
- Payload types use `tool` (not `toolName`) for the tool name field

### Main App Modules

- **App/** — Entry point (`@main`), `AppDelegate` (menu bar, keyboard shortcuts, lifecycle), `AppState` (central @Observable state)
- **Socket/** — `SocketServer` (NWListener on Unix socket), `SocketConnection` (per-connection handler with NDJSON framing)
- **Session/** — `AgentSession` model, `SessionManager` (lifecycle, timeouts), `SessionStatus`, `IslandMode` enum
- **Overlay/** — `IslandPanel` (non-activating NSPanel), `IslandPanelController` (positioning at notch, expand/collapse animations), SwiftUI views for each mode (Idle, Monitor, Approve, Ask)
- **PixelPet/** — 8x8 pixel art creatures with species enum, SwiftUI renderer, frame animator
- **Audio/** — AVAudioEngine chiptune synthesizer, event-to-sound mapping
- **Terminal/** — Protocol-based adapters for jumping to exact tab/pane (iTerm2 via AppleScript, Kitty via remote control, etc.)
- **HookConfig/** — Auto-installs hook entries into AI tool config files (Claude Code settings.json, Codex, Gemini)
- **Util/** — Screen geometry (notch detection), accessibility permissions

### Data Flow

```
AI Tool (Claude Code, Codex, etc.)
  → Hook fires → aibridge CLI → Unix socket → SocketServer
  → BridgeMessage parsed → AppState updated → IslandMode changes
  → SwiftUI views react → User clicks Allow/Deny or option
  → AppResponse sent back through socket → aibridge exits with code
  → AI Tool proceeds or blocks
```

### Key Design Decisions

- **Non-activating panel**: Uses `NSPanel` with `.nonactivatingPanel` style mask so the overlay never steals focus from editors/terminals. Level is `.statusBar + 1`.
- **Flat event enum + separate payload**: `AgentEvent` is a String-based enum for wire compatibility. Typed payloads are in the separate `MessagePayload` enum.
- **Fire-and-forget vs blocking**: Most events (tool_use, status, session_start/end) are fire-and-forget. Only `permission_request` and `ask` block the bridge waiting for a response.
- **Terminal jump**: Each terminal has its own adapter. iTerm2 uses AppleScript, Kitty uses `kitty @` remote control, others mostly just activate the app.

### Design Tokens

- Background: `#1a1a1a` (0.95 alpha)
- Accent: `#D97757` (warm orange)
- Status colors: blue=working, green=idle, orange=waiting, red=error
- Corner radius: 19 for panel, 12 for cards, 8 for badges
- Font: system for UI, monospaced for code/diffs
