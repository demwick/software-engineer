# Behavioral evals

These suites test **LLM-decision quality** — the actual value of the plugin —
rather than bash plumbing. Today that means: does `triage` route a prompt to the
right flow (`direct-apply` / `light-plan` / `full-flow`)?

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

## Cost

One `claude -p` call per fixture line (~12 calls), each loading the plugin. Expect
a handful of cents and a minute or two of wall time per run. Run locally before a
release or on a nightly schedule, not on every push.

## Caveat

Routing classification is driveable headless; the interactive parts of the flows
(clarify's `AskUserQuestion`) are not — those still need the manual checklist in
`TESTING.md`.
