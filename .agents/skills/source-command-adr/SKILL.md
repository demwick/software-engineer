---
name: "source-command-adr"
description: "Draft an Architectural Decision Record for the most recent architectural decision in this conversation."
---

# source-command-adr

Use this skill when the user asks to run the migrated source command `adr`.

## Command Template

# /adr

You are drafting an ADR based on an architectural decision made in
the current conversation. The goal is to capture the decision so a
future reader (human or agent) can evaluate whether its assumptions
still hold.

## Procedure

1. Identify the decision. Ask yourself:
   - What was decided?
   - What problem did it solve?
   - What alternatives were rejected, and why?
   If any of these are unclear from the conversation, **ask the
   user one specific question** to fill the gap. Do not invent.

2. Find the next ADR number by listing `.Codex/knowledge/adr/`
   (excluding `0000-template.md`). Use the next unused integer,
   zero-padded to four digits.

3. Create a new file at
   `.Codex/knowledge/adr/NNNN-short-title-slug.md` by copying
   `0000-template.md` and filling in:
   - **Title** (imperative mood, short).
   - **Status:** `Proposed`.
   - **Date:** today's date.
   - **Deciders:** the people involved, if known.
   - **Context:** the pain that led to the decision.
   - **Decision:** the change, in one sentence plus the mechanism.
   - **Consequences:** positive, negative, neutral — honestly.
   - **Alternatives considered:** at least two, with rejection
     reasons.

4. Report the path to the new ADR and its title.

## Known failure patterns to avoid

- **Do not** invent alternatives that were not actually discussed
  just to fill the section. Ask the user if the alternatives are
  unknown.
- **Do not** write a decision-less ADR. If no real decision was
  made, tell the user and do not create the file.
- **Do not** put implementation detail in the ADR. Link to the code
  or the PR, but the ADR is about the decision, not the code.
- **Do not** auto-approve. New ADRs start as `Proposed`, not
  `Accepted`.
