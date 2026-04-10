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

To update the installed app after building:

```bash
cp .build/release/aibridge /Applications/AIIsland.app/Contents/MacOS/aibridge
cp .build/release/AIIsland /Applications/AIIsland.app/Contents/MacOS/AIIsland
```

## Architecture

### Three Targets (Package.swift)

1. **AIIslandProtocol** (library) — Shared Codable types used by both app and bridge. The canonical type definitions live in `Protocol.swift`. Never duplicate types elsewhere.

2. **AIBridge** (CLI executable `aibridge`) — Lightweight binary invoked by AI tool hook scripts. Reads event JSON from stdin, connects to `~/.aiisland/island.sock` Unix domain socket, sends an NDJSON message, and for permission/ask events blocks until it receives a response. Must start in <10ms. Exits silently on socket errors (never breaks the agent).

3. **AIIsland** (macOS app executable) — The main overlay app. Runs as an agent app (menu bar only by default, dock icon optional via Settings). Listens on the Unix socket, manages sessions, and renders the Dynamic Island panel. Supports launch at login via SMAppService.

### Wire Protocol

Communication between bridge and app uses **NDJSON** (newline-delimited JSON) over a **Unix domain socket** at `~/.aiisland/island.sock`.

- **Bridge → App**: `BridgeCommand.processClaudeHook(ClaudeHookPayload)` — forwards Claude Code's native JSON payload directly
- **App → Bridge**: `BridgeResponse.claudeHookDirective(ClaudeHookDirective)` for permission decisions, or `.acknowledged` for fire-and-forget events
- The bridge decodes Claude's native `ClaudeHookPayload` (with `hook_event_name`, `session_id`, optional `cwd`, `tool_name`, `permission_suggestions`, etc.) and forwards it unchanged
- Permission responses use Claude Code's native format: `{"continue":true,"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[...]}}}`

### Main App Modules

- **App/** — Entry point (`@main`), `AppDelegate` (menu bar, keyboard shortcuts, lifecycle), `AppState` (central @Observable state)
- **Socket/** — `SocketServer` (NWListener on Unix socket), `SocketConnection` (per-connection handler with NDJSON framing)
- **Session/** — `AgentSession` model (with `SubagentInfo`, `TaskInfo`, `isDiscovered`), `SessionManager` (lifecycle, timeouts, 24h grace for discovered sessions), `SessionDiscovery` (JSONL transcript scanner for launch-time recovery), `SessionStatus`, `IslandMode` enum
- **Overlay/** — `IslandPanel` (non-activating NSPanel), `IslandPanelController` (positioning at notch, expand/collapse animations), SwiftUI views for each mode (Idle, Monitor, Approve, Ask)
- **PixelPet/** — 8x8 pixel art creatures with species enum, SwiftUI renderer, frame animator
- **Audio/** — AVAudioEngine chiptune synthesizer, event-to-sound mapping
- **Terminal/** — Protocol-based adapters for jumping to exact tab/pane (iTerm2 via AppleScript, Kitty via remote control, etc.)
- **HookConfig/** — Auto-installs hook entries into AI tool config files (Claude Code settings.json, Codex, Gemini). Includes `HookHealthCheck` for validating binary, config JSON, and stale paths per tool, with per-agent config schema awareness.
- **Usage/** — Context window and rate limit monitoring — reads Claude Code's cache files, models, and bar/dot views
- **Util/** — Screen geometry (notch detection), accessibility permissions, `ShellUtils` (login-shell PATH resolution for GUI apps), `DisplayOption` (multi-monitor screen enumeration and selection), `DesignTokens`

### Data Flow

```
Claude Code (hook fires on 14 events)
  → aibridge CLI (reads stdin JSON, decodes ClaudeHookPayload)
    → Unix socket → SocketServer → SocketConnection
      → AppState.dispatch(BridgeCommand) → handleClaudeHook()
        → SwiftUI views react → User clicks Allow/Deny/suggestion button
          → BridgeResponse.claudeHookDirective sent back through socket
            → aibridge writes hookSpecificOutput JSON to stdout
              → Claude Code reads response and proceeds
```

### Key Design Decisions

- **Non-activating panel**: Uses `NSPanel` with `.nonactivatingPanel` style mask so the overlay never steals focus from editors/terminals. Level is `.statusBar + 1`.
- **Native Claude payload passthrough**: The bridge decodes Claude Code's native `ClaudeHookPayload` and forwards it to the app unchanged. No re-interpretation or event type mapping.
- **14 hook events**: SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest (24h timeout), PermissionDenied, Notification, Stop, StopFailure, SubagentStart, SubagentStop, PreCompact.
- **Rich permission options**: Claude Code sends `permission_suggestions` (typed `ClaudePermissionUpdate` values) with PermissionRequest hooks. These render as additional buttons beyond Allow/Deny (e.g., "Always allow Bash for this session").
- **Fire-and-forget vs blocking**: Only `PermissionRequest` blocks the bridge waiting for a response (24h timeout). All other events get an `.acknowledged` response.
- **Terminal jump**: Each terminal has its own adapter. iTerm2 uses AppleScript, Kitty uses `kitty @` remote control, others mostly just activate the app.
- **Hook health checks**: `HookHealthCheck` validates aibridge binary existence, config JSON validity, stale command paths, and third-party hook coexistence. Each tool (Claude, Codex, Gemini) has its own config schema parser. Repair re-installs hooks for detected tools only.
- **InstallMode enum**: `HookInstaller.installAll(mode:)` uses `.incremental` (default on launch), `.forceReinstall` (repair), or `.bootstrap` (Settings "Install" button — creates configs even for undetected tools).
- **Multi-monitor support**: `DisplayOption` enumerates screens via `NSScreen.screens`, generates stable IDs from `NSScreenNumber`. `IslandPanelController.targetScreen()` resolves: user-selected screen > notch screen > main screen. Settings persists `preferredScreenID`.
- **Subagent tracking**: `PreToolUse(Agent)` descriptions are cached in a per-session FIFO queue. `SubagentStart` pops the oldest description. This is best-effort — Claude Code's hook protocol has no correlation ID between PreToolUse and SubagentStart.
- **Task visualization**: `PostToolUse` for `TaskCreate`/`TaskUpdate` tools updates `AgentSession.activeTasks`. Fallback matching uses title + FIFO when the tool response omits a task ID.
- **Session discovery**: On launch, `SessionDiscovery` scans `~/.claude/projects/` for JSONL transcripts modified within 24h. Discovered sessions merge without overwriting live socket sessions and get a 24h expiration grace period.

### Design Tokens

- Background: `#1a1a1a` (0.95 alpha)
- Accent: `#D97757` (warm orange)
- Status colors: blue=working, green=idle, orange=waiting, red=error
- Corner radius: 19 for panel, 12 for cards, 8 for badges
- Font: system for UI, monospaced for code/diffs

## Git Commit Guidelines

- **DO NOT** include Claude attribution or co-authored-by information in commit messages
- Keep commit messages clean and professional without AI tool references
