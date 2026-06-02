#!/bin/bash
# publish.sh — Publishes a ticket's findings to Confluence.
# Reads the local tickets/<ID>/*.md files and creates or updates a Confluence
# page nested under the configured parent (folder or page). Idempotent: looks
# up an existing page by ticket-ID prefix in the title before creating.
#
# Usage: ./scripts/publish.sh <TICKET-ID>
# Example: ./scripts/publish.sh ZD-12345
#
# Reads publish.confluence config block from ~/.screen-capture/config.yaml.
# Uses Claude Code with Atlassian MCP tools (no API tokens needed locally).

export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

CONFIG_FILE="$HOME/.screen-capture/config.yaml"

# --- YAML parser (handles nested keys: publish.confluence.field) ---
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

parse_yaml_nested_value() {
    # Parses key under a 2-deep nesting, e.g. publish.confluence.cloud_id
    local grandparent="$1"
    local parent="$2"
    local key="$3"
    local default="$4"
    local val
    val=$(awk -v gp="$grandparent" -v p="$parent" -v k="$key" '
        BEGIN { in_gp=0; in_p=0 }
        /^[a-zA-Z_]/ { in_gp=0; in_p=0 }
        $0 ~ "^"gp":" { in_gp=1; next }
        in_gp && $0 ~ "^  "p":" { in_p=1; next }
        in_p && $0 ~ "^    "k":" {
            sub(/^[^:]+: */, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null)
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

if ! command -v claude &>/dev/null; then
    echo "Claude Code CLI not found. Install: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
fi

# --- Load Confluence config ---
PUBLISH_ENABLED=$(parse_yaml_nested_value "publish" "confluence" "enabled" "false")
if [ "$PUBLISH_ENABLED" != "true" ]; then
    echo "Confluence publishing is disabled in config (publish.confluence.enabled: false)."
    echo "Enable it in $CONFIG_FILE to publish."
    exit 1
fi

CLOUD_ID=$(parse_yaml_nested_value "publish" "confluence" "cloud_id" "")
SPACE_KEY=$(parse_yaml_nested_value "publish" "confluence" "space_key" "")
PARENT_ID=$(parse_yaml_nested_value "publish" "confluence" "parent_id" "")
TITLE_PREFIX=$(parse_yaml_nested_value "publish" "confluence" "title_prefix" "")

if [ -z "$CLOUD_ID" ] || [ -z "$SPACE_KEY" ] || [ -z "$PARENT_ID" ]; then
    echo "Confluence config incomplete. Required fields under publish.confluence:"
    echo "  cloud_id:  ${CLOUD_ID:-<missing>}"
    echo "  space_key: ${SPACE_KEY:-<missing>}"
    echo "  parent_id: ${PARENT_ID:-<missing>}"
    exit 1
fi

# --- Load output config ---
OUTPUT_DIR=$(parse_yaml_value "directory" "$HOME/screen-capture")
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
MODEL=$(parse_yaml_value "model" "opus")
LOG_DIR="$OUTPUT_DIR/logs"
mkdir -p "$LOG_DIR"

TICKET_DIR="$OUTPUT_DIR/tickets/$TICKET_ID"

if [ ! -d "$TICKET_DIR" ]; then
    echo "Ticket folder not found: $TICKET_DIR"
    echo "Run ./scripts/analyze.sh first, then ./scripts/review-ticket.sh $TICKET_ID."
    exit 1
fi

# --- Compose page title ---
PAGE_TITLE="${TITLE_PREFIX}${TICKET_ID} — Process & Findings"

# --- Run publish via headless Claude with Atlassian MCP ---
LOG_FILE="$LOG_DIR/publish-${TICKET_ID}.log"

PROMPT="Publish ticket $TICKET_ID findings to Confluence.

Ticket folder: $TICKET_DIR/
Confluence target:
  cloud_id:  $CLOUD_ID
  space_key: $SPACE_KEY
  parent_id: $PARENT_ID    (folder or page that will be the parent)
  title:     $PAGE_TITLE

Steps:
1. Read these files from the ticket folder if they exist (skip any that don't):
   - process.md
   - feedback.md
   - opportunities.md
   - timeline.md
   - review.md (preferred summary — if present, lead with it)
2. Compose a single Confluence page body that combines them as top-level sections in this order:
   - Review (from review.md if present, otherwise skip the heading)
   - Process
   - Opportunities
   - Feedback (self-review)
   - Timeline (collapsed/at the bottom)
   Use markdown — Confluence MCP will convert.
3. Search the space for an existing page whose title starts with '$TICKET_ID — '. Use
   mcp__claude_ai_Atlassian__searchConfluenceUsingCql with CQL like:
   space = $SPACE_KEY AND type = page AND title ~ \"$TICKET_ID\"
4. If an existing page is found:
   - Use mcp__claude_ai_Atlassian__updateConfluencePage to update it with the new body
   - Preserve the existing title
5. If no page is found:
   - Use mcp__claude_ai_Atlassian__createConfluencePage with:
     spaceId derived from space_key '$SPACE_KEY',
     parentId='$PARENT_ID',
     title='$PAGE_TITLE',
     body=composed markdown
   - If parentId rejects a folder ID, retry with no parent (page goes to space root)
     and log a warning.
6. Print the resulting page URL to stdout.

Do not include person names in the published body — those were already redacted at write time,
but double-check before publishing. Ticket IDs, account names, tool names, URLs all pass through."

echo "Publishing $TICKET_ID to Confluence ($CLOUD_ID, space $SPACE_KEY)..."
claude --model "$MODEL" \
    --allowedTools "Read,Glob,Grep,mcp__claude_ai_Atlassian__searchConfluenceUsingCql,mcp__claude_ai_Atlassian__createConfluencePage,mcp__claude_ai_Atlassian__updateConfluencePage,mcp__claude_ai_Atlassian__getConfluencePage,mcp__claude_ai_Atlassian__getConfluenceSpaces" \
    -p "$PROMPT" \
    2>&1 | tee -a "$LOG_FILE"

echo ""
echo "Publish log: $LOG_FILE"
