---
name: adr
description: Record an Architecture Decision Record when a significant technical decision is made — database choice, auth strategy, sync vs async, monolith vs services, a framework or protocol commitment, anything expensive to reverse. **Invoked automatically by `/triage`'s full-flow** when the spec's trade-offs contain a real architectural fork, and usable directly when the user says "record this decision", "write an ADR", "document why we chose X". Writes a numbered, versioned record. Location is conditional: if claude-charter is installed it writes into `.claude/knowledge/adr/` in charter's template; otherwise into `.se/adr/`.
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

Capture an architectural decision while the reasoning is fresh: what forced it, what you weighed, what you chose, and the trade-off you accepted. An ADR is cheap insurance against re-litigating a settled decision six months later. Announce: **"Recording an ADR for \<decision\>."**

Decision: $ARGUMENTS

## Step 1: Decide whether this deserves an ADR

Write one only for decisions that are **significant and hard to reverse**:

- Data store / schema strategy, auth & identity model, sync vs async / queue vs direct, monolith vs services, a load-bearing framework or protocol, a public API shape, a security or compliance posture.

Do **not** write ADRs for routine choices (a variable name, a small refactor, which test helper to use). If it's reversible in an afternoon, it's not an ADR. When unsure, ask the user "worth an ADR?" rather than spamming records.

## Step 2: Choose the location (Detect & Defer)

```bash
if [ -d ".claude/knowledge/adr" ]; then echo "DIR=.claude/knowledge/adr"; else echo "DIR=.se/adr"; fi
```

- **charter present** (`.claude/knowledge/adr/` exists) → write there, in charter's `0000-template.md` format. This is the authoritative location; do **not** also write `.se/adr/`.
- **standalone** → write `.se/adr/`, creating it if needed (`mkdir -p .se/adr`). Use the same template for consistency.

You can confirm the ecosystem from `.se/state.json` `integrations.charter` if state exists; the directory probe above is authoritative and works even without `.se/`.

## Step 3: Number it

Find the highest existing `NNNN-*.md` in the chosen directory (ignore `0000-template.md`), add one, zero-pad to four digits:

```bash
DIR=<from step 2>
LAST=$(ls "$DIR" 2>/dev/null | grep -E '^[0-9]{4}-' | grep -v '^0000-' | sort | tail -1 | grep -oE '^[0-9]{4}' || echo "0000")
NEXT=$(printf '%04d' $((10#$LAST + 1)))
```

Slug: short kebab-case from the decision (`0007-use-postgres-over-dynamo.md`).

## Step 4: Write the record

Write `<DIR>/NNNN-<slug>.md` in this format (charter's template — use it in both modes):

```markdown
# NNNN: <short title, imperative mood>

- **Status:** Accepted
- **Date:** <YYYY-MM-DD>
- **Deciders:** <handles or "project author">

## Context

What problem forces this decision now? The status quo and its pain — technical, product, cost. Do not describe the solution here.

## Decision

The change, as a single sentence if possible, then the mechanism.

## Consequences

**Positive**
- What gets better.

**Negative**
- What gets worse. An ADR with no downside is hiding one.

**Neutral**
- What stays the same but is worth noting.

## Alternatives considered

1. **<option>.** Why rejected, in a sentence or two.
2. **<option>.** Why rejected.

## References

- Related spec (`.se/specs/<feature>.md`), issues, prior ADRs.
```

Link the originating spec under References, and if this decision supersedes an earlier ADR, set the old one's status to `Superseded by NNNN` and note it here.

## Step 5: Confirm

Tell the user the path and the one-sentence decision. Do not commit the ADR on its own unless asked — it rides along with the work it justifies.

## Rules

- **Significant + hard-to-reverse only.** Routine choices are not ADRs.
- **charter location wins when present.** Never fork an ADR across both locations.
- **Honest Negatives.** The accepted trade-off is the whole point — name it.
- **Numbered and append-only.** Never renumber or delete an ADR; supersede it.

## Related

- `/spec` — trade-offs flagged there graduate to an ADR here
- `/triage` full-flow — invokes this when the spec contains an architectural fork
- charter `.claude/knowledge/adr/0000-template.md` — the canonical template when charter is installed
