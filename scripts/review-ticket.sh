#!/bin/bash
# review-ticket.sh — Re-runs ticket-scoped synthesis for a single ticket across
# all of its observed sessions to date. Produces tickets/<ID>/review.md, a
# self-review summary intended to be shared with the team.
#
# Usage: ./scripts/review-ticket.sh <TICKET-ID>
# Example: ./scripts/review-ticket.sh ZD-12345

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

CONFIG_FILE="$HOME/.screen-capture/config.yaml"
SUPPORT_SKILL_FILE="$HOME/.claude/skills/support-ticket-analysis/SKILL.md"

# --- Simple YAML parser (matches analyze.sh) ---
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

# --- Preflight ---
if [ -z "${1:-}" ]; then
    echo "Usage: $0 <TICKET-ID>"
    echo "Example: $0 ZD-12345"
    exit 1
fi
TICKET_ID="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config not found: $CONFIG_FILE — run install.sh first"
    exit 1
fi

PERSONA=$(parse_yaml_value "persona" "")
if [ "$PERSONA" != "support" ]; then
    echo "Error: persona is not 'support' in $CONFIG_FILE"
    echo "       This script is only useful for the support persona."
    exit 1
fi

if ! command -v claude &>/dev/null; then
    echo "Claude Code CLI not found. Install: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

if [ ! -f "$SUPPORT_SKILL_FILE" ]; then
    echo "Support skill not found: $SUPPORT_SKILL_FILE — run install.sh first"
    exit 1
fi

# --- Load config ---
OUTPUT_DIR=$(parse_yaml_value "directory" "$HOME/screen-capture")
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
MODEL=$(parse_yaml_value "model" "opus")
LOG_DIR="$OUTPUT_DIR/logs"
mkdir -p "$LOG_DIR"

TICKET_DIR="$OUTPUT_DIR/tickets/$TICKET_ID"

if [ ! -d "$TICKET_DIR" ]; then
    echo "Ticket folder not found: $TICKET_DIR"
    echo "Has this ticket been analyzed yet? Try running ./scripts/analyze.sh first."
    exit 1
fi

# --- Run review synthesis ---
LOG_FILE="$LOG_DIR/review-${TICKET_ID}.log"

PROMPT="Run a cross-session review synthesis for ticket $TICKET_ID.

Config file: $CONFIG_FILE
Ticket folder: $TICKET_DIR/
Daily outputs root: $OUTPUT_DIR/

Read every existing file in $TICKET_DIR/ (process.md, feedback.md, opportunities.md, timeline.md).
Read the supporting evidence from daily folders ($OUTPUT_DIR/*/context-switching.md and
$OUTPUT_DIR/*/tickets-summary.md) that reference this ticket.

Produce $TICKET_DIR/review.md — a self-review summary intended to be shared with the team.
It should:
1. Synthesize the full investigation arc across all observed sessions and days
2. Call out the highest-leverage automation / FAQ / runbook opportunities from opportunities.md
3. Summarize context-switching cost specifically borne by this ticket (switches in/out, re-entry cost, fragmentation)
4. Flag knowledge gaps that slowed resolution
5. State a one-line verdict on whether this ticket's handling is a candidate for process improvement

Apply the redaction rules from the config — never write person names if redact_person_names is true.
Overwrite $TICKET_DIR/review.md if it exists."

echo "Running review synthesis for $TICKET_ID..."
claude --model "$MODEL" \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
    -p "$PROMPT" \
    >> "$LOG_FILE" 2>&1

if [ -f "$TICKET_DIR/review.md" ]; then
    echo "Review written: $TICKET_DIR/review.md"
    echo "To share with the team: ./scripts/publish.sh $TICKET_ID"
else
    echo "Review may have failed — no review.md produced."
    echo "Check log: $LOG_FILE"
    exit 1
fi
