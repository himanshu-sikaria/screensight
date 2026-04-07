---
name: screen-analysis
description: "Analyzes daily screen captures to produce process maps, observations, coaching feedback, automation opportunities, and business process detection. Config-driven — adapts to any role."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
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

**Only if `meeting_source: granola` in config:**

1. Use `mcp__claude_ai_Granola__list_meetings` to find all meetings for the analysis date
2. For each meeting, use `mcp__claude_ai_Granola__get_meeting_transcript` to get the full transcript
3. Build a meeting index: title, start/end time, participants, key topics, decisions, action items

This gives the **conversation layer** — what was said in meetings. Screenshots give the **visual layer** — what was on screen. The analysis merges both:

- Meeting blocks in the process map get enriched with topics, decisions, and action items
- Observations can reference what was said vs. what was on screen
- Process detection benefits from knowing what was discussed during prep and follow-up

**If meeting_source is `none` or Granola is unavailable**: Proceed with screenshots only.

---

## Step 2: Read Screenshots (Adaptive Strategy)

Raw screenshots are in `<raw_screenshots_dir>/*.jpg` (JPEG, ~30s intervals).

### Phase A: Skeleton scan
Read every 2nd screenshot chronologically to build the timeline. For each, extract:
- **Timestamp** (from filename: HH-MM-SS.jpg)
- **App**: What application is in the foreground
- **Context**: What's on screen (meeting, doc, thread, spreadsheet, code, terminal, etc.)
- **People visible**: Names in video call tiles, chat threads, doc editors

This gives a ~50% sample rate — one screenshot per minute. Enough to catch every transition and activity block.

### Phase B: Targeted fill-in
After the skeleton is built, fill remaining gaps:
- **Transitions**: Where the app/context changed between two samples — read the screenshots in that gap
- **Meeting content shifts**: Read additional screenshots within meetings where screen-shares or doc editing are detected
- **Rapid-switch zones**: Read every screenshot in periods with 3+ transitions in 5 minutes

### Budget guidance
- Full day (~960 screenshots): ~480 skeleton + ~50-100 targeted = ~530-580 reads
- Half day (~480 screenshots): ~240 skeleton + ~30-50 targeted = ~270-290 reads
- Use parallel agents (3-4) to read screenshots concurrently — split the day into time blocks
- Target: minimum 50% of all screenshots read. Below 30% is insufficient for accurate analysis.

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

| Category | Duration | % of Day | Blocks |
|----------|----------|----------|--------|
| ... | ... | ... | ... |

Total active time: Xh Ym
```

**Dynamic categories**: Do NOT use predefined categories. Let categories emerge from what's on screen. Name them by app + primary context (e.g., "Zoom — team syncs", "Slack — async threads", "VS Code — feature development").

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
