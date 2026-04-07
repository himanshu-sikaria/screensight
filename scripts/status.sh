#!/bin/bash
# status.sh — Diagnostic status for screen-capture system.
# Shows daemon state, today's captures, last analysis, config summary, and LaunchAgent status.

CONFIG_FILE="$HOME/.screen-capture/config.yaml"

# --- Simple YAML parser (matches capture-daemon.sh) ---
parse_yaml_value() {
    local key="$1"
    local default="$2"
    local val
    val=$(grep "^  ${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || echo "")
    if [ -z "$val" ]; then
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

# --- Preflight ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found: $CONFIG_FILE — run install.sh first"
    exit 1
fi

# --- Load config ---
OUTPUT_DIR=$(parse_yaml_value "directory" "$HOME/screen-capture")
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
RAW_DIR="$OUTPUT_DIR/raw"
ROLE=$(parse_yaml_value "role" "not set")
MODEL=$(parse_yaml_value "model" "opus")
SCHEDULE_TIME=$(parse_yaml_value "schedule_time" "not set")
SCHEDULE_DAYS=$(parse_yaml_value "schedule_days" "1,2,3,4,5")
EXCLUDE_APPS=$(parse_yaml_list "exclude_apps")

TODAY=$(date +%Y-%m-%d)
PIDFILE="/tmp/screen-capture.pid"

echo "=== Screen Capture Status ==="
echo ""

# --- Daemon status ---
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Daemon:     Running (PID $(cat "$PIDFILE"))"
else
    echo "Daemon:     Not running"
fi

# --- Today's screenshots ---
TODAY_DIR="$RAW_DIR/$TODAY"
if [ -d "$TODAY_DIR" ]; then
    COUNT=$(ls "$TODAY_DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
    SIZE=$(du -sh "$TODAY_DIR" 2>/dev/null | awk '{print $1}')
    echo "Today:      ${COUNT} screenshots (${SIZE}) in ${TODAY_DIR/$HOME/~}/"
else
    echo "Today:      No screenshots yet"
fi

# --- Last analysis ---
LAST_DIGEST=""
LAST_DATE=""
# Search output dir for most recent digest.md (excluding raw/)
for d in $(ls -1rd "$OUTPUT_DIR"/*/digest.md 2>/dev/null); do
    LAST_DIGEST="$d"
    LAST_DATE=$(basename "$(dirname "$d")")
    break
done
if [ -n "$LAST_DIGEST" ]; then
    echo "Last analysis: ${LAST_DATE} (${LAST_DIGEST/$HOME/~})"
else
    echo "Last analysis: None found"
fi

echo ""
echo "Config:"
echo "  Role:     $ROLE"
echo "  Model:    $MODEL"
echo "  Schedule: ${SCHEDULE_TIME}, days ${SCHEDULE_DAYS}"
if [ -n "$EXCLUDE_APPS" ]; then
    echo "  Excluded: $(echo "$EXCLUDE_APPS" | tr ' ' ', ')"
else
    echo "  Excluded: (none)"
fi

echo ""
echo "LaunchAgents:"

# --- LaunchAgent status ---
if launchctl list 2>/dev/null | grep -q "com.screen-capture.daemon"; then
    echo "  Capture:  loaded"
else
    echo "  Capture:  not loaded"
fi

if launchctl list 2>/dev/null | grep -q "com.screen-capture.analyze"; then
    echo "  Analysis: loaded"
else
    echo "  Analysis: not loaded"
fi
