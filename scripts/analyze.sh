#!/bin/bash
# analyze.sh — Triggers Claude Code analysis for screen captures.
# Runs via LaunchAgent on schedule + on login (catch-up).
# Idempotent: skips if digest.md already exists for a given date.

CONFIG_FILE="$HOME/.screen-capture/config.yaml"
SKILL_FILE="$HOME/.claude/skills/screen-analysis/SKILL.md"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Simple YAML parser ---
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

# --- Preflight checks ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found: $CONFIG_FILE — run install.sh first"
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo "Claude Code CLI not found. Install: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

if [ ! -f "$SKILL_FILE" ]; then
    echo "Analysis skill not found: $SKILL_FILE — run install.sh first"
    exit 1
fi

# --- Load config ---
OUTPUT_DIR=$(parse_yaml_value "directory" "$HOME/screen-capture")
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
RAW_DIR="$OUTPUT_DIR/raw"
MODEL=$(parse_yaml_value "model" "opus")
LOG_DIR="$OUTPUT_DIR/logs"
mkdir -p "$LOG_DIR"

# --- Check schedule ---
SCHEDULE_DAYS=$(parse_yaml_value "schedule_days" "1,2,3,4,5")
TODAY_DOW=$(date +%u)  # 1=Monday, 7=Sunday

# Only run on scheduled days (skip catch-up check for non-scheduled days)
is_scheduled_day() {
    local day="$1"
    echo "$SCHEDULE_DAYS" | tr ',' '\n' | grep -q "^${day}$"
}

# --- Analysis function ---
analyze_date() {
    local DATE="$1"
    local RAW_DATE_DIR="$RAW_DIR/$DATE"
    local OUTPUT_DATE_DIR="$OUTPUT_DIR/$DATE"
    local DIGEST="$OUTPUT_DATE_DIR/digest.md"

    # Skip if no raw screenshots exist
    if [ ! -d "$RAW_DATE_DIR" ] || [ -z "$(ls "$RAW_DATE_DIR"/*.jpg 2>/dev/null)" ]; then
        echo "[$DATE] No screenshots found. Skipping."
        return 0
    fi

    # Skip if analysis already ran (idempotent)
    if [ -f "$DIGEST" ]; then
        echo "[$DATE] Analysis already exists. Skipping."
        return 0
    fi

    echo "[$DATE] Running analysis..."
    mkdir -p "$OUTPUT_DATE_DIR"
    mkdir -p "$OUTPUT_DIR/processes"

    local LOG_FILE="$LOG_DIR/analysis-$DATE.log"

    # Build the prompt with all necessary context
    local PROMPT="Run screen analysis for date $DATE.

Config file: $CONFIG_FILE
Raw screenshots directory: $RAW_DATE_DIR/
Output directory: $OUTPUT_DATE_DIR/
Process files directory: $OUTPUT_DIR/processes/

Read the config file first to understand the user's role, focus areas, and coaching priorities.
Then analyze the screenshots and produce all output files."

    # Run Claude Code with the analysis skill
    claude --model "$MODEL" \
        --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
        -p "$PROMPT" \
        >> "$LOG_FILE" 2>&1

    if [ -f "$DIGEST" ]; then
        echo "[$DATE] Analysis complete. Output: $OUTPUT_DATE_DIR/"
    else
        echo "[$DATE] Analysis may have failed — no digest.md produced."
        echo "         Check log: $LOG_FILE"
    fi
}

# --- Run analysis ---
echo "=== Screen Capture Analysis — $(date) ==="

# Today
TODAY=$(date +%Y-%m-%d)
if is_scheduled_day "$TODAY_DOW"; then
    analyze_date "$TODAY"
fi

# Catch-up: yesterday
YESTERDAY=$(date -v-1d +%Y-%m-%d)
YESTERDAY_DOW=$(date -v-1d +%u)
if is_scheduled_day "$YESTERDAY_DOW"; then
    analyze_date "$YESTERDAY"
fi

# Catch-up: day before yesterday (handles weekends / multi-day laptop off)
DAY_BEFORE=$(date -v-2d +%Y-%m-%d)
DAY_BEFORE_DOW=$(date -v-2d +%u)
if is_scheduled_day "$DAY_BEFORE_DOW"; then
    analyze_date "$DAY_BEFORE"
fi

echo "=== Done ==="
