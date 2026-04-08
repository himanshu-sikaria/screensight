#!/bin/bash
# install.sh — One-command installer for screen-capture tool.
# Installs capture daemon, analysis trigger, Claude Code skill, and config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.screen-capture"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SKILL_DIR="$HOME/.claude/skills/screen-analysis"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
OUTPUT_DIR="$HOME/screen-capture"

echo "=== Screen Capture — Installer ==="
echo ""

# --- Check prerequisites ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This tool only works on macOS."
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo "Error: Claude Code CLI not found."
    echo "Install it first: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

if ! command -v screencapture &>/dev/null; then
    echo "Error: screencapture command not found."
    exit 1
fi

# --- Choose template ---
echo "Choose your role (pre-fills config with relevant defaults):"
echo ""
echo "  [1] Engineering (IC or manager)"
echo "  [2] Product Manager"
echo "  [3] Customer Success / CX"
echo "  [4] Sales / GTM"
echo "  [5] Custom (blank config)"
echo ""
read -rp "Enter choice [1-5]: " CHOICE

case "$CHOICE" in
    1) TEMPLATE="$SCRIPT_DIR/configs/templates/engineering.yaml" ;;
    2) TEMPLATE="$SCRIPT_DIR/configs/templates/product.yaml" ;;
    3) TEMPLATE="$SCRIPT_DIR/configs/templates/customer-success.yaml" ;;
    4) TEMPLATE="$SCRIPT_DIR/configs/templates/sales.yaml" ;;
    5) TEMPLATE="$SCRIPT_DIR/configs/default.yaml" ;;
    *) echo "Invalid choice. Using default."; TEMPLATE="$SCRIPT_DIR/configs/default.yaml" ;;
esac

# --- Install config ---
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_FILE" ]; then
    read -rp "Config already exists at $CONFIG_FILE. Overwrite? [y/N]: " OVERWRITE
    if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
        echo "Keeping existing config."
    else
        cp "$TEMPLATE" "$CONFIG_FILE"
        echo "Config written: $CONFIG_FILE"
    fi
else
    cp "$TEMPLATE" "$CONFIG_FILE"
    echo "Config written: $CONFIG_FILE"
fi

# --- Read schedule_hour from config for plist ---
SCHEDULE_HOUR=$(grep "^  schedule_hour:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || echo "23")

# --- Install Claude Code skill ---
mkdir -p "$SKILL_DIR"
cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "Skill installed: $SKILL_DIR/SKILL.md"

# --- Create output directories ---
mkdir -p "$OUTPUT_DIR/raw"
mkdir -p "$OUTPUT_DIR/processes"
mkdir -p "$OUTPUT_DIR/logs"
echo "Output directory: $OUTPUT_DIR/"

# --- Make scripts executable ---
chmod +x "$SCRIPT_DIR/scripts/capture-daemon.sh"
chmod +x "$SCRIPT_DIR/scripts/analyze.sh"

# --- Install LaunchAgents ---
mkdir -p "$LAUNCH_AGENTS_DIR"

# Capture daemon plist — replace placeholders
sed -e "s|INSTALL_PATH|$SCRIPT_DIR|g" \
    -e "s|LOG_PATH|$OUTPUT_DIR/logs|g" \
    "$SCRIPT_DIR/scripts/com.screen-capture.plist" \
    > "$LAUNCH_AGENTS_DIR/com.screen-capture.daemon.plist"

# Analysis trigger plist — replace placeholders including schedule hour
sed -e "s|INSTALL_PATH|$SCRIPT_DIR|g" \
    -e "s|LOG_PATH|$OUTPUT_DIR/logs|g" \
    -e "s|SCHEDULE_HOUR|$SCHEDULE_HOUR|g" \
    "$SCRIPT_DIR/scripts/com.screen-capture.analyze.plist" \
    > "$LAUNCH_AGENTS_DIR/com.screen-capture.analyze.plist"

# Load LaunchAgents
launchctl unload "$LAUNCH_AGENTS_DIR/com.screen-capture.daemon.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/com.screen-capture.daemon.plist"

launchctl unload "$LAUNCH_AGENTS_DIR/com.screen-capture.analyze.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/com.screen-capture.analyze.plist"

echo "LaunchAgents installed and loaded."

# --- Menu bar app (optional, requires rumps) ---
if python3 -c "import rumps" 2>/dev/null; then
    sed -e "s|INSTALL_PATH|$SCRIPT_DIR|g" \
        -e "s|LOG_PATH|$OUTPUT_DIR/logs|g" \
        "$SCRIPT_DIR/scripts/com.screen-capture.menubar.plist" \
        > "$LAUNCH_AGENTS_DIR/com.screen-capture.menubar.plist"
    launchctl unload "$LAUNCH_AGENTS_DIR/com.screen-capture.menubar.plist" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENTS_DIR/com.screen-capture.menubar.plist"
    echo "Menu bar app installed (shows capture status, pause/resume)."
else
    echo ""
    echo "Optional: Install the menu bar app for status indicator + pause/resume:"
    echo "  pip3 install rumps --break-system-packages"
    echo "  Then re-run ./install.sh"
fi

# --- Screen Recording permission ---
echo ""
echo "=== IMPORTANT: Grant Screen Recording Permission ==="
echo ""
echo "macOS requires you to manually grant Screen Recording access."
echo "Opening System Preferences now..."
echo ""
echo "  1. Find 'Terminal' (or 'iTerm') in the list"
echo "  2. Toggle it ON"
echo "  3. You may need to restart Terminal after granting"
echo ""
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

# --- Done ---
echo ""
echo "=== Installation Complete ==="
echo ""
echo "  Capture is running now (screenshot every 30 seconds)."
echo "  Analysis runs nightly at ${SCHEDULE_HOUR}:00 (or on next login if laptop was closed)."
echo ""
echo "  Config:      $CONFIG_FILE"
echo "  Screenshots: $OUTPUT_DIR/raw/YYYY-MM-DD/"
echo "  Analysis:    $OUTPUT_DIR/YYYY-MM-DD/"
echo "  Processes:   $OUTPUT_DIR/processes/"
echo "  Logs:        $OUTPUT_DIR/logs/"
echo ""
echo "  Edit $CONFIG_FILE to customize role, coaching areas, and capture settings."
echo ""
