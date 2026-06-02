---
name: support-ticket-analysis
description: "Ticket-centric analysis for support engineers. Stitches a day's screenshots into per-ticket sessions, tracks context switching, and writes evolving per-ticket process / feedback / opportunities markdown. Runs after the base screen-analysis skill."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Support Ticket Analysis

You are running the second pass of daily analysis for a Customer Support Engineer. The base `screen-analysis` skill has already produced the day-level digest. Your job is to segment the same day into **ticket sessions**, track **context switching**, and update **per-ticket evolving documents** that will be shared with the team for operational improvement.

## Core Principle

**A ticket is a topic of investigation, not a UI surface.** Most support work happens in tools that don't show the ticket ID — terminals, dashboards, internal docs, Slack threads, code. Ticket IDs visible in URLs/titles are *anchors*, not boundaries. Attribute the surrounding work to the ticket based on topic continuity, not just visible IDs.

---

## Step 0: Load Configuration

Read `~/.screen-capture/config.yaml`. Verify `persona: support`. If not, **stop — this skill should not have been invoked.**

Extract from the `support:` block:
- **ticket_patterns** — list of `{ name, url_match | title_match, id_format }` regex patterns
- **spread_window_minutes** — how far before/after an anchor to attribute work (default 15)
- **switch_noise_threshold_seconds** — switches shorter than this are noise (default 120)
- **pre_ticket_attribution** — whether to retro-attach diagnostic work to a ticket once its anchor appears (default true)
- **untracked_bucketing** — `slug` (one folder per topic) or `flat` (single log file)
- **min_session_seconds** — ignore sessions shorter than this (default 60)

Extract from the `redaction:` block:
- **redact_person_names** — if true, output markdown never contains person names; use role-based references ("the customer", "an engineer", "the on-call SRE")
- **redact_account_names** — if true, replace customer/account names with generic placeholders

Extract `output.directory` (default `~/screen-capture`).

---

## Step 1: Build the Anchor Map

The base skill has already read the day's `.meta.json` sidecars. Re-read them here (cheap; small JSON files) at `<output_dir>/raw/<date>/*.meta.json`.

For each entry, apply every pattern in `support.ticket_patterns`:
- `url_match` → test against the `url` field
- `title_match` → test against the `window_title` field
- If a pattern matches, render the ticket ID by substituting capture groups into `id_format` (e.g., `id_format: "ZD-{1}"` with capture group `12345` → `ZD-12345`)

Output: an ordered list of **anchor events**:

```
[
  { "timestamp": "09:14:30", "ticket_id": "ZD-12345", "source": "zendesk:url" },
  { "timestamp": "09:16:00", "ticket_id": "ZD-12345", "source": "zendesk:url" },
  { "timestamp": "09:32:15", "ticket_id": "ATLAN-7821", "source": "linear:url" },
  ...
]
```

A single screenshot can produce multiple anchors (e.g., a Linear page with `ATLAN-7821` in URL plus the parent ZD ticket ID in the page title) — keep both, they'll resolve to the same investigation later if they're truly related.

---

## Step 2: Segment the Day into Candidate Sessions

Walk the metadata timeline chronologically. A **candidate session** is a contiguous block of screenshots where the working topic is stable. Boundaries are detected by:

1. **Explicit ticket switch** — a new anchor for a different ticket appears, sustained for more than `switch_noise_threshold_seconds`. If a different ticket flashes briefly and the user returns to the prior ticket, that flash is **noise**, not a switch.
2. **Topic shift** (vision-driven) — the apps/content visible no longer relate to the prior ticket's investigation. Read screenshots to confirm.
3. **Long gap** — idle/locked period > 10 minutes ends the session.
4. **End of day** — the last screenshot.

For each candidate session, record:
- `start` / `end` timestamps
- `primary_ticket_id` — the anchor that dominates the session, or `null` if no anchor present
- `app_sequence` — ordered list of apps used (deduped consecutive)
- `notable_artifacts` — Grafana dashboard names, customer/account names, error signatures, SQL queries, log lines, runbook URLs — anything from screenshots that anchors the topic

---

## Step 3: Spread + Attribute Work to Tickets

For each candidate session **without** a `primary_ticket_id`, attempt attribution:

1. **Look back** up to `spread_window_minutes` from the session start. If an anchor for ticket T existed in that window AND the session's `notable_artifacts` plausibly relate to T's topic (same customer name, same error class, same Slack thread), attribute the session to T.
2. **Look forward** up to `spread_window_minutes` from the session end. Same logic — useful when pre-ticket diagnostic work precedes the agent opening the ticket.
3. If `pre_ticket_attribution: true`, prefer look-forward attribution for diagnostic work that precedes a ticket's first anchor. This is how 20 minutes of "I was poking at Grafana before I filed the ticket" gets correctly rolled into the ticket's total effort.
4. If neither lookback nor lookforward yields a plausible owner, the session is **untracked**.

When attributing, write a one-line *attribution rationale* (e.g., "Terminal session 09:18–09:25 attributed to ZD-12345: queried `customer_x_prod` ClickHouse instance, same customer referenced in the Zendesk anchor at 09:14"). Save these rationales — they're audit trail.

---

## Step 4: Detect and Log Context Switches

Walk the attributed session list. A **switch** is a transition from session_i (ticket T_a) to session_i+1 (ticket T_b) where `T_a != T_b` AND `(session_i+1.end - session_i+1.start) > switch_noise_threshold_seconds`.

For each switch record:
- `from_ticket` / `to_ticket`
- `at` timestamp
- `trigger` — read screenshots ±2 min around the switch to infer cause: "Slack ping from #support channel", "new Zendesk assignment notification", "self-initiated (no external trigger visible)", "post-meeting follow-up", "calendar event ended"
- `re_entry_cost` (only when returning to a previously-paused ticket) — minutes from switching back to the first productive action visible on screen (opening the right tab, typing in the right channel, running the next diagnostic command)

Also detect **parallel handling** windows — any 5-minute span where the agent's attributed sessions span 2+ tickets with rapid alternation.

---

## Step 5: Write Daily Context-Switching Report

Write `<output_dir>/<date>/context-switching.md`:

```markdown
# Context Switching — YYYY-MM-DD

## Summary

- **Tickets touched**: N
- **Total switches**: M (after filtering < {switch_noise_threshold_seconds}s noise)
- **Switches per active hour**: X.Y
- **Parallel handling windows**: K (windows where ≥2 tickets were alternated within 5 min)
- **Total re-entry cost**: Xh Ym (time spent re-orienting on resumed tickets)

## Switch Log

| Time  | From       | To         | Trigger                              | Re-entry cost |
|-------|------------|------------|--------------------------------------|---------------|
| 09:32 | ZD-12345   | ATLAN-7821 | Slack ping from #support             | —             |
| 10:14 | ATLAN-7821 | ZD-12345   | Self-initiated                       | 3m            |
| ...   | ...        | ...        | ...                                  | ...           |

## Per-Ticket Fragmentation

| Ticket     | Sessions | Total time | Longest stretch | Fragmentation score |
|------------|----------|------------|-----------------|---------------------|
| ZD-12345   | 4        | 42m        | 18m             | 0.71                |
| ATLAN-7821 | 2        | 28m        | 22m             | 0.21                |
| ...        | ...      | ...        | ...             | ...                 |

(Fragmentation score = 1 - (longest_stretch / total_time). 0 = single block, 1 = maximally fragmented.)

## Parallel Handling

- 09:30–09:35 — alternated ZD-12345 ↔ ATLAN-7821 (4 transitions in 5 min)
- ...

## One-Line Verdict

[Single sentence: was today fragmented or focused? Which tickets paid the largest fragmentation cost?]
```

---

## Step 6: Write Daily Ticket Summary

Write `<output_dir>/<date>/tickets-summary.md`:

```markdown
# Tickets Touched — YYYY-MM-DD

## Tracked

| Ticket     | Time spent | Sessions | Status visible on screen | Anchor sources |
|------------|------------|----------|--------------------------|----------------|
| ZD-12345   | 42m        | 4        | Awaiting customer        | zendesk, slack |
| ATLAN-7821 | 28m        | 2        | In progress              | linear         |
| ...        | ...        | ...      | ...                      | ...            |

## Untracked

| Topic slug              | Time spent | Sessions | Looks like              |
|-------------------------|------------|----------|-------------------------|
| slack-dm-customer-acme  | 12m        | 1        | Customer support in DM  |
| ...                     | ...        | ...      | ...                     |

## Links to evolving ticket docs

- [ZD-12345](../tickets/ZD-12345/process.md)
- [ATLAN-7821](../tickets/ATLAN-7821/process.md)
- ...
```

---

## Step 7: Write/Update Per-Ticket Documents

For each attributed ticket (tracked or untracked), write to `<output_dir>/tickets/<ID>/`. For untracked work, the ID is either:
- `untracked/<slug>` if `untracked_bucketing: slug` — slug is derived from observed content (e.g., `slack-dm-acme-snowflake-perms`). Keep slugs stable across days: if today's untracked work matches a prior slug's topic, append to the existing folder.
- `untracked/log` if `untracked_bucketing: flat` — a single log file shared across all untracked work.

These files are **evolving**, same semantics as the base skill's `processes/` folder. If a file exists, update it; do not overwrite.

### process.md

```markdown
# Process — <TICKET-ID>

**First observed**: YYYY-MM-DD
**Last observed**: YYYY-MM-DD
**Total time across sessions**: Xh Ym
**Sessions**: N (across M days)
**Status (last seen)**: [whatever was visible — "Awaiting customer", "Closed", "In progress", "Escalated"]

## Investigation Steps (chronological, deduped)

1. [Step] — [tool/app] — [evidence: timestamp + brief note]
2. [Step] — [tool/app] — [evidence]
3. ...

## Tools Used

| Tool       | Purpose                       | Total time |
|------------|-------------------------------|------------|
| Zendesk    | Reading customer messages     | 8m         |
| Grafana    | Querying logs                 | 14m        |
| DataGrip   | Querying ClickHouse           | 10m        |
| ...        | ...                           | ...        |

## People / Roles Involved

(If `redact_person_names: true`, use role descriptors only. Never write person names.)

- the customer (acme corp)
- the on-call SRE
- a Linear engineering owner

## Artifacts Referenced

- Grafana dashboard: <dashboard-name>
- Runbook: <doc-title>
- Query patterns: <signature>
- ...

## Day-by-Day Log

### YYYY-MM-DD
- Session 1: HH:MM–HH:MM (Xm) — [one-line summary of what happened]
- Session 2: HH:MM–HH:MM (Xm) — [one-line summary]
- Switches into this ticket: N | Switches out: M | Re-entry cost: Ym
```

### feedback.md

Self-coaching tone — direct, evidence-based, *not* evaluative. Audience is the agent themselves and the group reading shared reviews.

```markdown
# Feedback — <TICKET-ID>

## Process Observations

What went well in handling this ticket. What could have been done differently. Be evidence-based — cite specific session timestamps.

## Context Switch Cost on This Ticket

- Switches in: N (most common trigger: ...)
- Switches out: M (most common trigger: ...)
- Re-entry cost: Xm
- Implication: [was the fragmentation avoidable?]

## Knowledge Gap Signals

Where did the investigation slow down because information was hard to find? Examples:
- Spent 12m searching docs for a query pattern (knowledge gap candidate)
- Reproduced steps from memory that are in the runbook (runbook discoverability issue)

## What You Could Have Done Earlier

Cite specific moments. If the actual fix was discovered at minute 35, what could have surfaced it at minute 5?
```

### opportunities.md

Designed to be group-mineable. Each entry is a candidate for automation, FAQ, runbook update, or product improvement.

```markdown
# Opportunities — <TICKET-ID>

## Candidates

### [Short name]
- **Type**: Automation | FAQ | Runbook update | Tool integration | Product fix
- **Evidence**: What was observed (cite timestamps)
- **Frequency hypothesis**: How often does this ticket category repeat? (look at process.md across tickets)
- **Effort to address**: Low | Medium | High
- **Proposed shape**: [one-line description of what the automation/doc/fix would look like]

### [Next candidate]
...

## Pattern Notes

If this ticket fits a known recurring pattern (escalation type, customer category, error class), note it. These pattern names are the seeds for cross-ticket aggregation later.

- Pattern: [name] — also seen in <other ticket IDs>
```

### timeline.md

Raw evidence — the session log that backs every claim in the other three files.

```markdown
# Timeline — <TICKET-ID>

## All Sessions

### YYYY-MM-DD
- **HH:MM–HH:MM** (Xm) — apps: [App1 → App2 → App3]
  - [timestamp] [evidence line]
  - [timestamp] [evidence line]
- **HH:MM–HH:MM** (Xm) — apps: [...]
  - ...

### YYYY-MM-DD
- ...
```

---

## Step 8: Update Daily Digest with Ticket Lens

Append a `## Tickets Lens` section to the base skill's `<output_dir>/<date>/digest.md`. Do **not** replace the existing content — append only.

```markdown
## Tickets Lens

This day broken down by ticket investigation rather than by app:

| Ticket     | Time | % of day | Switches in | Switches out |
|------------|------|----------|-------------|--------------|
| ZD-12345   | 42m  | 9%       | 3           | 4            |
| ATLAN-7821 | 28m  | 6%       | 2           | 2            |
| untracked  | 18m  | 4%       | 2           | 2            |
| no-ticket  | 5h ... |        |             |              |

See: [context-switching.md](context-switching.md) · [tickets-summary.md](tickets-summary.md)
```

---

## Step 9: Apply Redaction

Before writing any of the markdown files above, scrub person names from output content if `redact_person_names: true`:

- Substitute role-based references: "the customer", "the customer's data eng", "an engineer", "the on-call SRE", "a Linear owner", "an Atlanian"
- Account/customer names PASS THROUGH unless `redact_account_names: true` — they are the signals the group needs to spot patterns
- Ticket IDs and URLs are not PII — keep them
- Do **not** alter raw screenshots, metadata JSON, or any non-markdown artifact

If you are uncertain whether a string is a person name (could be a product name, account name, or feature name), keep it unless the context clearly indicates a person.

---

## Rules

- Never fabricate session boundaries that the data doesn't support
- Every attribution should have an audit-trail rationale
- Treat ticket IDs as anchors, not as the definition of work scope
- Per-ticket files are evolving documents — append + update, never overwrite without merging
- Person-name redaction is enforced at write time, not capture time — raw screenshots are untouched
- If a session is shorter than `min_session_seconds`, drop it from per-ticket files but still count it in switch detection (it may be the trigger for a real switch)
- A noise-filtered tab flash is still recorded in the raw timeline; it just doesn't count as a switch or a session
