---
name: adr
description: Record an Architecture Decision Record for a significant, hard-to-reverse technical decision — data store, auth strategy, sync vs async, monolith vs services, a framework or protocol commitment. Invoked by triage's full-flow when the spec's trade-offs hold a real architectural fork; also directly — "record this decision", "write an ADR", "document why we chose X". Location follows the ecosystem: charter's `.claude/knowledge/adr/` when present, else `.se/adr/`.
argument-hint: [the decision to record]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# adr

Capture a decision while the reasoning is fresh: what forced it, what was weighed, what was chosen, the trade-off accepted. Announce: **"Recording an ADR for \<decision\>."**

Decision: $ARGUMENTS

## Step 1: Does it deserve one?

Only decisions that are significant **and** hard to reverse: data store or schema strategy, auth and identity model, sync vs async, monolith vs services, a load-bearing framework or protocol, a public API shape, a security or compliance posture. Reversible in an afternoon → not an ADR. Unsure → ask "worth an ADR?".

## Step 2: Location (Detect & Defer)

```bash
if [ -d ".claude/knowledge/adr" ]; then echo "DIR=.claude/knowledge/adr"; else echo "DIR=.se/adr"; fi
```

charter present → write there in charter's `0000-template.md` format, and nowhere else. Standalone → `.se/adr/` (`mkdir -p`), same template.

## Step 3: Number

```bash
LAST=$(ls "$DIR" 2>/dev/null | grep -E '^[0-9]{4}-' | grep -v '^0000-' | sort | tail -1 | grep -oE '^[0-9]{4}' || echo "0000")
NEXT=$(printf '%04d' $((10#$LAST + 1)))
```

Slug: kebab-case from the decision (`0007-use-postgres-over-dynamo.md`).

## Step 4: Write `<DIR>/NNNN-<slug>.md`

```markdown
# NNNN: <short title, imperative mood>

- **Status:** Accepted
- **Date:** <YYYY-MM-DD>
- **Deciders:** <handles or "project author">

## Context
What forces this decision now — the status quo and its pain. Not the solution.

## Decision
The change, one sentence if possible, then the mechanism.

## Consequences
**Positive** — what gets better.
**Negative** — what gets worse. An ADR with no downside is hiding one.
**Neutral** — what stays the same but is worth noting.

## Alternatives considered
1. **<option>.** Why rejected.
2. **<option>.** Why rejected.

## References
- The spec (`.se/specs/<slug>.md`), issues, prior ADRs.
```

Superseding an earlier ADR: set the old one's status to `Superseded by NNNN` and say so here.

## Step 5: Confirm

Tell the user the path and the one-sentence decision. The ADR is committed with the work it justifies (the flow's bootstrap or close commit), not on its own.

## Rules

- Numbered and append-only: never renumber or delete; supersede.
- charter's location wins when present; never fork an ADR across both.
- Honest Negatives — the accepted trade-off is the point.
