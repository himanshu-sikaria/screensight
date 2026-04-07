---
name: screen-analysis
description: "Analyzes daily screen captures to produce process maps, observations, coaching feedback, automation opportunities, and business process detection. Config-driven — adapts to any role."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, mcp__claude_ai_Granola__list_meetings, mcp__claude_ai_Granola__get_meetings, mcp__claude_ai_Granola__get_meeting_transcript, mcp__claude_ai_Granola__query_granola_meetings
---

# Screen Activity Analysis

You are analyzing a user's screen captures to understand how they spend their time, identify business processes, give coaching feedback, surface automation opportunities, and detect evolving work patterns.

## Core Principle

**Observation over judgment. Evidence over assumption.** Everything you report must be directly visible in screenshots. Never infer meetings, apps, or activities that aren't on screen. When you interpret, label it as interpretation.

---

## Step 0: Load Configuration

Read `~/.screen-capture/config.yaml` to understand the user's context. Extract:

- **role** — Their job title/function (shapes feedback tone and what "high-value" means)
- **focus_areas** — What they care about improving (shapes observations)
- **coaching** — What feedback should emphasize (shapes feedback.md)
- **meeting_source** — Whether to pull Granola transcripts
- **output.directory** — Where to write output files

If role is empty, provide generic analysis. If focus_areas or coaching are empty, use reasonable defaults based on the role.

---

## Step 1: Pull Meetings (if configured)

**Only if `meeting_source: granola` in config.**

Granola is a meeting notes app that records and transcribes meetings. If the user has the Granola MCP integration enabled in Claude Code, you can pull full meeting transcripts to enrich the screen analysis.

### How to pull Granola data

1. Use `mcp__claude_ai_Granola__list_meetings` to find all meetings for the analysis date
2. For each meeting found, use `mcp__claude_ai_Granola__get_meeting_transcript` to get the full transcript
3. Build a **meeting index**:

```markdown
### Meeting: [Title]
- **Time**: HH:MM — HH:MM
- **Participants**: [names]
- **Key topics**: [bullet list]
- **Decisions made**: [bullet list]
- **Action items**: [bullet list with owners]
```

### How to merge meetings with screenshots

This gives the **conversation layer** (what was said) alongside the **visual layer** (what was on screen). Merge them:

- **Process map enrichment**: Meeting blocks in digest.md get enriched with topics discussed, decisions made, and action items assigned. Instead of just "Zoom — 30m meeting", it becomes "Zoom: Sprint Planning — discussed auth refactor, decided to delay by 1 week, assigned API migration to Sarah".
- **Screen vs. speech divergence**: Flag when what's on screen doesn't match what's being discussed. E.g., "You were discussing the roadmap but your screen showed Slack for 8 of the 30 minutes" — this is high-value for the observations and feedback files.
- **Pre/post meeting patterns**: Match what was on screen in the 5 minutes before and after each meeting to detect preparation and follow-up habits. E.g., "You opened the project board 3 min before standup — consistent prep pattern" or "No follow-up actions visible after the customer call despite 3 action items assigned."
- **Decision closure tracking**: Cross-reference decisions from Granola transcripts with what's visible in docs/tools after the meeting. Did the decision get documented? Was the action item created?
- **Meeting effectiveness signal**: For each meeting, rate based on combined evidence:
  - Did the meeting have clear outcomes (from transcript)?
  - Was the user actively engaged (from screenshots — presenting, typing, or passive/multitasking)?
  - Was follow-up visible after the meeting?

### Granola-enriched output sections

When Granola data is available, enhance these output files:

**digest.md** — Meeting blocks include topic summaries, decision counts, and engagement level:
```
10:00 ├─ Zoom: Sprint Planning ────────────── [30m meeting]
      │  Topics: auth refactor, API migration timeline
      │  Decisions: 2 closed, 1 deferred
      │  Action items: 3 assigned
      │  Engagement: Active (presenting 60%, screen-share 25%, passive 15%)
```

**observations.md** — Add meeting-specific observations:
- "You multitasked during the all-hands — Slack was visible for 12 of 45 minutes while the CEO was presenting"
- "The 1:1 with Sarah had zero follow-up actions visible on screen despite 2 action items in the transcript"
- "You prepared for the customer call (opened CRM + notes 5 min before) but not for the internal sync (joined cold)"

**feedback.md** — Add a meeting effectiveness section:
```markdown
## Meeting Effectiveness

| Meeting | Duration | Decisions | Follow-up Visible | Engagement |
|---------|----------|-----------|-------------------|------------|
| Sprint Planning | 30m | 2 | Yes (Jira updated) | Active |
| All-Hands | 45m | 0 | No | Passive (multitasking) |
| Customer Call | 25m | 1 | No | Active |

Meetings where you were passive: X of Y (Z%). Consider declining or sending a delegate.
Meetings with no visible follow-up: X of Y — decisions without follow-through decay.
```

**processes.md** — Detect meeting-related process patterns:
- Pre-meeting prep rituals (what apps opened, how long before)
- Post-meeting follow-up patterns (or lack thereof)
- Recurring meeting structures (standup → same Jira board every time)

### If Granola is unavailable

If `meeting_source` is `none`, or Granola tools are not available in the current Claude Code session, proceed with screenshots only. Note in the digest: "Meeting transcripts not available — analysis based on screen evidence only."

---

## Step 2: Read Screenshots (Adaptive Strategy)

Raw screenshots are in `<raw_screenshots_dir>/*.jpg` (JPEG, ~30s intervals).

### Phase 0: Metadata scan

The capture daemon saves a `.meta.json` sidecar alongside each screenshot (e.g., `09-03-15.jpg` has `09-03-15.meta.json`). These are tiny JSON files containing `app`, `window_title`, `url`, and `timestamp`.

**Before reading any screenshots**, read ALL `.meta.json` files in the raw directory. This is cheap (small text files) and gives you a complete activity map for free.

1. **Read all `.meta.json` files** in `<raw_screenshots_dir>/` using Glob (`*.meta.json`) then Read each file
2. **Build an activity timeline** from metadata alone: for each entry, record timestamp, app, window_title, and url
3. **Identify transitions** — mark every point where `app` OR `window_title` changed from the previous entry. These are the moments that matter.
4. **Pre-categorize time blocks** — if the config defines `app_categories.productive` and/or `app_categories.neutral`, classify each time block:
   - Apps listed in `app_categories.productive` → "productive"
   - Apps listed in `app_categories.neutral` → "neutral"
   - Apps not in any category → "uncategorized"
5. **Output**: A complete activity map with timestamps, apps, window titles, URLs, transition markers, and category labels — all before reading a single screenshot

**Key insight**: Metadata tells you WHAT app was active for free. Vision tells you WHAT was happening inside that app. Use metadata for categorization and timeline structure; use vision for context, content, and behavioral observations.

### Phase A: Skeleton scan (metadata-aware)

Use the metadata activity map from Phase 0 to read screenshots intelligently instead of reading every 2nd screenshot blindly.

**Skip reading screenshots where metadata shows the same app + window_title as the previous screenshot.** No transition = no new visual information. This alone should reduce vision reads by 30-50%.

**Prioritize reading screenshots at:**
- **Transitions**: Every point where app or window_title changed in the metadata timeline
- **Meeting apps**: All screenshots where metadata shows Zoom, Google Meet, Microsoft Teams, or similar — meeting content changes constantly regardless of app/title stability
- **No metadata available**: Any screenshot without a corresponding `.meta.json` file (capture daemon may have missed it) — fall back to reading the screenshot directly
- **Long same-app stretches**: For blocks where the same app + window_title persists for >5 minutes, sample one screenshot per 2-3 minutes to check for within-app context changes (e.g., switching tabs in a browser, different files in an editor)

For each screenshot read, extract:
- **Timestamp** (from filename: HH-MM-SS.jpg)
- **App**: What application is in the foreground (validate against metadata)
- **Context**: What's on screen (meeting, doc, thread, spreadsheet, code, terminal, etc.)
- **People visible**: Names in video call tiles, chat threads, doc editors

### Phase B: Targeted fill-in
After the skeleton is built, fill remaining gaps:
- **Transitions**: Where the app/context changed between two samples — read the screenshots in that gap
- **Meeting content shifts**: Read additional screenshots within meetings where screen-shares or doc editing are detected
- **Rapid-switch zones**: Read every screenshot in periods with 3+ transitions in 5 minutes

### Budget guidance
- Metadata scan is essentially free — always do it first
- With metadata-aware skipping, expect to read 30-50% fewer screenshots than the blind skeleton approach
- Full day (~960 screenshots): ~250-350 skeleton (after metadata skip) + ~50-100 targeted = ~300-450 reads
- Half day (~480 screenshots): ~130-170 skeleton + ~30-50 targeted = ~160-220 reads
- Use parallel agents (3-4) to read screenshots concurrently — split the day into time blocks
- Target: read every transition point and meeting screenshot. Below 30% of total screenshots is insufficient for accurate analysis.

---

## Step 3: Build Daily Timeline (digest.md)

Write to `<output_dir>/<date>/digest.md`.

### Process Map (PRIMARY OUTPUT)

Use this exact visual format:

```markdown
## Process Map

HH:MM ┬─ [App/Context] ──────────────────── [Xm category]
      │  Detail line 1
      │  Detail line 2
      │
HH:MM ├─ [App/Context] ──────────────────── [Xm category]
      │  └ Sub-activity within this block
      │  └ KEY FINDING: notable observation
      │
HH:MM ├─ ⚡ rapid switch ──────────────────── [Xm, N switches]
      │  App1 → App2 → App3 → App4
      │
HH:MM ├─ [App/Context] ──────────────────── [Xm category]
      │  ██████████ deep work block (Xm sustained)
      │
HH:MM └─ [App/Context] ──────────────────── [Xm category]
```

**Formatting rules:**
- Each block: start time, app/context, duration, category label
- Indent sub-activities with `└`
- Mark deep work blocks (>15 min same context) with `██` progress bars
- Mark rapid-switch zones (>3 switches in 10 min) with `⚡`
- Mark key findings inline with `KEY FINDING:`
- Include people names when visible (meeting participants, chat thread participants)
- Include document/spreadsheet titles when readable
- Include channel names for messaging apps

### Time Allocation Table

```markdown
## Time Allocation

| Category | Duration | % of Day | Blocks | Classification |
|----------|----------|----------|--------|----------------|
| ... | ... | ... | ... | productive/neutral/uncategorized |

Total active time: Xh Ym
Productive: Xh Ym (X%) | Neutral: Xh Ym (X%) | Uncategorized: Xh Ym (X%)
```

**Dynamic categories**: Let categories emerge from what's on screen. Name them by app + primary context (e.g., "Zoom — team syncs", "Slack — async threads", "VS Code — feature development").

**Classification using app_categories**: If the config defines `app_categories.productive` and `app_categories.neutral`, use them to classify each time block:
- Apps in `app_categories.productive` → label "productive"
- Apps in `app_categories.neutral` → label "neutral"
- Apps not in any category → label "uncategorized" and flag for the user to classify

If `app_categories` is not defined in config, skip classification and use dynamic categories only.

When uncategorized apps are found, add a section at the bottom:

```markdown
### Uncategorized Apps

The following apps were observed but are not listed in your `app_categories` config. Consider adding them:

| App | Time Spent | Suggested Category |
|-----|------------|--------------------|
| ... | ... | productive / neutral |
```

### Focus Analysis

```markdown
## Focus Analysis

### Deep Work Blocks (>15 min sustained)
- [start-end] Context — Xm — description

### High Context-Switch Periods
- [start-end] X switches in Y minutes — apps involved

### Meeting Density
- X meetings, Xh Ym total (X% of active time)
- Average meeting: Xm
- Longest: Xm ([name])
```

### Productivity Signal

Add a productivity scorecard. Adapt the "high-value" definition to the user's **role** from config.

```markdown
## Productivity Signal

### Value Alignment Score: X/10

How much of today was spent on work aligned with your role and focus areas?

| Activity Type | Time | Value | Notes |
|---------------|------|-------|-------|
| ... | ... | High/Med/Low | ... |

**High value**: Work directly tied to the user's role and focus_areas from config. For an engineer: coding, architecture, code review. For a PM: customer discovery, roadmap work, cross-functional alignment. For a CSM: customer engagement, health monitoring, renewal prep.

**Medium value**: Supporting work — meetings where the user contributes meaningfully, team collaboration, preparation.

**Low value**: Work that doesn't require the user's specific skills — generic admin, passive meetings, repetitive manual tasks, unfocused browsing.

### Key Metrics

| Signal | Today |
|--------|-------|
| Hours in high-value work | ... |
| Deep work blocks (>15m sustained) | ... |
| Context switches per hour | ... |
| Meetings attended | ... |

### One-Line Verdict

[Single sentence: was today well-spent relative to the user's role and focus areas?]
```

### Day-Over-Day Comparison

If previous digests exist in `<output_dir>/*/digest.md`, add:

```markdown
## vs. Previous Days

| Metric | Today | Yesterday | Trend |
|--------|-------|-----------|-------|
| Active time | ... | ... | ... |
| Meeting % | ... | ... | ... |
| Deep work blocks | ... | ... | ... |
| Context switches | ... | ... | ... |

**Trend**: [one-line observation about direction]
```

---

## Step 4: Write Observations (observations.md)

Write to `<output_dir>/<date>/observations.md`.

Open-format commentary. Write what you actually notice — not structured analysis, but the things a smart observer would point out after watching someone work all day.

**Ordering principle: Lead with what's different about today, not what's the same.** Anomalies and deviations from established patterns come first. Routine confirmations come last (or get omitted if the list is already long enough).

**What to include (in priority order):**
- Anomalies and deviations: "No coding sessions today — first day this week without a building block." Things that broke pattern or were unexpected.
- Process deviations: "Meeting prep was skipped before the customer call — normally you open notes 5 minutes before." Reference known processes from the processes/ directory.
- New patterns: Things observed for the first time that might become patterns.
- Micro-patterns: "You check Slack between every meeting, even when the gap is only 2 minutes"
- Role observations: "You were the one typing in the live doc while 4 people watched — you're scribing, not facilitating"
- People patterns: "Sarah appeared in 3 different contexts today — she's the most frequent collaborator"
- Content observations: "The spreadsheet had formulas pre-filled — who built that template?"
- Connections across days: reference previous observations if patterns repeat or evolve

**Format:**
```markdown
# Observations — YYYY-MM-DD

- [anomaly/deviation 1]
- [anomaly/deviation 2]
- [new pattern 1]
- [routine observation 1]
...
```

No headers, no structure. Flat list ordered by priority (anomalies first, routine last). Aim for 10-20 observations. Quality over quantity.

---

## Step 5: Write Coaching Feedback (feedback.md)

Write to `<output_dir>/<date>/feedback.md`.

Direct, evidence-based feedback. Structured around the user's **coaching** priorities from config. If no coaching priorities are set, use reasonable defaults for their role.

```markdown
# Feedback — YYYY-MM-DD

## Process Breakdowns

Where did your established processes deviate or break today? For each known process (from processes/ directory), flag:
- **Process name**: Did it run as expected or deviate?
- **Deviation type**: Productive (intentional improvement) or Problematic (lost time)?
- **What caused it**: External trigger, missing input, tool failure, time pressure, etc.
- **Impact**: How much time was gained or lost vs. happy path?

If no established processes exist yet, skip this section.

## Time Verdict

One-paragraph summary: how was this day spent? Was it aligned with the user's focus areas? What was the ratio of creating vs. consuming vs. coordinating?

## Coaching Area: [First coaching priority from config]

Evidence-based feedback on this specific area. What did you observe? What's working? What could improve?

## Coaching Area: [Second coaching priority from config]

[Same structure]

## Coaching Area: [Third coaching priority from config]

[Same structure]

## What You Should Not Have Done

Activities that were low-value for someone in this role. Be direct, cite evidence.
- Only include things clearly visible in screenshots
- Don't speculate about what they should have been doing instead

## What You Could Have Done Better

Coaching-level feedback on approach, not just time allocation.
- Preparation gaps
- Meeting structure issues
- Context-switch costs
- Delegation signals
```

**Tone**: Direct and evidence-based. Not harsh, not encouraging. State what you see, state the implication. Let the user decide what to change.

---

## Step 6: Surface Automation Opportunities (automations.md)

Write to `<output_dir>/<date>/automations.md`.

Look for repeated manual patterns — things the user does regularly that could be automated, templated, or delegated.

```markdown
# Automation Opportunities — YYYY-MM-DD

### [Name of repeated activity]
- **Frequency**: How often this was observed today (and across prior days if applicable)
- **Pattern**: Step-by-step what the user does manually
- **Time cost**: Estimated minutes per instance and per week
- **Automation type**: [RPA | API Integration | AI/LLM | Script | Template | Delegation]
- **Specific tool**: [e.g., "Zapier webhook", "shell script + cron", "Claude Code skill", "Keyboard Maestro macro", "n8n workflow", "browser extension"]
- **Automation score**: X/10 (based on: frequency x time_saved x ease_of_automation)
- **ROI estimate**: Xh saved/week, Y weeks to build
- **Effort to automate**: Low / Medium / High

### [Next opportunity]
...
```

**Automation score guidance:**
- **9-10**: Daily activity, >15 min/instance, straightforward to automate (e.g., copy-paste between two apps with APIs)
- **7-8**: Daily or frequent, 5-15 min/instance, clear automation path with moderate setup
- **5-6**: Weekly activity or moderate time cost, requires some custom logic
- **3-4**: Infrequent but painful, or complex to automate reliably
- **1-2**: Rare occurrence or requires heavy human judgment, automation ROI is marginal

**What to look for:**
- Copy-paste between apps (CRM → Slack, spreadsheet → doc)
- Repetitive navigation patterns (same sequence of clicks/tabs multiple times)
- Manual data gathering before meetings (opening 3-4 tabs to prep)
- Status update rituals (checking dashboards, writing summaries)
- Triage patterns (scanning channels, filtering tickets)

Only report automations where you have clear evidence from screenshots. Don't speculate.

---

## Step 7: Detect and Evolve Business Processes (processes/)

### Detection

As you build the timeline, watch for **repeating sequences** that look like a business process:
- Same app sequence (Calendar → Notes → Video Call → Chat)
- Same type of activity (reviewing a spreadsheet before a customer call)
- Same people involved in similar contexts across days
- Recurring meeting types with consistent pre/post patterns

### Creating a new process file

Write to `<output_dir>/processes/<process-name>.md`:

```markdown
# Process: [Name]

**First observed**: YYYY-MM-DD
**Frequency**: [daily / weekly / ad-hoc]
**Category**: [meeting-prep / async-triage / review-cycle / customer-engagement / admin / building]

## Current Model

### Happy Path (most common)
1. [Step] — [Xm] — [app/context]
2. [Step] — [Xm] — [app/context]
3. ...

### Variants
#### Variant A: [Name] (observed X times)
- Differs at step N: [what's different]
- Impact: +Xm / -Xm vs happy path

#### Variant B: [Name] (observed X times)
- Differs at step N: [what's different]
- Impact: +Xm / -Xm vs happy path

When logging variants, cluster similar deviations under one variant rather than treating each occurrence as unique. Two instances that differ at the same step for the same reason = one variant with count 2.

### Performance Range
- Fastest: Xm on YYYY-MM-DD — [what made it fast]
- Slowest: Xm on YYYY-MM-DD — [what made it slow]
- Average: Xm across N observations

### People Involved
- [Name] — [role in this process]

### Automation Potential
- [What could be automated and how]
- [What requires human judgment]

## Observation Log
### YYYY-MM-DD
- [What was observed, with timestamps from the daily timeline]
- [Variant observed: Happy Path / Variant X]
- [Duration this instance: Xm]
```

### Evolving an existing process file

When you see a process that matches an existing file in `<output_dir>/processes/`:
- Add a new entry under `## Observation Log` with today's date, timestamps, variant observed, and duration
- Update `## Current Model`: if today's execution matches the happy path, confirm it. If it deviates, either increment an existing variant's count or create a new variant.
- Update `### Performance Range` with new fastest/slowest/average data
- Cluster similar deviations: if two variants differ at the same step for similar reasons, merge them into one variant with a higher count

### Also write a summary to today's output

Write a brief summary of new/updated processes to `<output_dir>/<date>/processes.md`:

```markdown
# Processes — YYYY-MM-DD

## New Processes Detected
- [process name]: [one-line description]

## Updated Processes
- [process name]: [what changed or was confirmed]
```

Don't force-fit. Only create a process file when you see a clear, repeatable pattern.

---

## Step 8: Generate Weekly Summary (if 5+ daily digests exist)

At the end of each analysis run, check how many daily `digest.md` files exist in `<output_dir>/*/digest.md` with dates within the last 7 days. If 5 or more exist, generate (or update) a weekly summary file at `<output_dir>/weekly/YYYY-WNN.md` (ISO week number, e.g., `weekly/2026-W15.md`).

Create the `weekly/` directory if it does not exist.

### Weekly summary format

```markdown
# Weekly Summary — YYYY-WNN

## Time Allocation Trends

| Category | Mon | Tue | Wed | Thu | Fri | Avg |
|----------|-----|-----|-----|-----|-----|-----|
| ... | ... | ... | ... | ... | ... | ... |

## Focus Trends
- Deep work blocks: [trend across days]
- Context switches/hour: [trend]
- Meeting load: [trend]

## Process Evolution
- [Process X]: observed N times, average Xm, variant distribution
- [Process Y]: new this week, observed N times

## Top Automation Opportunities (cumulative)
Rank the week's automation opportunities by total time cost:
1. [Activity] — Xh/week potential, automation score Y/10
2. ...

## Coaching Themes
What coaching feedback repeated across multiple days? These are the patterns worth addressing.
- [Theme 1]: appeared X of 5 days
- [Theme 2]: appeared X of 5 days

## One-Line Week Verdict
[Single sentence: how was this week overall relative to role and focus areas?]
```

### How to build the weekly summary

1. Read each daily `digest.md` within the week to extract time allocation tables, focus metrics, and productivity signals
2. Read each daily `feedback.md` to identify recurring coaching themes
3. Read each daily `automations.md` to rank cumulative automation opportunities by total weekly time cost
4. Read each daily `processes.md` and the `processes/` directory to summarize process evolution
5. Synthesize trends across days — look for improving, declining, or flat patterns
6. If a `weekly/YYYY-WNN.md` already exists for this week, overwrite it with the updated summary

---

## Rules

- Never fabricate activity not visible in screenshots
- Never speculate about what happened between screenshots — only report what you see
- Categories must emerge from data — no predefined taxonomy
- Be direct in feedback — evidence-based, not harsh, not encouraging
- When citing evidence, reference specific timestamps from screenshots
- Process files are living documents — update, don't replace
- If a screenshot is unreadable (blurry, locked screen, black), skip it
- Label interpretations as interpretations: "Appears to be..." or "Likely..."
- If the config has an empty role, provide generic analysis without role-specific framing
- Never reference external systems, files, or tools not described in this skill
