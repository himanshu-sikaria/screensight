#!/bin/bash
# analyze.sh — Triggers Claude Code analysis for screen captures.
# Runs via LaunchAgent on schedule + on login (catch-up).
# Idempotent: skips if digest.md already exists for a given date.

# launchd uses a minimal PATH that may not include ~/.local/bin (Claude Code)
# or /opt/homebrew/bin (Homebrew). Ensure they are available.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

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
PERSONA=$(parse_yaml_value "persona" "")
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

    mkdir -p "$OUTPUT_DATE_DIR"
    mkdir -p "$OUTPUT_DIR/processes"

    # --- Base pass: day-level analysis (idempotent on digest.md) ---
    if [ -f "$DIGEST" ]; then
        echo "[$DATE] Base analysis already exists. Skipping base pass."
    else
        echo "[$DATE] Running base analysis..."
        local LOG_FILE="$LOG_DIR/analysis-$DATE.log"

        local PROMPT="Run screen analysis for date $DATE.

Config file: $CONFIG_FILE
Raw screenshots directory: $RAW_DATE_DIR/
Output directory: $OUTPUT_DATE_DIR/
Process files directory: $OUTPUT_DIR/processes/

Read the config file first to understand the user's role, focus areas, and coaching priorities.
Then analyze the screenshots and produce all output files."

        local TOOLS="Read,Write,Edit,Glob,Grep,Bash"
        local MEETING_SOURCE
        MEETING_SOURCE=$(parse_yaml_value "meeting_source" "none")
        if [ "$MEETING_SOURCE" = "granola" ]; then
            TOOLS="$TOOLS,mcp__claude_ai_Granola__list_meetings,mcp__claude_ai_Granola__get_meetings,mcp__claude_ai_Granola__get_meeting_transcript,mcp__claude_ai_Granola__query_granola_meetings"
        fi

        claude --model "$MODEL" \
            --allowedTools "$TOOLS" \
            -p "$PROMPT" \
            >> "$LOG_FILE" 2>&1

        if [ -f "$DIGEST" ]; then
            echo "[$DATE] Base analysis complete. Output: $OUTPUT_DATE_DIR/"
        else
            echo "[$DATE] Base analysis may have failed — no digest.md produced."
            echo "         Check log: $LOG_FILE"
            return 0
        fi
    fi

    # --- Second pass: support persona ticket analysis ---
    if [ "$PERSONA" = "support" ]; then
        local SUPPORT_MARKER="$OUTPUT_DATE_DIR/.support-analyzed"
        if [ -f "$SUPPORT_MARKER" ]; then
            echo "[$DATE] Support pass already ran. Skipping."
            return 0
        fi

        echo "[$DATE] Running support ticket analysis pass..."
        local TICKETS_DIR="$OUTPUT_DIR/tickets"
        mkdir -p "$TICKETS_DIR"

        local SUPPORT_LOG="$LOG_DIR/support-analysis-$DATE.log"
        local SUPPORT_PROMPT="Run support-ticket-analysis for date $DATE.

Config file: $CONFIG_FILE
Raw screenshots directory: $RAW_DATE_DIR/
Daily output directory: $OUTPUT_DATE_DIR/
Per-ticket directory (evolving): $TICKETS_DIR/

Confirm persona: support in the config. Read the support and redaction blocks.
Then segment the day into ticket sessions, detect context switches, attribute work,
and update the per-ticket markdown files. Write context-switching.md and tickets-summary.md
into the daily output directory, and append a Tickets Lens section to digest.md."

        claude --model "$MODEL" \
            --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
            -p "$SUPPORT_PROMPT" \
            >> "$SUPPORT_LOG" 2>&1

        if [ -f "$OUTPUT_DATE_DIR/context-switching.md" ]; then
            touch "$SUPPORT_MARKER"
            echo "[$DATE] Support pass complete. Tickets: $TICKETS_DIR/"
        else
            echo "[$DATE] Support pass may have failed — no context-switching.md produced."
            echo "         Check log: $SUPPORT_LOG"
        fi
    fi
}

# --- Run analysis ---
echo "=== Screen Capture Analysis — $(date) ==="

if [ -n "$1" ]; then
    # Explicit date provided — analyze that date only, no catch-up
    analyze_date "$1"
else
    # Default: today + catch-up
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
fi

echo "=== Done ==="
