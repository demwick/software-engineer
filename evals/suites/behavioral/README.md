# Behavioral evals

These suites test **LLM-decision quality** — the actual value of the plugin —
rather than bash plumbing. Two questions live here: does `triage` route a prompt
to the right flow (`direct-apply` / `light-plan` / `full-flow`), and is each
candidate instruction block still load-bearing or has the model absorbed it
(`instruction-noop`)?

They are **gated and excluded from CI on purpose.** GitHub Actions cannot run the
`claude` CLI, and these evals cost tokens, so they only run when you opt in:

```bash
SE_BEHAVIORAL_EVALS=1 bash evals/suites/behavioral/triage-routing.sh
```

Without `SE_BEHAVIORAL_EVALS=1` (or without `claude` on PATH) the suite prints a
`skip:` line and exits **99**, which `bash evals/run.sh` reports as an explicit
`SKIP` (not a silent pass) — so the default gate stays green while the skip is
honestly accounted. The **deterministic** behavioral suites in this directory
(`executor-verification-fires`, `red-proof-catches-theater`, `stop-gate-blocks`)
do run in the default gate; only this LLM-in-the-loop routing suite is opt-in.

## What it does

For each line in `evals/fixtures/behavioral/triage-routing.jsonl`
(`{prompt, expected_route, why}`), it drives `claude` headless in print mode,
asks only for the route label, and asserts the returned label matches
`expected_route`. The single function `run_triage_classification` is the only
place that talks to the CLI — fix the invocation there if a future `claude`
release changes the flag.

## instruction-noop

Hard Rule 8's compensation-vs-preference test, made runnable. For each line in
`evals/fixtures/behavioral/instruction-noop.jsonl` it puts the same task to the
model twice — once alone, once with the instruction block sliced live out of the
file it ships in — and grades both free-form responses against the fixture's
rubric with a second call. The block is **load-bearing** when the baseline fails
the rubric and the block flips it, **absorbed** when the baseline already passes,
and **ineffective** when even the treated run fails.

An absorbed block FAILS the suite on purpose. That is the alarm you want firing
on a model upgrade, which is exactly when instruction budget needs re-spending.

Two design points are load-bearing and easy to undo by accident:

- **The subject is never offered the two labels.** An A/B question that names the
  good answer measures recognition, not behavior — every block here reads as
  absorbed under that weaker probe, so the verdict would be worthless. The
  subject does the task; a separate judge call assigns the label.
- **The run is isolated**: `--setting-sources ""` (the user's own `CLAUDE.md`
  otherwise supplies some of the behavior under test), no `--plugin-dir`, and
  cwd in a temp dir outside this repo.

When adding a rubric, sanity-check the judge with a response that clearly
violates it and confirm it returns the negative label — a judge that always
agrees produces a clean sweep of false "absorbed" verdicts.

## Cost

`triage-routing`: one `claude -p` call per fixture line (~12), each loading the
plugin. `instruction-noop`: subject + judge × 2 conditions × `SE_NOOP_SAMPLES`
(default 3) per fixture — 48 calls for four fixtures. Expect a handful of cents
and a few minutes of wall time. Run locally before a release or on a nightly
schedule, not on every push.

## Caveat

Routing classification is driveable headless; the interactive parts of the flows
(clarify's `AskUserQuestion`) are not — those still need the manual checklist in
`TESTING.md`.
