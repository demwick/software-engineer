#!/usr/bin/env bash
# --close-slice is the only forward path through a phase, and it decides from
# the verification records. Every case here runs the real chain — plan, a real
# check result, verify-phase.sh, write-review.sh, the close — because the bugs
# this suite exists to catch all lived in the seams between those scripts, not
# inside any one of them. Every refusal also asserts the state file did not
# move: a gate that refuses and advances anyway is worse than no gate.
# Contract: docs/specs/2026-09-15-evidence-gated-closing.md
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

SU="$REPO_ROOT/scripts/state-update.sh"
VP="$REPO_ROOT/scripts/verify-phase.sh"
WR="$REPO_ROOT/scripts/write-review.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

C1="GET /x returns 200"
C2="errors surface to the caller"

# A real project: a git repo, a roadmap, a plan that passes plan-validate.
( cd "$W" && git init -q && git config user.email e@x && git config user.name n ) >/dev/null
mkdir -p "$W/.se/plans" "$W/.se/verification"
cat > "$W/.se/roadmap.md" <<'EOF'
# Project Roadmap
## Phases
### Phase 1: the slice
**Status:** pending
### Phase 2: the next one
**Status:** pending
### Phase 3: the last one
**Status:** pending
EOF
write_plan() {  # write_plan <id>
    cat > "$W/.se/plans/$1.md" <<EOF
# Plan: $1
## Files
- src/app.sh
## Tasks
### Task 1: implement
- What: implement it
- Check: \`bash t.sh\`
- Commit: \`feat(x): do it\`
## Acceptance criteria
- [ ] $C1
- [ ] $C2
## Risks
- none — confirm: no
## Proof
- the suite green
EOF
}
write_plan phase-1
printf 'echo app\n' > "$W/src_placeholder" ; mkdir -p "$W/src"; printf 'echo app\n' > "$W/src/app.sh"
( cd "$W" && git add -A && git commit -qm "chore: init" ) >/dev/null

reset_state() {  # reset_state [current_phase] [total_phases]
    jq -n --argjson cp "${1:-1}" --argjson tp "${2:-3}" \
        '{schema_version:3, mode:"light", created:"2026-09-15",
          current_phase:$cp, total_phases:$tp}' > "$W/.se/state.json"
    find "$W/.se/verification" -name '*.closed.json' -delete 2>/dev/null || true
    find "$W/.se/verification" -name '*.accepted.json' -delete 2>/dev/null || true
}

tier1() {  # tier1 <id> <tests-status> [command] [exit] [reason]
    bash "$VP" "$W" "$1" planned "${2:-passed}" "${3:-bash t.sh}" "${4:-0}" "${5:-}" >/dev/null
}

# review <id> <jq-filter-applied-to-the-default-payload>
review() {
    local id="$1" filter="${2:-.}"
    jq -n --arg c1 "$C1" --arg c2 "$C2" \
        --argjson src "$(jq -c '.source' "$W/.se/verification/${id}.json")" \
        '{status:"pass", review:"complete", reason:"all criteria met",
          criteria:[{text:$c1,status:"met",evidence:"t.sh:3"},
                    {text:$c2,status:"met",evidence:"t.sh:9"}],
          findings:[], repeated_findings:[], out_of_scope:[], source:$src}' \
        | jq "$filter" | bash "$WR" "$W" "$id" >/dev/null 2>&1
}
# review_rc <id> <filter> → the writer's exit code
review_rc() {
    local id="$1" filter="${2:-.}" rc=0
    jq -n --arg c1 "$C1" --arg c2 "$C2" \
        --argjson src "$(jq -c '.source' "$W/.se/verification/${id}.json")" \
        '{status:"pass", review:"complete", reason:"all criteria met",
          criteria:[{text:$c1,status:"met",evidence:"t.sh:3"},
                    {text:$c2,status:"met",evidence:"t.sh:9"}],
          findings:[], repeated_findings:[], out_of_scope:[], source:$src}' \
        | jq "$filter" | bash "$WR" "$W" "$id" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}
# force_review <id> <filter> — bypass the writer to plant a record the writer
# would have refused. Used only to prove the closing gate re-validates rather
# than trusting the file's provenance.
force_review() {
    local id="$1" filter="$2"
    jq -n --arg c1 "$C1" --arg c2 "$C2" \
        --argjson src "$(jq -c '.source' "$W/.se/verification/${id}.json")" \
        '{record_version:1, id:"'"$id"'", status:"pass", review:"complete", reason:"r",
          criteria:[{text:$c1,status:"met",evidence:"e"},
                    {text:$c2,status:"met",evidence:"e"}],
          findings:[], repeated_findings:[], out_of_scope:[],
          tests_assessment:null, source:$src, verified_at:"2026-09-15T00:00:00Z"}' \
        | jq "$filter" > "$W/.se/verification/${id}.review.json"
}

rc()   { local c=0; bash "$SU" --project-dir "$W" --close-slice "$@" >/dev/null 2>&1 || c=$?; echo "$c"; }
msg()  { bash "$SU" --project-dir "$W" --close-slice "$@" 2>&1 >/dev/null || true; }
phase(){ jq -r '.current_phase' "$W/.se/state.json"; }
snap() { md5 -q "$W/.se/state.json" 2>/dev/null || md5sum "$W/.se/state.json" | cut -d' ' -f1; }

# =============================== the writer rejects what the gate would ======
reset_state 1 3; tier1 phase-1 passed

assert_eq 3 "$(review_rc phase-1 '.criteria = []')" "empty criteria rejected at write time"
assert_eq 3 "$(review_rc phase-1 '.criteria = [42]')" "a criteria entry that is not an object is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria[0] |= del(.evidence)')" "met without evidence is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria[0].evidence = "   "')" "whitespace is not evidence"
assert_eq 3 "$(review_rc phase-1 '.findings = [{severity:"blocker",file:"f",problem:"p",fix:"x"}]')" \
    "pass carrying a blocker is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria[1].status = "unmet" | .criteria[1].evidence = "missing handler"')" \
    "pass carrying an unmet criterion is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria[1].status = "unverified"')" \
    "complete review leaving a criterion unverified is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria[1].text = "something the plan never asked for"')" \
    "a criterion the plan does not ask for is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria = [.criteria[0], .criteria[0]]')" \
    "judging one criterion twice is rejected"
assert_eq 3 "$(review_rc phase-1 '.criteria = [.criteria[0]]')" \
    "leaving a plan criterion unjudged is rejected"
[ ! -e "$W/.se/verification/phase-1.review.json" ] || _fail "a rejected review was written to disk"

# The legitimate shapes still go through.
assert_eq 0 "$(review_rc phase-1 '.')" "a consistent review is accepted"
assert_eq 0 "$(review_rc phase-1 '.status = "fail" | .findings = [{severity:"blocker",file:"f",problem:"p",fix:"x"}]')" \
    "a blocker with verdict fail is accepted"
assert_eq 0 "$(review_rc phase-1 '.status = "partial" | .criteria[1].status = "unmet" | .criteria[1].evidence = "no handler"')" \
    "an unmet criterion with verdict partial is accepted"
assert_eq 0 "$(review_rc phase-1 '.review = "incomplete" | .status = "partial" | .criteria[1].status = "unverified"')" \
    "an unfinished review may leave a criterion unverified"

# ================================= the gate re-validates the files ===========
# A record the writer would have refused still has to be refused at close:
# .se/ is always open to the model, so provenance is not evidence.
reset_state 1 3; tier1 phase-1 passed
force_review phase-1 '.criteria = []'
assert_eq 6 "$(rc phase-1)" "planted empty criteria refused at close"
force_review phase-1 '.findings = [{severity:"blocker",file:"f",problem:"p",fix:"x"}]'
assert_eq 6 "$(rc phase-1)" "planted pass+blocker refused at close"
force_review phase-1 'del(.status)'
assert_eq 6 "$(rc phase-1)" "planted record with no status refused at close"
force_review phase-1 '.criteria[0] |= del(.evidence)'
assert_eq 6 "$(rc phase-1)" "planted evidence-free met refused at close"
force_review phase-1 '.record_version = 2'
assert_eq 6 "$(rc phase-1)" "an unknown review version is not evidence"
# Coverage is checked on both sides. The writer catches it for a reviewer that
# uses the writer; this catches it for a record that appeared some other way.
force_review phase-1 '.criteria = [.criteria[0]]'
assert_eq 6 "$(rc phase-1)" "a planted review that judges only half the plan refused at close"
force_review phase-1 '.criteria[1].text = "a criterion the plan never asked for"'
assert_eq 6 "$(rc phase-1)" "a planted review judging an unrelated criterion refused at close"
force_review phase-1 '.id = "some-other-slice"'
assert_eq 6 "$(rc phase-1)" "a review naming another slice cannot close this one"
assert_eq 1 "$(phase)" "none of the planted records advanced the phase"

# =================================== Tier-1 evidence =========================
reset_state 1 3; tier1 phase-1 passed; review phase-1
BEFORE="$(snap)"
rm -f "$W/.se/verification/phase-1.json"
assert_eq 5 "$(rc phase-1)" "no Tier-1 record → 5"
assert_eq "$BEFORE" "$(snap)" "a refusal leaves the state file byte-identical"

printf 'not json' > "$W/.se/verification/phase-1.json"
assert_eq 5 "$(rc phase-1)" "unparseable Tier-1 record → 5"

tier1 phase-1 failed "bash t.sh" 1
assert_eq 5 "$(rc phase-1)" "a red suite → 5"
assert_contains "$(msg phase-1)" "fail" "the refusal names the Tier-1 verdict"

tier1 phase-1 passed
jq '.record_version = 99' "$W/.se/verification/phase-1.json" > "$W/t" && mv "$W/t" "$W/.se/verification/phase-1.json"
assert_eq 5 "$(rc phase-1)" "an unknown Tier-1 version is not evidence"

# The plan is re-checked against the contract that gated it, not merely counted.
tier1 phase-1 passed; review phase-1
PLANBAK="$(mktemp)"; cp "$W/.se/plans/phase-1.md" "$PLANBAK"
printf '# Plan: phase-1\n## Files\n- a\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] %s\n- [ ] %s\n## Risks\n- none\n' "$C1" "$C2" > "$W/.se/plans/phase-1.md"
assert_eq 5 "$(rc phase-1)" "a plan that no longer satisfies plan-validate → 5"
cp "$PLANBAK" "$W/.se/plans/phase-1.md"

rm -f "$W/.se/plans/phase-1.md"
assert_eq 5 "$(rc phase-1)" "a plan that is gone → 5"
cp "$PLANBAK" "$W/.se/plans/phase-1.md"

# =============================== evidence must still apply ===================
# Source edited but not committed: HEAD still matches, the tree does not.
reset_state 1 3; tier1 phase-1 passed; review phase-1
printf 'echo changed\n' >> "$W/src/app.sh"
assert_eq 5 "$(rc phase-1)" "uncommitted source edits stale the evidence"
assert_contains "$(msg phase-1)" "src/app.sh" "the refusal names the drifted path"
( cd "$W" && git checkout -- src/app.sh )

# A new, unadded source file is source too.
printf 'echo new\n' > "$W/src/extra.sh"
assert_eq 5 "$(rc phase-1)" "an untracked new source file stales the evidence"
rm -f "$W/src/extra.sh"

# Source committed after the review: HEAD moved, and it moved over source.
printf 'echo changed\n' >> "$W/src/app.sh"
( cd "$W" && git add -A && git commit -qm "feat: change after review" ) >/dev/null
assert_eq 5 "$(rc phase-1)" "source committed after the review stales the evidence"
assert_eq 1 "$(phase)" "stale evidence never advances the phase"

# The plan edited after the review.
reset_state 1 3; tier1 phase-1 passed; review phase-1
printf '\n- [ ] a third criterion\n' >> "$W/.se/plans/phase-1.md"
assert_eq 5 "$(rc phase-1)" "a plan edited after the review stales the evidence"
cp "$PLANBAK" "$W/.se/plans/phase-1.md"

# An artifact-only commit is the close's own commit: it must not invalidate
# the very records it is committing.
reset_state 1 3; tier1 phase-1 passed; review phase-1
( cd "$W" && git add -A && git commit -qm "chore(se): close phase-1 artifacts" ) >/dev/null
assert_eq 0 "$(rc phase-1)" "an artifact-only commit does not stale the evidence"
assert_eq 2 "$(phase)" "the clean path advances one phase"

# ==================================== slice identity =========================
reset_state 1 3
write_plan phase-2; ( cd "$W" && git add -A && git commit -qm "docs(se): plan phase-2" ) >/dev/null
tier1 phase-2 passed; review phase-2
assert_eq 5 "$(rc phase-2)" "phase-2 evidence cannot close while the project is on phase 1"
assert_eq 1 "$(phase)" "a wrong-phase close changes nothing"

# An ad-hoc planned slice closes without advancing the roadmap.
write_plan csv-export; ( cd "$W" && git add -A && git commit -qm "docs(se): plan csv-export" ) >/dev/null
tier1 csv-export passed; review csv-export
assert_eq 0 "$(rc csv-export)" "an ad-hoc planned slice closes"
assert_eq 1 "$(phase)" "an ad-hoc slice does not advance the roadmap phase"
assert_file_exists "$W/.se/verification/csv-export.closed.json" "the close is recorded"
assert_jq "$(cat "$W/.se/verification/csv-export.closed.json")" '.slice_kind' '== "adhoc"' \
    "the close record knows what kind of slice it closed"

# A path-escaping id never reaches the filesystem.
assert_eq 2 "$(rc ../../etc/passwd)" "a slice id that escapes .se/verification is refused"

# ====================================== idempotency ==========================
reset_state 1 3; tier1 phase-1 passed; review phase-1
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
assert_eq 0 "$(rc phase-1)" "first close succeeds"
assert_eq 2 "$(phase)" "first close advances"
assert_eq 0 "$(rc phase-1)" "closing the same slice again is a no-op, not an error"
assert_eq 2 "$(phase)" "the phase does not advance twice"
assert_eq 0 "$(rc phase-1)" "and again"
assert_eq 2 "$(phase)" "still once"

# Interrupted between the close record and the state write: re-running finishes
# the job rather than re-judging evidence the close commit has already moved.
reset_state 1 3
jq -n '{record_version:1, id:"phase-1", slice_kind:"roadmap", from_phase:1,
        to_phase:2, completed:false, source:{}, accepted_risk:null,
        closed_at:"2026-09-15T00:00:00Z"}' > "$W/.se/verification/phase-1.closed.json"
rm -f "$W/.se/verification/phase-1.review.json"
assert_eq 0 "$(rc phase-1)" "an interrupted close resumes without the review in hand"
assert_eq 2 "$(phase)" "the interrupted close completes its state write"

# ====================================== last phase ===========================
reset_state 3 3; tier1 phase-1 passed; review phase-1
rm -f "$W/.se/verification/phase-1.closed.json"
# phase-1 evidence cannot close phase 3.
assert_eq 5 "$(rc phase-1)" "phase-1 evidence cannot close phase 3"
cat >> "$W/.se/roadmap.md" <<'EOF'
EOF
write_plan phase-3; ( cd "$W" && git add -A && git commit -qm "docs(se): plan phase-3" ) >/dev/null
tier1 phase-3 passed; review phase-3
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
assert_eq 0 "$(rc phase-3)" "the last phase closes"
assert_jq "$(cat "$W/.se/state.json")" '.completed' '== true' "last phase → completed"
assert_jq "$(cat "$W/.se/state.json")" '.current_phase' '<= 3' "current_phase never exceeds total_phases"
assert_eq 0 "$(rc phase-3)" "re-closing the last phase is a no-op"

# ====================================== accepted risk ========================
reset_state 1 3
tier1 phase-1 passed
review phase-1 '.status = "partial" | .criteria[1].status = "unmet" | .criteria[1].evidence = "no handler on the 500 path" | .findings = [{severity:"major",file:"src/app.sh:3",problem:"500 swallowed",fix:"surface it"}]'
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
assert_eq 7 "$(rc phase-1)" "partial without --accept-risk → 7"
assert_contains "$(msg phase-1)" "accept-risk" "the refusal names what would satisfy it"
BEFORE_REVIEW="$(cat "$W/.se/verification/phase-1.review.json")"
assert_eq 0 "$(rc phase-1 --accept-risk "shipping the 500 path for the demo")" "partial + accept-risk closes"
assert_eq 2 "$(phase)" "an accepted partial advances"
A="$W/.se/verification/phase-1.accepted.json"
assert_file_exists "$A" "the acceptance is recorded"
assert_jq "$(cat "$A")" '.reason' '| test("demo")' "the reason is kept"
assert_jq "$(cat "$A")" '.findings | length' '== 1' "the findings that stood are kept"
assert_eq "$BEFORE_REVIEW" "$(cat "$W/.se/verification/phase-1.review.json")" \
    "accepting a risk never edits the reviewer's record"

# accept-risk buys exactly one thing: a partial verdict.
reset_state 1 3; tier1 phase-1 failed "bash t.sh" 1; review phase-1 2>/dev/null || true
assert_eq 5 "$(rc phase-1 --accept-risk "please")" "accept-risk does not rescue a red suite"
reset_state 1 3; tier1 phase-1 passed
force_review phase-1 '.review = "incomplete" | .criteria[1].status = "unverified"'
assert_eq 6 "$(rc phase-1 --accept-risk "please")" "accept-risk does not rescue an unfinished review"
assert_eq 1 "$(phase)" "neither advanced the phase"

# ======================== a runner-less project can still close ==============
# The plan requires it; Tier-1 pass alone would make it impossible. The
# reviewer has to say, in the record, that what it saw stands in for the run.
reset_state 1 3
tier1 phase-1 not_run "" "" "no test runner in this project"
assert_eq 3 "$(review_rc phase-1 '.')" "with no test run, a review that does not assess it is rejected"
review phase-1 '.tests_assessment = {status:"accepted", reason:"both criteria checked by reading the rendered output"}'
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
assert_eq 0 "$(rc phase-1)" "a runner-less slice closes on an assessed review"
assert_eq 2 "$(phase)" "and advances"
T1J="$(cat "$W/.se/verification/phase-1.json")"
assert_jq "$T1J" '.tests.status' '== "not_run"' "not_run is still not_run after closing"
case "$T1J" in *"tests passed"*) _fail "a runner-less close claims tests passed" ;; esac

# The reviewer may also say the missing run is not coverable.
reset_state 1 3
tier1 phase-1 not_run "" "" "no test runner in this project"
review phase-1 '.tests_assessment = {status:"insufficient", reason:"the HTTP behaviour cannot be checked by reading"}'
assert_eq 7 "$(rc phase-1)" "an insufficient assessment does not close"
assert_eq 1 "$(phase)" "and does not advance"

# ============== the caller's own keys survive the close ======================
# The flow passes last_commit alongside --close-slice. An implementation that
# rebuilds the argument list instead of prepending to it drops that silently.
reset_state 1 3; tier1 phase-1 passed; review phase-1
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
assert_eq 0 "$(rc phase-1 last_commit=deadbeef)" "the close accepts extra key=value pairs"
assert_jq "$(cat "$W/.se/state.json")" '.last_commit' '== "deadbeef"'     "the caller's last_commit reaches the state file"
assert_jq "$(cat "$W/.se/state.json")" '.current_phase' '== 2' "and the phase still advanced"

# ================================ the guarded keys ===========================
g()    { local c=0; bash "$SU" --project-dir "$W" "$@" >/dev/null 2>&1 || c=$?; echo "$c"; }
gmsg() { bash "$SU" --project-dir "$W" "$@" 2>&1 >/dev/null || true; }
reset_state 1 3
assert_eq 8 "$(g completed=true)"     "completed=true through the generic path → 8"
assert_eq 8 "$(g current_phase=2)"    "a forward current_phase → 8"
assert_eq 8 "$(g current_phase=3 last_commit=abc)" "a forward move hidden among other keys → 8"
# jq parses these as numbers, so a guard that only looks at the string shape
# waves them straight through into current_phase.
assert_eq 8 "$(g current_phase=2e0)"  "2e0 is the number 2 → 8"
assert_eq 8 "$(g current_phase=1.5)"  "a fractional phase → 8"
assert_eq 8 "$(g current_phase=+2)"   "a signed integer → 8"
assert_contains "$(gmsg completed=true)" "close-slice" "the refusal names the operation to use"
assert_eq 1 "$(phase)" "no guarded refusal changed the phase"

# The legitimate transitions stay open.
assert_eq 0 "$(g total_phases=5)"     "extending a roadmap still works"
assert_eq 0 "$(g completed=false)"    "adding a milestone to a finished project still works"
assert_eq 0 "$(g current_phase=1)"    "rewriting the same phase still works"
reset_state 3 5
assert_eq 0 "$(g current_phase=2)"    "moving back still works"

# ============ the close does not launder the keys it guards ==================
# The guard used to live in the `else` of the close branch, so --close-slice
# accepted the very keys the generic path refuses — and flow-light teaches
# appending `last_commit=<sha>` to that exact call, so the tail is not
# adversarial, it is prescribed.
reset_state 1 3; tier1 phase-1 passed; review phase-1
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
BEFORE="$(snap)"
assert_eq 8 "$(rc phase-1 completed=true)"          "completed=true is refused on the close call too"
assert_eq "$BEFORE" "$(snap)"                        "and changes nothing"
assert_eq 8 "$(rc phase-1 current_phase=5)"         "a forward phase is refused on the close call too"
assert_eq 8 "$(rc phase-1 last_commit=abc completed=true)" "hidden among legitimate keys, still refused"
assert_eq "$BEFORE" "$(snap)"                        "still nothing"
# The prescribed shape keeps working.
assert_eq 0 "$(rc phase-1 last_commit=deadbeef)"    "the documented last_commit= tail still closes"
assert_eq 2 "$(phase)"                               "and advances exactly one phase"

# ================= a value has to be the right shape, not just the right text =
reset_state 1 3
assert_eq 8 "$(g 'current_phase="4"')"   "a JSON string phase is refused"
assert_eq 1 "$(phase)"                    "and is not written"
assert_eq 8 "$(g 'current_phase=[2]')"   "an array phase is refused"
assert_eq 8 "$(g 'current_phase=0x2')"   "a non-numeric literal phase is refused"
assert_eq 8 "$(g 'completed="true"')"    "a JSON string completed is refused"
assert_eq 8 "$(g 'completed=1')"         "a numeric completed is refused"
assert_eq 1 "$(phase)"                    "none of them landed"
assert_eq 0 "$(g current_phase=1)"        "a real integer at the same phase still works"

# ============ total_phases is the denominator of the completed decision ======
# Closing is gated on evidence; the caller used to move the finish line
# instead. Two commands took a five-phase project to "completed" on phase 1.
reset_state 1 5
assert_eq 8 "$(g total_phases=1)"        "shrinking total_phases below the roadmap is refused"
assert_jq "$(cat "$W/.se/state.json")" '.total_phases' '== 5' "the denominator did not move"
assert_eq 0 "$(g total_phases=9)"        "extending a roadmap still works"

# ==================== a roadmap phase is not silently an ad-hoc slice ========
# roadmap.md is model-written markdown with no validator. A heading the regex
# missed used to fall through to `adhoc`: the close exited 0, the phase never
# advanced, and .closed.json then made every retry a no-op — the project could
# never advance again by any route, including the generic path, which refuses
# a forward phase by design.
reset_state 1 3; tier1 phase-1 passed; review phase-1
( cd "$W" && git add -A && git commit -qm "chore(se): artifacts" ) >/dev/null
RMBAK="$(mktemp)"; cp "$W/.se/roadmap.md" "$RMBAK"

# Ordinary punctuation the template does not show is accepted, not downgraded.
for sep in " —" "." ")" ""; do
    sed "s/^### Phase 1: the slice/### Phase 1${sep} the slice/" "$RMBAK" > "$W/.se/roadmap.md"
    K="$(rc phase-1)"
    assert_eq 0 "$K" "a heading written as 'Phase 1${sep}' still closes as a roadmap phase"
    assert_jq "$(cat "$W/.se/verification/phase-1.closed.json")" '.slice_kind' '== "roadmap"' \
        "'Phase 1${sep}' is a roadmap phase, not an ad-hoc slice"
    reset_state 1 3
done

# A heading nothing can match refuses, rather than wedging the project.
sed 's/^### Phase 1: the slice/### Phase One: the slice/' "$RMBAK" > "$W/.se/roadmap.md"
assert_eq 5 "$(rc phase-1)" "a roadmap with no matching heading refuses instead of downgrading"
[ ! -e "$W/.se/verification/phase-1.closed.json" ] || _fail "a refused close still wrote its close record"
assert_eq 1 "$(phase)" "and the phase did not move"
cp "$RMBAK" "$W/.se/roadmap.md"
assert_eq 0 "$(rc phase-1)" "with the heading fixed it closes"
assert_eq 2 "$(phase)" "and advances"

# ================= a project nested inside a repo is still a project ========
# git reports paths from the repository root; the artifact test matches
# project-relative ones. Unstripped, a monorepo package read its own .se/
# files as changed source and could never close — and committing them only
# moved them from the status list into the diff list, so it never cleared.
NEST="$(mktemp -d)"
( cd "$NEST" && git init -q && git config user.email e@x && git config user.name n ) >/dev/null
mkdir -p "$NEST/apps/web/.se/plans" "$NEST/apps/web/src" "$NEST/apps/api/src"
cp "$RMBAK" "$NEST/apps/web/.se/roadmap.md"
cp "$W/.se/plans/phase-1.md" "$NEST/apps/web/.se/plans/phase-1.md"
printf 'echo web\n' > "$NEST/apps/web/src/app.sh"
printf 'echo api\n' > "$NEST/apps/api/src/api.sh"
jq -n '{schema_version:3, mode:"light", created:"2026-09-15", current_phase:1, total_phases:3}' \
    > "$NEST/apps/web/.se/state.json"
( cd "$NEST" && git add -A && git commit -qm "chore: monorepo" ) >/dev/null

bash "$VP" "$NEST/apps/web" phase-1 planned passed "bash t.sh" 0 >/dev/null
jq -n --arg c1 "$C1" --arg c2 "$C2" \
    --argjson src "$(jq -c '.source' "$NEST/apps/web/.se/verification/phase-1.json")" \
    '{status:"pass", review:"complete", reason:"ok",
      criteria:[{text:$c1,status:"met",evidence:"e"},{text:$c2,status:"met",evidence:"e"}],
      findings:[], source:$src}' | bash "$WR" "$NEST/apps/web" phase-1 >/dev/null
nrc=0; bash "$SU" --project-dir "$NEST/apps/web" --close-slice phase-1 >/dev/null 2>&1 || nrc=$?
assert_eq 0 "$nrc" "a project nested in a repo closes"
assert_eq 2 "$(jq -r '.current_phase' "$NEST/apps/web/.se/state.json")" "and advances"

# A sibling package's change is not this slice's source drift.
jq -n '{schema_version:3, mode:"light", created:"2026-09-15", current_phase:1, total_phases:3}' \
    > "$NEST/apps/web/.se/state.json"
rm -f "$NEST/apps/web/.se/verification/phase-1.closed.json"
printf 'echo api changed\n' >> "$NEST/apps/api/src/api.sh"
nrc=0; bash "$SU" --project-dir "$NEST/apps/web" --close-slice phase-1 >/dev/null 2>&1 || nrc=$?
assert_eq 0 "$nrc" "a sibling package's edit is not this slice's drift"
# This package's own source still is.
jq -n '{schema_version:3, mode:"light", created:"2026-09-15", current_phase:1, total_phases:3}' \
    > "$NEST/apps/web/.se/state.json"
rm -f "$NEST/apps/web/.se/verification/phase-1.closed.json"
printf 'echo web changed\n' >> "$NEST/apps/web/src/app.sh"
nrc=0; bash "$SU" --project-dir "$NEST/apps/web" --close-slice phase-1 >/dev/null 2>&1 || nrc=$?
assert_eq 5 "$nrc" "this package's own source drift still refuses"
rm -rf "$NEST"

# ====================== a severity the rules cannot read ====================
# The verdict rules compare against the literal words blocker and major. A
# finding with any other severity was invisible to them, so a single typo
# turned a fail into a clean close.
reset_state 1 3; tier1 phase-1 passed
sev_filter() { printf '.findings = [{severity: %s, file: "f", problem: "p", fix: "x"}]' "$1"; }
for sev in '"critical"' '"Blocker"' '"high"' '["blocker"]' 'null'; do
    assert_eq 3 "$(review_rc phase-1 "$(sev_filter "$sev")")" \
        "severity $sev is rejected, not silently ignored"
done
assert_eq 0 "$(review_rc phase-1 '.status = "fail" | '"$(sev_filter '"blocker"')")" \
    "blocker with verdict fail is accepted"
assert_eq 0 "$(review_rc phase-1 '.status = "partial" | '"$(sev_filter '"major"')")" \
    "major with verdict partial is accepted"
assert_eq 0 "$(review_rc phase-1 "$(sev_filter '"minor"')")" "minor with verdict pass is accepted"
assert_eq 0 "$(review_rc phase-1 "$(sev_filter '"nit"')")" "nit with verdict pass is accepted"

# ================== an unborn HEAD is not a revision ========================
# `git rev-parse HEAD` prints the literal "HEAD" and exits 128 on a repo with
# no commits, and the record then named a revision no close could accept.
UNBORN="$(mktemp -d)"
( cd "$UNBORN" && git init -q ) >/dev/null
mkdir -p "$UNBORN/.se/plans"
jq -n '{schema_version:3, mode:"light", created:"2026-09-15", current_phase:1, total_phases:1}' > "$UNBORN/.se/state.json"
cp "$W/.se/plans/phase-1.md" "$UNBORN/.se/plans/phase-1.md"
bash "$VP" "$UNBORN" phase-1 planned passed "bash t.sh" 0 >/dev/null
assert_jq "$(cat "$UNBORN/.se/verification/phase-1.json")" '.source.head_commit' '== null' \
    "an unborn HEAD records null, not the string HEAD"
rm -rf "$UNBORN"

echo "PASS: a slice closes on evidence, or it does not close"
