#!/bin/bash
# capture-daemon.sh — Screenshot daemon for screen-capture tool.
# Takes a JPEG screenshot every N seconds. Skips if idle, locked, display asleep,
# or frontmost app is in exclude list. Cleans up old captures.
#
# Reads config from ~/.screen-capture/config.yaml

CONFIG_FILE="$HOME/.screen-capture/config.yaml"

# --- Simple YAML parser ---
parse_yaml_value() {
    local key="$1"
    local default="$2"
    local val
    # Try indented key first (nested under a section)
    val=$(grep "^  ${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || echo "")
    if [ -z "$val" ]; then
        # Try top-level key
        val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || echo "")
    fi
    echo "${val:-$default}"
}

parse_yaml_list() {
    local key="$1"
    local in_section=false
    local result=""
    while IFS= read -r line; do
        if echo "$line" | grep -q "^  ${key}:"; then
            # Check for inline list: key: [a, b, c]
            local inline
            inline=$(echo "$line" | sed "s/.*${key}: *//" | tr -d '[]"' | tr ',' '\n' | xargs)
            if [ -n "$inline" ] && [ "$inline" != "" ]; then
                echo "$inline"
                return
            fi
            in_section=true
            continue
        fi
        if $in_section; then
            if echo "$line" | grep -q "^    - "; then
                local item
                item=$(echo "$line" | sed 's/^    - //' | tr -d '"')
                result="$result $item"
            elif echo "$line" | grep -q "^  [a-z]"; then
                break
            fi
        fi
    done < "$CONFIG_FILE"
    echo "$result" | xargs
}

# --- Load config ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found: $CONFIG_FILE"
    echo "Run install.sh first."
    exit 1
fi

INTERVAL=$(parse_yaml_value "interval_seconds" "30")
IDLE_LIMIT_MIN=$(parse_yaml_value "idle_timeout_minutes" "30")
IDLE_LIMIT=$(( IDLE_LIMIT_MIN * 60 ))
RETENTION_DAYS=$(parse_yaml_value "retention_days" "7")
QUALITY=$(parse_yaml_value "quality" "30")
WIDTH=$(parse_yaml_value "width" "1280")
MIN_FILE_SIZE=30000

OUTPUT_DIR=$(parse_yaml_value "directory" "$HOME/screen-capture")
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
CAPTURE_DIR="$OUTPUT_DIR/raw"

EXCLUDE_APPS=$(parse_yaml_list "exclude_apps")

PIDFILE="/tmp/screen-capture.pid"

# --- Prevent duplicate instances ---
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Already running (PID $(cat "$PIDFILE")). Exiting."
    exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT

echo "Screen capture running (PID $$)"
echo "  Interval: ${INTERVAL}s | Idle timeout: ${IDLE_LIMIT_MIN}m | Quality: $QUALITY"
echo "  Captures: $CAPTURE_DIR/YYYY-MM-DD/"
echo "  Retention: ${RETENTION_DAYS} days"
if [ -n "$EXCLUDE_APPS" ]; then
    echo "  Excluded apps: $EXCLUDE_APPS"
fi

LAST_CLEANUP_DAY=""

while true; do
    # --- Cleanup once per new day ---
    TODAY=$(date +%Y-%m-%d)
    if [ "$TODAY" != "$LAST_CLEANUP_DAY" ]; then
        if [ -d "$CAPTURE_DIR" ]; then
            find "$CAPTURE_DIR" -type d -mindepth 1 -maxdepth 1 -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null
        fi
        LAST_CLEANUP_DAY="$TODAY"
    fi

    # --- Guard: idle ---
    IDLE_NS=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/{gsub(/[^0-9]/,"",$NF); print $NF}' || echo "0")
    IDLE_SEC=$(( ${IDLE_NS:-0} / 1000000000 ))
    if [ "$IDLE_SEC" -gt "$IDLE_LIMIT" ]; then
        sleep "$INTERVAL"
        continue
    fi

    # --- Guard: screen locked ---
    LOCKED=$(/usr/libexec/PlistBuddy -c "Print :IOConsoleUsers:0:CGSSessionScreenIsLocked" /dev/stdin 2>/dev/null <<< "$(ioreg -n Root -d1 -a 2>/dev/null)" || echo "false")
    if [ "$LOCKED" = "true" ]; then
        sleep "$INTERVAL"
        continue
    fi

    # --- Guard: display asleep ---
    if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Display Asleep: Yes"; then
        sleep "$INTERVAL"
        continue
    fi

    # --- Guard: excluded app in foreground ---
    if [ -n "$EXCLUDE_APPS" ]; then
        FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
        SKIP=false
        for APP in $EXCLUDE_APPS; do
            if [ "$FRONTMOST" = "$APP" ]; then
                SKIP=true
                break
            fi
        done
        if $SKIP; then
            sleep "$INTERVAL"
            continue
        fi
    fi

    # --- Capture ---
    DIR="$CAPTURE_DIR/$TODAY"
    mkdir -p "$DIR"
    TS=$(date +%H-%M-%S)

    /usr/sbin/screencapture -x "$DIR/${TS}.png" 2>/dev/null

    if [ -s "$DIR/${TS}.png" ]; then
        /usr/bin/sips -Z "$WIDTH" "$DIR/${TS}.png" --out "$DIR/${TS}.png" >/dev/null 2>&1
        /usr/bin/sips -s format jpeg -s formatOptions "$QUALITY" "$DIR/${TS}.png" --out "$DIR/${TS}.jpg" >/dev/null 2>&1
        rm -f "$DIR/${TS}.png"

        # Discard black/blank screenshots
        FSIZE=$(stat -f%z "$DIR/${TS}.jpg" 2>/dev/null || echo "0")
        if [ "$FSIZE" -lt "$MIN_FILE_SIZE" ]; then
            rm -f "$DIR/${TS}.jpg"
        fi
    else
        rm -f "$DIR/${TS}.png"
    fi

    sleep "$INTERVAL"
done
