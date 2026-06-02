#!/bin/bash
# install.sh — One-command installer for screen-capture tool.
# Installs capture daemon, analysis trigger, Claude Code skill, and config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.screen-capture"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SKILL_DIR="$HOME/.claude/skills/screen-analysis"
SUPPORT_SKILL_DIR="$HOME/.claude/skills/support-ticket-analysis"
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

# --- Install Python capture dependency (for launchd compatibility) ---
# Pin to the same python3 the daemon will resolve under launchd. capture-daemon.sh
# exports PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" before invoking python3,
# so the install target is the first python3 found along that same order.
DAEMON_PYTHON=""
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [ -x "$candidate" ]; then
        DAEMON_PYTHON="$candidate"
        break
    fi
done

if [ -z "$DAEMON_PYTHON" ]; then
    echo "Warning: No python3 found in /opt/homebrew/bin, /usr/local/bin, or /usr/bin."
    echo "  Capture will use /usr/sbin/screencapture (may fail under launchd on macOS 15+)."
else
    echo "Using python3 for CoreGraphics capture: $DAEMON_PYTHON"
    if "$DAEMON_PYTHON" -c "import Quartz" 2>/dev/null; then
        echo "CoreGraphics capture: ready (pyobjc-framework-Quartz already installed)"
    else
        echo "Installing pyobjc-framework-Quartz into $DAEMON_PYTHON..."
        if "$DAEMON_PYTHON" -m pip install pyobjc-framework-Quartz --break-system-packages 2>/dev/null; then
            if "$DAEMON_PYTHON" -c "import Quartz" 2>/dev/null; then
                echo "CoreGraphics capture: installed"
            else
                echo "Warning: pip succeeded but import still fails. Check $DAEMON_PYTHON config."
            fi
        else
            echo "Warning: Could not install pyobjc-framework-Quartz into $DAEMON_PYTHON."
            echo "  Capture will use /usr/sbin/screencapture (may fail under launchd on macOS 15+)."
            echo "  To fix manually: $DAEMON_PYTHON -m pip install pyobjc-framework-Quartz --break-system-packages"
        fi
    fi
fi

# --- Choose template ---
echo "Choose your role (pre-fills config with relevant defaults):"
echo ""
echo "  [1] Engineering (IC or manager)"
echo "  [2] Product Manager"
echo "  [3] Customer Success / CX"
echo "  [4] Sales / GTM"
echo "  [5] Support Engineer (ticket-centric analysis)"
echo "  [6] Custom (blank config)"
echo ""
read -rp "Enter choice [1-6]: " CHOICE

case "$CHOICE" in
    1) TEMPLATE="$SCRIPT_DIR/configs/templates/engineering.yaml" ;;
    2) TEMPLATE="$SCRIPT_DIR/configs/templates/product.yaml" ;;
    3) TEMPLATE="$SCRIPT_DIR/configs/templates/customer-success.yaml" ;;
    4) TEMPLATE="$SCRIPT_DIR/configs/templates/sales.yaml" ;;
    5) TEMPLATE="$SCRIPT_DIR/configs/templates/support.yaml" ;;
    6) TEMPLATE="$SCRIPT_DIR/configs/default.yaml" ;;
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

# Install support-ticket skill if persona: support is set in the active config
PERSONA=$(grep "^persona:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || echo "")
if [ "$PERSONA" = "support" ] && [ -f "$SCRIPT_DIR/skill/support/SKILL.md" ]; then
    mkdir -p "$SUPPORT_SKILL_DIR"
    cp "$SCRIPT_DIR/skill/support/SKILL.md" "$SUPPORT_SKILL_DIR/SKILL.md"
    echo "Support skill installed: $SUPPORT_SKILL_DIR/SKILL.md"
fi

# --- Create output directories ---
mkdir -p "$OUTPUT_DIR/raw"
mkdir -p "$OUTPUT_DIR/processes"
mkdir -p "$OUTPUT_DIR/logs"
echo "Output directory: $OUTPUT_DIR/"

# --- Make scripts executable ---
chmod +x "$SCRIPT_DIR/scripts/capture-daemon.sh"
chmod +x "$SCRIPT_DIR/scripts/analyze.sh"
chmod +x "$SCRIPT_DIR/scripts/capture-screen.py"
[ -f "$SCRIPT_DIR/scripts/review-ticket.sh" ] && chmod +x "$SCRIPT_DIR/scripts/review-ticket.sh"
[ -f "$SCRIPT_DIR/scripts/publish.sh" ] && chmod +x "$SCRIPT_DIR/scripts/publish.sh"

# --- Create app bundle for Screen Recording TCC ---
# macOS grants Screen Recording permission to app bundles, not raw binaries.
# launchd runs /bin/bash directly, which has no app bundle, so screencapture
# fails with "could not create image from display." This wrapper app gives
# macOS a named entity to grant permission to.
APP_DIR="$HOME/Applications/ScreenCaptureDaemon.app"
echo "Creating app bundle: $APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>run</string>
    <key>CFBundleIdentifier</key>
    <string>com.screen-capture.daemon</string>
    <key>CFBundleName</key>
    <string>ScreenCaptureDaemon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

cat > "$APP_DIR/Contents/MacOS/run" << WRAPPER
#!/bin/bash
exec "$SCRIPT_DIR/scripts/capture-daemon.sh"
WRAPPER
chmod +x "$APP_DIR/Contents/MacOS/run"

# Ad-hoc sign so macOS recognizes it for TCC
codesign -s - -f "$APP_DIR" 2>/dev/null || true

# --- Install LaunchAgents ---
mkdir -p "$LAUNCH_AGENTS_DIR"

# Capture daemon plist — replace placeholders
sed -e "s|INSTALL_PATH|$SCRIPT_DIR|g" \
    -e "s|APP_BUNDLE_PATH|$APP_DIR|g" \
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
echo "Opening System Settings and revealing the app bundle in Finder now..."
echo ""
echo "  1. Click the '+' button in System Settings → Screen Recording"
echo "  2. Either:"
echo "     (a) Drag ScreenCaptureDaemon.app from the Finder window I just opened"
echo "         directly into the Screen Recording list, OR"
echo "     (b) In the file picker, press Cmd+Shift+G, paste ~/Applications,"
echo "         press Enter, then select ScreenCaptureDaemon.app"
echo "  3. Toggle it ON"
echo ""
echo "  Why the file picker can't find it by default: macOS defaults to"
echo "  /Applications (system-wide), but the bundle is in ~/Applications"
echo "  (user-level) — both are valid Apple-recognized locations."
echo ""
echo "  Note: On macOS 15+, granting permission to Terminal/iTerm alone is"
echo "  not sufficient. The launchd daemon runs outside any terminal app, so"
echo "  it needs its own Screen Recording entry via the app bundle above."
echo ""
open -R "$APP_DIR" 2>/dev/null || true
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
