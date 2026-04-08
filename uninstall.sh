#!/bin/bash
# uninstall.sh — Removes screen-capture tool completely.

set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
CONFIG_DIR="$HOME/.screen-capture"
SKILL_DIR="$HOME/.claude/skills/screen-analysis"
OUTPUT_DIR="$HOME/screen-capture"

echo "=== Screen Capture — Uninstaller ==="
echo ""

# --- Stop and remove LaunchAgents ---
for PLIST in "com.screen-capture.daemon" "com.screen-capture.analyze" "com.screen-capture.menubar"; do
    PLIST_FILE="$LAUNCH_AGENTS_DIR/${PLIST}.plist"
    if [ -f "$PLIST_FILE" ]; then
        launchctl unload "$PLIST_FILE" 2>/dev/null || true
        rm -f "$PLIST_FILE"
        echo "Removed: $PLIST_FILE"
    fi
done

# --- Remove PID file ---
rm -f /tmp/screen-capture.pid

# --- Remove skill ---
if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    echo "Removed skill: $SKILL_DIR"
fi

# --- Remove config ---
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "Removed config: $CONFIG_DIR"
fi

# --- Optionally remove data ---
if [ -d "$OUTPUT_DIR" ]; then
    echo ""
    read -rp "Remove all captured data at $OUTPUT_DIR? [y/N]: " REMOVE_DATA
    if [[ "$REMOVE_DATA" == "y" || "$REMOVE_DATA" == "Y" ]]; then
        rm -rf "$OUTPUT_DIR"
        echo "Removed data: $OUTPUT_DIR"
    else
        echo "Kept data at: $OUTPUT_DIR"
    fi
fi

echo ""
echo "Uninstall complete."
