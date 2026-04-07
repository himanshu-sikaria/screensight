# Screen Capture

AI-powered screen capture and analysis tool for macOS. Takes a screenshot every 30 seconds, then runs an end-of-day AI analysis to produce process maps, coaching feedback, automation opportunities, and business process detection.

All data stays local. Analysis outputs are markdown files.

## How It Works

```
Every 30 seconds:                    End of day (or on login):
┌──────────────────┐                 ┌──────────────────────────┐
│ Capture Daemon    │                 │ Analysis Engine           │
│                   │                 │                           │
│ Screenshot        │                 │ Claude Code reads ~500    │
│ → Resize (1280px) │                 │ screenshots via vision    │
│ → Compress (JPEG) │                 │                           │
│ → Skip if idle/   │                 │ Produces:                 │
│   locked/excluded │                 │ • digest.md (timeline)    │
│                   │                 │ • observations.md         │
│ Store locally:    │                 │ • feedback.md (coaching)  │
│ ~/screen-capture/ │────────────────→│ • automations.md          │
│ raw/YYYY-MM-DD/   │                 │ • processes/ (evolving)   │
└──────────────────┘                 └──────────────────────────┘
```

## Prerequisites

- **macOS** (uses native `screencapture` command)
- **Claude Code CLI** — [Install here](https://docs.anthropic.com/en/docs/claude-code)

## Install

```bash
git clone https://github.com/himanshu-sikaria/screen-capture.git
cd screen-capture
./install.sh
```

The installer will:
1. Ask you to pick a role template (Engineering, Product, CS, Sales, or Custom)
2. Install config to `~/.screen-capture/config.yaml`
3. Install the Claude Code analysis skill
4. Set up LaunchAgents (auto-start on login)
5. Open System Preferences for Screen Recording permission

## Configuration

Edit `~/.screen-capture/config.yaml` to customize:

```yaml
# Your role (shapes analysis and feedback)
role: "Software Engineer"
focus_areas:
  - deep work and coding output
  - code review throughput

# What coaching feedback should emphasize
coaching:
  - deep work protection
  - meeting load management

# Capture settings
capture:
  interval_seconds: 30          # How often to screenshot
  idle_timeout_minutes: 30      # Skip when idle
  retention_days: 7             # Auto-delete raw screenshots
  exclude_apps: ["1Password"]   # Never capture these apps

# Analysis
analysis:
  schedule_hour: 23             # When to run analysis (24h)
  model: opus                   # opus (best) or sonnet (cheaper)
  meeting_source: none          # none or granola
```

### Role Templates

Pre-built configs for common roles:
- `configs/templates/engineering.yaml` — Deep work, code review, architecture
- `configs/templates/product.yaml` — Customer discovery, roadmap, cross-functional alignment
- `configs/templates/customer-success.yaml` — Customer engagement, renewals, escalations
- `configs/templates/sales.yaml` — Pipeline, prospecting, deal prep

## Output

All output is in `~/screen-capture/`:

```
~/screen-capture/
├── raw/                        # Raw screenshots (auto-deleted after retention_days)
│   └── 2026-04-07/
│       ├── 09-03-15.jpg
│       ├── 09-03-45.jpg
│       └── ...
├── 2026-04-07/                 # Daily analysis output
│   ├── digest.md               # Process map, time allocation, focus analysis
│   ├── observations.md         # 10-20 micro-patterns and observations
│   ├── feedback.md             # Coaching feedback tied to your priorities
│   ├── automations.md          # Automation opportunities with effort estimates
│   └── processes.md            # New/updated process patterns
├── processes/                  # Evolving business process documentation
│   ├── slack-triage.md
│   ├── meeting-prep.md
│   └── ...
└── logs/                       # Daemon and analysis logs
```

### What Each File Contains

**digest.md** — Visual timeline of your day with a process map showing every activity block, time allocation table, focus analysis (deep work blocks, context switches), and a productivity signal score.

**observations.md** — Open-format list of 10-20 things a smart observer would notice about how you work. Micro-patterns, people patterns, preparation habits, anomalies.

**feedback.md** — Direct coaching feedback structured around your configured coaching priorities. What you should not have done, what you could have done better.

**automations.md** — Repeated manual patterns with frequency, time cost, and specific automation suggestions.

**processes/** — Detected business processes that evolve over time. Each file tracks steps, people, time per instance, and automation potential.

## Granola Meeting Integration

If you use [Granola](https://granola.ai) for meeting notes and have the Granola MCP integration enabled in Claude Code, screen-capture can merge meeting transcripts with screen data for richer analysis.

**To enable:**

1. Make sure Granola MCP is connected in your Claude Code settings (Settings > MCP Servers > Granola)
2. Set `meeting_source: granola` in `~/.screen-capture/config.yaml`

**What it adds:**

- Meeting blocks in digest.md get enriched with topics, decisions, action items, and engagement level
- Feedback includes a meeting effectiveness table (decisions made, follow-up visible, engagement)
- Observations flag screen-vs-speech divergence (e.g., multitasking during presentations)
- Process detection picks up pre-meeting prep and post-meeting follow-up patterns
- Decision closure tracking: did decisions from meetings get documented in tools afterward?

**Without Granola:** Everything works — analysis is based on screenshots only. Meeting blocks still appear in the timeline (Zoom/Meet visible on screen) but without transcript context.

## Cost

The AI analysis uses Claude's vision API to read screenshots:

| Model | Cost/Day | Quality |
|-------|----------|---------|
| Opus | ~$5-15 | Best analysis, most nuanced feedback |
| Sonnet | ~$1-3 | Good analysis, less detailed coaching |

Set `analysis.model` in config to control cost.

## Privacy

- All screenshots stay on your machine. They are never uploaded to any server.
- Claude Code reads screenshots locally via the filesystem.
- When analysis runs, screenshot content is sent to Anthropic's API for vision processing. This is standard Claude Code behavior, covered by [Anthropic's usage policy](https://www.anthropic.com/legal/aup).
- Use `exclude_apps` to skip sensitive applications (password managers, banking, medical).
- Raw screenshots auto-delete after `retention_days` (default: 7).
- No telemetry, no analytics, no data collection.

## Manual Analysis

To run analysis manually (without waiting for the scheduled time):

```bash
./scripts/analyze.sh
```

This analyzes today + catches up on any missed days.

## Uninstall

```bash
./uninstall.sh
```

Removes LaunchAgents, config, and the Claude Code skill. Optionally removes captured data.

## Troubleshooting

**No screenshots being captured**
- Check Screen Recording permission: System Preferences → Privacy & Security → Screen Recording → enable Terminal/iTerm
- Check the daemon is running: `cat /tmp/screen-capture.pid && ps aux | grep capture-daemon`
- Check logs: `cat ~/screen-capture/logs/capture.log`

**Analysis not running**
- Check Claude Code is installed: `claude --version`
- Check the skill exists: `ls ~/.claude/skills/screen-analysis/SKILL.md`
- Run manually to see errors: `./scripts/analyze.sh`
- Check logs: `cat ~/screen-capture/logs/analyze-trigger.log`

**LaunchAgent not loading**
- Reload: `launchctl unload ~/Library/LaunchAgents/com.screen-capture.daemon.plist && launchctl load ~/Library/LaunchAgents/com.screen-capture.daemon.plist`
- Check for errors: `launchctl list | grep screen-capture`

**High API costs**
- Switch to Sonnet: set `analysis.model: sonnet` in config
- Increase capture interval: set `capture.interval_seconds: 60` for half the screenshots
- Reduce retention to analyze fewer days on catch-up
