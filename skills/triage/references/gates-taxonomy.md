<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.

  The four-gate vocabulary below is adapted from the GSD ("Get Shit Done")
  project's gates reference (MIT © 2025 Lex Christopherson,
  github.com/gsd-build/get-shit-done), by way of NousResearch/hermes-agent.
  The prose here is original and maps the vocabulary onto this plugin's own
  mechanisms; only the four-type framing is borrowed.
-->

# Gates Taxonomy

Every validation checkpoint in a flow is one of four gate types. Naming the
type makes "what happens when this check fails?" explicit instead of ad hoc.
For each gate, the flow must answer three questions: **what triggers it**,
**what happens on failure**, and **who resumes from where**.

## The four types

### 1. Pre-flight — validate preconditions before starting

Blocks entry if conditions are unmet; creates no partial work. Recovery: fix
the precondition, retry.

In this plugin: `spec-validate.sh` before execute, the `.se/` existence check
in full-flow Step 0, "does a plan exist?" before the executor, "is this a git
repo?" before a commit.

### 2. Revision — evaluate output, loop back if insufficient

Loops to the producer with specific feedback, bounded by an iteration cap.
Recovery: producer addresses feedback, checker re-evaluates. Escalate early if
the issue count does not shrink between iterations (stall), and escalate
unconditionally after the cap — never loop forever.

In this plugin: the **auto-QA Stop hook** (tests fail → `block` decision →
Claude fixes → re-verify, capped at 2 retries via `.verify-attempts`), and the
verifier's `partial` verdict surfacing `unmet_criteria[]`.

### 3. Escalation — surface an unresolvable choice to the user

Pauses, presents options, waits. Never guesses, never picks a default.
Recovery: the user chooses; the flow resumes on the selected path.

In this plugin: **risk gates** (HIGH findings → explicit "confirm" required),
the executor's `gate` status (`gate-pending.json` confirmation), spec
contradictions (`_common.md` Rule 2 "Manage Confusion Actively"), and the
auto-QA hook giving up after 2 retries and reporting to the user.

### 4. Abort — stop to prevent damage or waste

Stops immediately, preserves state (checkpoint), reports the specific reason.
Recovery: the user investigates, fixes, restarts from the checkpoint.

In this plugin: the executor's `blocked` status (surface verbatim, stop — do
not retry), and `_common.md` Rule 5 "Stop-the-Line on Failure".

## Using this in a flow

When a flow step is a checkpoint, name its gate type and answer the three
questions inline. If a checkpoint seems to need a fifth type, it is almost
always a revision gate with extra branching or an escalation gate in disguise.
