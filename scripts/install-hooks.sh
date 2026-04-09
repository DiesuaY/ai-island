#!/usr/bin/env bash
#
# install-hooks.sh — Install AI Island hooks into Claude Code's settings.json
#
# Usage:
#   ./scripts/install-hooks.sh              # auto-detect aibridge path
#   ./scripts/install-hooks.sh /path/to/aibridge  # explicit path
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- Locate aibridge binary ----------

find_aibridge() {
    # 1. Explicit argument
    if [[ -n "${1:-}" ]] && [[ -x "$1" ]]; then
        echo "$1"
        return
    fi

    # 2. Release build
    local release="$PROJECT_DIR/.build/release/aibridge"
    if [[ -x "$release" ]]; then
        echo "$release"
        return
    fi

    # 3. Debug build
    local debug="$PROJECT_DIR/.build/debug/aibridge"
    if [[ -x "$debug" ]]; then
        echo "$debug"
        return
    fi

    # 4. Inside an app bundle next to this script
    local app_bundle="$PROJECT_DIR/AIIsland.app/Contents/MacOS/aibridge"
    if [[ -x "$app_bundle" ]]; then
        echo "$app_bundle"
        return
    fi

    # 5. Common install locations
    for candidate in /usr/local/bin/aibridge /opt/homebrew/bin/aibridge "$HOME/.local/bin/aibridge"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done

    # 6. In PATH
    if command -v aibridge &>/dev/null; then
        command -v aibridge
        return
    fi

    return 1
}

AIBRIDGE="$(find_aibridge "${1:-}")" || {
    echo "ERROR: Could not find aibridge binary."
    echo ""
    echo "Build it first:  swift build -c release"
    echo "Or specify path: $0 /path/to/aibridge"
    exit 1
}

# Resolve to absolute path
AIBRIDGE="$(cd "$(dirname "$AIBRIDGE")" && pwd)/$(basename "$AIBRIDGE")"

echo "Found aibridge at: $AIBRIDGE"

# ---------- Settings file ----------

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# Create settings.json if it doesn't exist
if [[ ! -f "$SETTINGS" ]]; then
    echo '{}' > "$SETTINGS"
    echo "Created $SETTINGS"
fi

# Back up existing settings
BACKUP="$SETTINGS.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "Backed up settings to: $BACKUP"

# ---------- Merge hooks using python3 ----------

python3 - "$SETTINGS" "$AIBRIDGE" << 'PYEOF'
import json
import sys
import os

settings_path = sys.argv[1]
aibridge = sys.argv[2]

# Read existing settings
with open(settings_path, "r") as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        settings = {}

if not isinstance(settings, dict):
    settings = {}

# AI Island hook definitions
# Claude Code pipes JSON on stdin to hook commands.
# aibridge reads stdin directly — no cat pipe needed.
# No trailing & needed — hooks run in a subprocess already.
# $PPID is the parent PID (the Claude Code process), stable across all hooks in a session.
# Using $$ would give a different PID per hook subprocess, creating duplicate sessions.
hook_defs = {
    "PreToolUse": {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": '{aibridge} --event tool_use --session "claude-$PPID" --agent claude --terminal-pid $PPID'.format(aibridge=aibridge)
            }
        ]
    },
    "PostToolUse": {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": '{aibridge} --event tool_result --session "claude-$PPID" --agent claude --terminal-pid $PPID'.format(aibridge=aibridge)
            }
        ]
    },
    "Notification": {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": '{aibridge} --event status --session "claude-$PPID" --agent claude --terminal-pid $PPID'.format(aibridge=aibridge)
            }
        ]
    },
}

MARKER = "aibridge"

def is_ai_island_hook(entry):
    """Check if a hook entry was installed by AI Island."""
    hooks = entry.get("hooks", [])
    for h in hooks:
        cmd = h.get("command", "")
        if MARKER in cmd:
            return True
    return False

# Merge hooks
existing_hooks = settings.get("hooks", {})
if not isinstance(existing_hooks, dict):
    existing_hooks = {}

for event_type, new_entry in hook_defs.items():
    entries = existing_hooks.get(event_type, [])
    if not isinstance(entries, list):
        entries = []

    # Remove existing AI Island hooks
    entries = [e for e in entries if not is_ai_island_hook(e)]

    # Add our hook
    entries.append(new_entry)

    existing_hooks[event_type] = entries

settings["hooks"] = existing_hooks

# Write back
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("Hooks merged successfully.")
PYEOF

echo ""
echo "=== Claude Code hooks installed ==="
echo ""
echo "Settings file: $SETTINGS"
echo "Backup:        $BACKUP"
echo ""
echo "Hooks installed for:"
echo "  - PreToolUse    (permission requests)"
echo "  - PostToolUse   (tool results)"
echo "  - Notification  (status updates)"

# ---------- Codex CLI hooks ----------

CODEX_CONFIG=""
for candidate in "$HOME/.codex/config.json" "$HOME/.config/codex/config.json"; do
    if [[ -f "$candidate" ]]; then
        CODEX_CONFIG="$candidate"
        break
    fi
done

# Also check if the directory exists (even without config.json)
if [[ -z "$CODEX_CONFIG" ]]; then
    for candidate_dir in "$HOME/.codex" "$HOME/.config/codex"; do
        if [[ -d "$candidate_dir" ]]; then
            CODEX_CONFIG="$candidate_dir/config.json"
            break
        fi
    done
fi

if [[ -n "$CODEX_CONFIG" ]]; then
    CODEX_DIR="$(dirname "$CODEX_CONFIG")"
    mkdir -p "$CODEX_DIR"

    if [[ ! -f "$CODEX_CONFIG" ]]; then
        echo '{}' > "$CODEX_CONFIG"
        echo "Created $CODEX_CONFIG"
    fi

    # Back up existing config
    CODEX_BACKUP="$CODEX_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CODEX_CONFIG" "$CODEX_BACKUP"
    echo ""
    echo "Backed up Codex config to: $CODEX_BACKUP"

    python3 - "$CODEX_CONFIG" "$AIBRIDGE" << 'CODEX_PYEOF'
import json
import sys

config_path = sys.argv[1]
aibridge = sys.argv[2]

with open(config_path, "r") as f:
    try:
        config = json.load(f)
    except json.JSONDecodeError:
        config = {}

if not isinstance(config, dict):
    config = {}

MARKER = "aibridge"

# Codex hook definitions (single dict per event, not arrays)
hook_defs = {
    "pre_tool_use": {
        "command": "{aibridge} --event permission_request --session $SESSION_ID --agent codex".format(aibridge=aibridge)
    },
    "post_tool_use": {
        "command": "{aibridge} --event tool_result --session $SESSION_ID --agent codex".format(aibridge=aibridge)
    },
    "on_status": {
        "command": "{aibridge} --event status --session $SESSION_ID --agent codex".format(aibridge=aibridge)
    },
}

hooks = config.get("hooks", {})
if not isinstance(hooks, dict):
    hooks = {}

for key, new_entry in hook_defs.items():
    existing = hooks.get(key)
    if existing is None:
        hooks[key] = new_entry
    elif isinstance(existing, list):
        # Filter out AI Island entries and append
        filtered = [e for e in existing if not (isinstance(e, dict) and MARKER in e.get("command", ""))]
        filtered.append(new_entry)
        hooks[key] = filtered
    elif isinstance(existing, dict):
        cmd = existing.get("command", "")
        if MARKER in cmd:
            # Replace our old hook
            hooks[key] = new_entry
        else:
            # User's hook — wrap both in array
            hooks[key] = [existing, new_entry]
    else:
        hooks[key] = new_entry

config["hooks"] = hooks

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")

print("Codex hooks merged successfully.")
CODEX_PYEOF

    echo ""
    echo "=== Codex CLI hooks installed ==="
    echo ""
    echo "Config file: $CODEX_CONFIG"
    echo "Backup:      $CODEX_BACKUP"
    echo ""
    echo "Hooks installed for:"
    echo "  - pre_tool_use  (permission requests)"
    echo "  - post_tool_use (tool results)"
    echo "  - on_status     (status updates)"
else
    echo ""
    echo "(Codex CLI not detected — skipping Codex hooks)"
fi

echo ""
echo "To verify Claude Code hooks, run:"
echo "  cat $SETTINGS | python3 -m json.tool"
echo ""
echo "To uninstall, restore the backup:"
echo "  cp $BACKUP $SETTINGS"
