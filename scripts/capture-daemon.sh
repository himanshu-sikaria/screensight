#!/bin/bash
# capture-daemon.sh — Screenshot daemon for screen-capture tool.
# Takes a JPEG screenshot every N seconds. Skips if idle, locked, display asleep,
# or frontmost app is in exclude list. Cleans up old captures.
#
# Reads config from ~/.screen-capture/config.yaml

# launchd PATH is minimal — make sure Homebrew python3 (where Quartz lives) is
# reachable so the CoreGraphics capture method is detected and used.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG_FILE="$HOME/.screen-capture/config.yaml"

# --- Simple YAML parser ---
parse_yaml_value() {
    local key="$1"
    local default="$2"
    local val
    # Try indented key first (nested under a section)
    val=$(grep "^  ${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/ *#.*//' | sed 's/.*: *//' | tr -d '"' || echo "")
    if [ -z "$val" ]; then
        # Try top-level key
        val=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/ *#.*//' | sed 's/.*: *//' | tr -d '"' || echo "")
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
            inline=$(echo "$line" | sed 's/ *#.*//' | sed "s/.*${key}: *//" | tr -d '[]"' | tr ',' '\n' | xargs)
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

parse_yaml_nested_list() {
    # Parse a list nested under a parent key, e.g., app_categories.private
    local parent="$1"
    local child="$2"
    local in_parent=false
    local in_child=false
    local result=""
    while IFS= read -r line; do
        if echo "$line" | grep -q "^  ${parent}:"; then
            in_parent=true
            continue
        fi
        if $in_parent; then
            if echo "$line" | grep -q "^    ${child}:"; then
                # Check for inline list: child: [a, b, c]
                local inline
                inline=$(echo "$line" | sed 's/ *#.*//' | sed "s/.*${child}: *//" | tr -d '[]"' | tr ',' '\n' | xargs)
                if [ -n "$inline" ] && [ "$inline" != "" ]; then
                    echo "$inline"
                    return
                fi
                in_child=true
                continue
            fi
            if $in_child; then
                if echo "$line" | grep -q "^      - "; then
                    local item
                    item=$(echo "$line" | sed 's/^      - //' | tr -d '"')
                    result="$result $item"
                elif echo "$line" | grep -qv "^$"; then
                    break
                fi
            fi
            # If we hit a new top-level or capture-level key, stop
            if echo "$line" | grep -q "^  [a-z]" && ! echo "$line" | grep -q "^    "; then
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
EXCLUDE_WINDOWS=$(parse_yaml_list "exclude_windows")
PRIVATE_APPS=$(parse_yaml_nested_list "app_categories" "private")

# Merge private apps into exclude list
if [ -n "$PRIVATE_APPS" ]; then
    EXCLUDE_APPS="$EXCLUDE_APPS $PRIVATE_APPS"
    EXCLUDE_APPS=$(echo "$EXCLUDE_APPS" | xargs)
fi

LOG_DIR="$OUTPUT_DIR/logs"
mkdir -p "$LOG_DIR"

CAPTURE_ERR_LOG="$LOG_DIR/capture-errors.log"
HEARTBEAT_FILE="/tmp/screen-capture.last-success"
BLANK_COUNTER_FILE="/tmp/screen-capture.blank-streak"
PERMISSION_ALERT_FILE="/tmp/screen-capture.permission-alerted"

# N consecutive blank captures triggers a user-visible notification.
# 10 x 30s = 5 minutes of blank output — long enough to rule out a brief
# black-screen edge case, short enough to catch a revoked TCC grant fast.
BLANK_ALERT_THRESHOLD=10

# Rotate a log file if it exceeds ~5MB. launchd appends via StandardOutPath;
# in-place truncate keeps its file descriptor valid.
rotate_log_if_large() {
    local f="$1"
    [ -f "$f" ] || return 0
    local size
    size=$(stat -f%z "$f" 2>/dev/null || echo "0")
    if [ "$size" -gt 5242880 ]; then
        cp "$f" "${f}.1" 2>/dev/null
        : > "$f"
    fi
}

log_line() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

notify_permission_lost() {
    [ -f "$PERMISSION_ALERT_FILE" ] && return 0
    touch "$PERMISSION_ALERT_FILE"
    log_line "ALERT: ${BLANK_ALERT_THRESHOLD}+ consecutive blank captures — Screen Recording permission likely revoked."
    log_line "       Re-grant at: System Settings → Privacy & Security → Screen Recording → ScreenCaptureDaemon"
    osascript -e 'display notification "Re-grant Screen Recording permission in System Settings → Privacy & Security → Screen Recording." with title "Screen capture stopped working" sound name "Basso"' 2>/dev/null || true
}

# Detect capture method: prefer CoreGraphics (works under launchd) over screencapture
CAPTURE_METHOD="screencapture"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if python3 -c "import Quartz" 2>/dev/null; then
    CAPTURE_METHOD="coregraphics"
fi

PIDFILE="/tmp/screen-capture.pid"
PAUSEFILE="/tmp/screen-capture.paused"

# --- Prevent duplicate instances ---
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Already running (PID $(cat "$PIDFILE")). Exiting."
    exit 0
fi
echo $$ > "$PIDFILE"
# Clear any stale permission-alert latch from a prior run so a fresh daemon can notify again.
rm -f "$PERMISSION_ALERT_FILE"
trap 'rm -f "$PIDFILE"; exit 0' INT TERM EXIT

log_line "Screen capture running (PID $$) — method=$CAPTURE_METHOD"
log_line "  Interval: ${INTERVAL}s | Idle timeout: ${IDLE_LIMIT_MIN}m | Quality: $QUALITY"
log_line "  Captures: $CAPTURE_DIR/YYYY-MM-DD/"
log_line "  Retention: ${RETENTION_DAYS} days"
if [ -n "$EXCLUDE_APPS" ]; then
    log_line "  Excluded apps: $EXCLUDE_APPS"
fi
if [ -n "$EXCLUDE_WINDOWS" ]; then
    log_line "  Excluded window patterns: $EXCLUDE_WINDOWS"
fi

LAST_CLEANUP_DAY=""
LAST_LOG_ROTATE_DAY=""

while true; do
    # --- Guard: paused ---
    if [ -f "$PAUSEFILE" ]; then
        sleep "$INTERVAL"
        continue
    fi

    # --- Cleanup once per new day ---
    TODAY=$(date +%Y-%m-%d)
    if [ "$TODAY" != "$LAST_CLEANUP_DAY" ]; then
        if [ -d "$CAPTURE_DIR" ]; then
            find "$CAPTURE_DIR" -type d -mindepth 1 -maxdepth 1 -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null
        fi
        LAST_CLEANUP_DAY="$TODAY"
    fi

    # --- Rotate logs once per new day (cheap; skips if under threshold) ---
    if [ "$TODAY" != "$LAST_LOG_ROTATE_DAY" ]; then
        rotate_log_if_large "$LOG_DIR/capture.log"
        rotate_log_if_large "$LOG_DIR/capture.err"
        rotate_log_if_large "$CAPTURE_ERR_LOG"
        LAST_LOG_ROTATE_DAY="$TODAY"
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

    # --- Get frontmost app (reused for exclusion check + metadata) ---
    FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")

    # --- Guard: excluded app in foreground ---
    if [ -n "$EXCLUDE_APPS" ]; then
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

    # Capture stderr from the capture tool; a non-empty stderr usually means
    # "CGWindowListCreateImage returned nil" (permission revoked) or similar.
    if [ "$CAPTURE_METHOD" = "coregraphics" ]; then
        CAPTURE_STDERR=$(python3 "$SCRIPT_DIR/capture-screen.py" "$DIR/${TS}.png" 2>&1 >/dev/null) || true
    else
        CAPTURE_STDERR=$(/usr/sbin/screencapture -x "$DIR/${TS}.png" 2>&1 >/dev/null) || true
    fi
    if [ -n "$CAPTURE_STDERR" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $CAPTURE_METHOD: $CAPTURE_STDERR" >> "$CAPTURE_ERR_LOG"
    fi

    BLANK_STREAK=$(cat "$BLANK_COUNTER_FILE" 2>/dev/null || echo "0")
    BLANK_STREAK=${BLANK_STREAK//[^0-9]/}
    BLANK_STREAK=${BLANK_STREAK:-0}

    if [ -s "$DIR/${TS}.png" ]; then
        /usr/bin/sips -Z "$WIDTH" "$DIR/${TS}.png" --out "$DIR/${TS}.png" >/dev/null 2>&1
        /usr/bin/sips -s format jpeg -s formatOptions "$QUALITY" "$DIR/${TS}.png" --out "$DIR/${TS}.jpg" >/dev/null 2>&1
        rm -f "$DIR/${TS}.png"

        # Discard black/blank screenshots
        FSIZE=$(stat -f%z "$DIR/${TS}.jpg" 2>/dev/null || echo "0")
        if [ "$FSIZE" -lt "$MIN_FILE_SIZE" ]; then
            rm -f "$DIR/${TS}.jpg"
            BLANK_STREAK=$((BLANK_STREAK + 1))
            echo "$BLANK_STREAK" > "$BLANK_COUNTER_FILE"
            if [ "$BLANK_STREAK" -ge "$BLANK_ALERT_THRESHOLD" ]; then
                notify_permission_lost
            fi
        else
            # --- Write metadata sidecar ---
            META_TITLE=$(osascript -e 'tell application "System Events" to get title of front window of (first application process whose frontmost is true)' 2>/dev/null || echo "")

            # --- Guard: excluded window title pattern (case-insensitive glob) ---
            if [ -n "$EXCLUDE_WINDOWS" ] && [ -n "$META_TITLE" ]; then
                TITLE_LOWER=$(echo "$META_TITLE" | tr '[:upper:]' '[:lower:]')
                WINDOW_SKIP=false
                for PATTERN in $EXCLUDE_WINDOWS; do
                    PAT_LOWER=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]')
                    # Use bash case for glob matching
                    case "$TITLE_LOWER" in
                        $PAT_LOWER)
                            WINDOW_SKIP=true
                            break
                            ;;
                    esac
                done
                if $WINDOW_SKIP; then
                    rm -f "$DIR/${TS}.jpg"
                    sleep "$INTERVAL"
                    continue
                fi
            fi

            META_URL=""
            case "$FRONTMOST" in
                Safari) META_URL=$(osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null || echo "") ;;
                "Google Chrome") META_URL=$(osascript -e 'tell application "Google Chrome" to get URL of active tab of front window' 2>/dev/null || echo "") ;;
                Arc) META_URL=$(osascript -e 'tell application "Arc" to get URL of active tab of front window' 2>/dev/null || echo "") ;;
                Firefox) META_URL=$(osascript -e 'tell application "Firefox" to get URL of front document' 2>/dev/null || echo "") ;;
                "Microsoft Edge") META_URL=$(osascript -e 'tell application "Microsoft Edge" to get URL of active tab of front window' 2>/dev/null || echo "") ;;
            esac
            META_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            # Escape backslashes and double quotes for valid JSON
            META_TITLE=$(printf '%s' "$META_TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')
            META_URL=$(printf '%s' "$META_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')
            FRONTMOST_ESC=$(printf '%s' "$FRONTMOST" | sed 's/\\/\\\\/g; s/"/\\"/g')
            printf '{"app":"%s","window_title":"%s","url":"%s","timestamp":"%s"}\n' \
                "$FRONTMOST_ESC" "$META_TITLE" "$META_URL" "$META_TS" > "$DIR/${TS}.meta.json"

            # Success — clear blank streak, update heartbeat, re-arm permission alert.
            if [ "$BLANK_STREAK" -gt 0 ]; then
                echo "0" > "$BLANK_COUNTER_FILE"
                rm -f "$PERMISSION_ALERT_FILE"
            fi
            date +%s > "$HEARTBEAT_FILE"
        fi
    else
        # Capture tool failed entirely (returned nil image / no file produced).
        # Treat as a blank for streak-accounting purposes so the permission alert fires.
        rm -f "$DIR/${TS}.png"
        BLANK_STREAK=$((BLANK_STREAK + 1))
        echo "$BLANK_STREAK" > "$BLANK_COUNTER_FILE"
        if [ "$BLANK_STREAK" -ge "$BLANK_ALERT_THRESHOLD" ]; then
            notify_permission_lost
        fi
    fi

    sleep "$INTERVAL"
done
