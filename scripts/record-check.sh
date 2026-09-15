#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# record-check.sh — the one place that says whether verification evidence is
# usable. `write-review.sh` calls it before it writes, `state-update.sh
# --close-slice` calls it before it advances. Two consumers, one policy: a
# second copy would drift, and the copy that drifts is the one that says yes.
#
# It answers three questions the records cannot answer about themselves:
#   is each record internally consistent (does the label match the evidence
#   beside it), do the two records describe the same work, and does that work
#   still describe the tree we are about to close.
#
# Contract: docs/specs/2026-09-15-verification-contract.md
#           docs/specs/2026-09-15-evidence-gated-closing.md
#
# Usage:
#   bash record-check.sh <project-dir> <id> review <candidate-file>
#       Validate a Tier-2 record that has not been written yet: shape,
#       internal consistency, and — when Tier-1 exists — criteria coverage
#       and revision agreement. No freshness check: the review is being
#       written now, against whatever the tree is now.
#
#   bash record-check.sh <project-dir> <id> close [--accept-risk]
#       The full closing gate: both records, their agreement, the plan they
#       claim to satisfy, the verdict, and whether the evidence still applies
#       to the current source.
#
# Exit codes:
#   0 — usable
#   2 — usage error, or jq missing
#   5 — no usable Tier-1 evidence (missing, malformed, contradicted, wrong
#       slice, or no longer applicable to the current source)
#   6 — no usable review (missing, malformed, unfinished, or produced against
#       different material)
#   7 — the verdict does not permit closing

set -uo pipefail

PROJECT_DIR="${1:-}"
ID="${2:-}"
MODE="${3:-}"
ARG4="${4:-}"

usage() { echo "record-check: $1" >&2; exit 2; }

[ -n "$PROJECT_DIR" ] && [ -n "$ID" ] && [ -n "$MODE" ] || \
    usage "usage: record-check.sh <project-dir> <id> review <file> | close [--accept-risk]"
command -v jq >/dev/null 2>&1 || usage "jq is required"

# A slice id is a file name, and it is read from .se/.active — which the model
# can write. Anything that can leave .se/verification/ turns "validate this
# record" into "read that file", so the id is constrained to what a plan id
# can legitimately be before it is ever pasted into a path.
case "$ID" in
    *[!A-Za-z0-9._-]*|.*|"") usage "invalid slice id '${ID}' — use letters, digits, dot, dash, underscore" ;;
esac

STATE_DIR="$PROJECT_DIR/.se"
T1="$STATE_DIR/verification/${ID}.json"
T2="$STATE_DIR/verification/${ID}.review.json"
PLAN="$STATE_DIR/plans/${ID}.md"

reject() { echo "record-check: $1" >&2; [ -n "${2:-}" ] && echo "  $2" >&2; exit "$3"; }

# ---------------------------------------------------------------- Tier 2 ----
# The review's own consistency. Every rule here answers a way the record can
# say two things at once: a verdict that contradicts its findings, a criterion
# marked met with nothing behind it, an entry that is not a criterion at all.
REVIEW_RULES='
def nonempty($s): ($s | type == "string") and (($s | gsub("\\s";"")) != "");
if (.status? | IN("pass","partial","fail")) | not
  then "status must be pass|partial|fail, got: \(.status|tostring)"
elif (.review? | IN("complete","incomplete")) | not
  then "review must be complete|incomplete, got: \(.review|tostring)"
elif (.criteria | type) != "array"
  then "criteria must be an array"
elif (.criteria | length) == 0
  then "criteria is empty — a review with nothing to review against is not a review"
elif ([.criteria[] | type != "object"] | any)
  then "every criteria entry must be an object with text and status"
elif ([.criteria[] | nonempty(.text) | not] | any)
  then "every criterion needs a non-empty text"
elif ([.criteria[] | (.status // "") | IN("met","unmet","unverified") | not] | any)
  then "every criteria status must be met|unmet|unverified"
elif ([.criteria[] | select(.status == "met" or .status == "unmet") | nonempty(.evidence) | not] | any)
  then "a criterion judged met or unmet needs evidence: \([.criteria[] | select((.status == "met" or .status == "unmet") and (nonempty(.evidence) | not)) | .text] | join(", "))"
elif ((.criteria | map(.text) | unique | length) != (.criteria | length))
  then "criteria repeats a text; each criterion is judged once"
elif ((.findings // []) | type) != "array"
  then "findings must be an array"
elif ([(.findings // [])[] | type != "object"] | any)
  then "every finding must be an object"
elif ([(.findings // [])[] | (.severity // "") | IN("blocker","major","minor","nit") | not] | any)
  then "every finding severity must be blocker|major|minor|nit — a severity the verdict rules do not recognise is invisible to them"
elif (((.findings // []) | map(.severity // "") | index("blocker")) != null) and .status != "fail"
  then "a blocker finding with verdict \(.status) — a blocker is a fail"
elif (([.criteria[] | select(.status == "unmet")] | length) > 0) and (.status | IN("partial","fail") | not)
  then "unmet criteria with verdict \(.status) — an unmet criterion is at best partial"
elif (((.findings // []) | map(.severity // "") | index("major")) != null) and (.status | IN("partial","fail") | not)
  then "a major finding with verdict \(.status) — a major is at best partial"
elif (([.criteria[] | select(.status == "unverified")] | length) > 0) and .review != "incomplete"
  then "criteria left unverified while review says complete — an unreached criterion is an unfinished review"
elif (.source | type) != "object"
  then "source must be an object binding the review to a plan and a revision"
elif (.tests_assessment? != null) and (((.tests_assessment.status? // "") | IN("accepted","insufficient") | not) or (nonempty(.tests_assessment.reason?) | not))
  then "tests_assessment needs status accepted|insufficient and a non-empty reason"
else empty end'

check_review_file() {  # <path>
    local f="$1" problem
    jq -e . "$f" >/dev/null 2>&1 || reject "the review is not valid JSON" "" 6
    problem=$(jq -r "$REVIEW_RULES" "$f" 2>&1)
    if [ -n "$problem" ]; then
        case "$problem" in
            jq:*|*"error"*"at <stdin>"*) reject "the review could not be validated: $problem" "" 6 ;;
        esac
        reject "$problem" "" 6
    fi
}

# Tier 2 must account for exactly the criteria Tier 1 inventoried: not a
# subset (a criterion nobody judged), not a superset (a criterion nobody
# asked for), not a multiset (one judged twice under two verdicts).
check_coverage() {  # <tier1> <tier2-candidate>
    local problem
    problem=$(jq -rn --slurpfile a "$1" --slurpfile b "$2" '
        ($a[0].criteria // [] | map(.text)) as $want
        | ($b[0].criteria // [] | map(.text)) as $got
        | (($want - $got) | unique) as $missing
        | (($got - $want) | unique) as $extra
        | if ($missing | length) > 0 then "the review does not judge every plan criterion — missing: \($missing | join(", "))"
          elif ($extra | length) > 0 then "the review judges criteria the plan does not ask for: \($extra | join(", "))"
          else empty end' 2>/dev/null)
    [ -z "$problem" ] || reject "$problem" \
        "Tier 2 judges exactly the criteria Tier 1 inventoried from the plan" 6
}

check_same_source() {  # <tier1> <tier2>
    jq -e --slurpfile t1 "$1" '.source == $t1[0].source' "$2" >/dev/null 2>&1 || \
        reject "the review's source does not match the Tier-1 record" \
            "the review read a different plan or revision; re-run it against the current one" 6
}

# ---------------------------------------------------------- source scope ----
# The one definition of what counts as "the source this evidence describes".
# Everything else in the tree is the flow's own bookkeeping: the artifacts it
# writes while closing, and the CLAUDE.md notes it appends. Changing those
# cannot change what a test exercised, so they never stale the evidence —
# which is what keeps an artifact-only close commit from invalidating the
# very records it is committing.
# This list is `pre-guard`'s is_open() — the paths the flow and its agents
# write while working. They are the same set for the same reason: a path the
# gate lets an agent write without a plan cannot be a path whose change
# invalidates a plan's evidence. Observed live: a reviewer wrote its own
# .claude/agent-memory/ notes while reviewing, and the close then refused its
# own review as stale.
is_artifact_path() {
    case "$1" in
        .se|.se/*|CLAUDE.md|.gitignore|.claude|.claude/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Every source path that moved since the recorded revision: committed,
# staged, unstaged, or newly created and not yet added. A record bound only
# to HEAD misses the last two entirely.
source_drift() {  # <head_commit> ; echoes drifted paths
    local head="$1" line p prefix
    # git reports paths from the repository root; is_artifact_path matches
    # project-relative ones. Without stripping the prefix, a project nested in
    # a repo — a monorepo package — reads its own .se/ artifacts as changed
    # source and can never close; committing them only moves them from the
    # status list into the diff list, so it never clears. The same strip is
    # what keeps a sibling package's edit out of this slice's drift.
    prefix=$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --show-prefix 2>/dev/null || echo "")
    ( cd "$PROJECT_DIR" 2>/dev/null || exit 0
      git diff --name-only "${head}..HEAD" 2>/dev/null
      git status --porcelain --untracked-files=all 2>/dev/null | while IFS= read -r line; do
          p="${line:3}"
          case "$p" in *" -> "*) printf '%s\n' "${p%% -> *}"; p="${p##* -> }" ;; esac
          printf '%s\n' "$p"
      done
    ) | sed 's/^"//; s/"$//' | sort -u | while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -n "$prefix" ]; then
            case "$p" in
                "$prefix"*) p="${p#"$prefix"}" ;;
                *) continue ;;
            esac
        fi
        is_artifact_path "$p" || printf '%s\n' "$p"
    done
}

# --------------------------------------------------------------- review -----
if [ "$MODE" = "review" ]; then
    [ -n "$ARG4" ] && [ -f "$ARG4" ] || usage "review mode needs a candidate file"
    check_review_file "$ARG4"
    # Tier 1 may legitimately be absent here (the verifier's recovery path
    # runs the suite itself). When it is present its inventory is binding.
    if [ -f "$T1" ] && jq -e . "$T1" >/dev/null 2>&1; then
        check_coverage "$T1" "$ARG4"
        # A not_run Tier 1 means the reviewer is the only evidence there is:
        # it has to say, in the record, whether what it saw stands in for the
        # run that never happened.
        if [ "$(jq -r '.tests.status // ""' "$T1")" = "not_run" ]; then
            jq -e '.tests_assessment != null' "$ARG4" >/dev/null 2>&1 || \
                reject "Tier 1 recorded no test run, so the review must assess it" \
                    'add tests_assessment: {status: "accepted"|"insufficient", reason: "..."}' 6
        fi
    fi
    exit 0
fi

[ "$MODE" = "close" ] || usage "unknown mode '${MODE}' — expected review or close"
ACCEPT_RISK=false
[ "$ARG4" = "--accept-risk" ] && ACCEPT_RISK=true

# ---------------------------------------------------------------- close -----
# Tier 1: the mechanical evidence.
[ -f "$T1" ] || reject "no Tier-1 record at .se/verification/${ID}.json" \
    "run the suite and record it: verify-phase.sh . ${ID} planned <result> <command> <exit>" 5
jq -e . "$T1" >/dev/null 2>&1 || reject "the Tier-1 record is not valid JSON" \
    "delete it and re-record the slice" 5
RV1=$(jq -r '.record_version // 0' "$T1" 2>/dev/null || echo 0)
case "$RV1" in ''|*[!0-9]*) RV1=0 ;; esac
[ "$RV1" -eq 1 ] || reject "the Tier-1 record is version '${RV1}', not the contract's version 1" \
    "re-verify this slice; an unknown record version is not evidence" 5
[ "$(jq -r '.id // ""' "$T1")" = "$ID" ] || \
    reject "the Tier-1 record names slice '$(jq -r '.id // ""' "$T1")', not '${ID}'" \
        "evidence from another slice cannot close this one" 5

# The plan is re-checked against the same contract that gated it at write
# time. Two criteria lines is what verify-phase.sh can see; whether they are
# observable, whether the plan still has its tasks and risks, is plan-validate's
# question, and a hand-edited plan never went past it.
[ -f "$PLAN" ] || reject "the plan .se/plans/${ID}.md is gone" \
    "the record claims a plan that no longer exists; restore it or re-plan the slice" 5
PV="$(cd "$(dirname "$0")" && pwd)/plan-validate.sh"
if [ -f "$PV" ]; then
    PV_OUT=$(bash "$PV" "$PLAN" 2>&1) || reject "the plan no longer satisfies plan-validate" \
        "$(printf '%s' "$PV_OUT" | head -2 | tr '\n' ' ')" 5
fi

TESTS_STATUS=$(jq -r '.tests.status // ""' "$T1")
ST1=$(jq -r '.status // ""' "$T1")

# Tier 2: a review that read this material and finished.
[ -f "$T2" ] || reject "no review at .se/verification/${ID}.review.json" \
    "run the verifier for ${ID}; it writes through write-review.sh" 6
check_review_file "$T2"
RV2=$(jq -r '.record_version // 0' "$T2" 2>/dev/null || echo 0)
case "$RV2" in ''|*[!0-9]*) RV2=0 ;; esac
[ "$RV2" -eq 1 ] || reject "the review is version '${RV2}', not the contract's version 1" \
    "re-run the verifier; an unknown record version is not evidence" 6
[ "$(jq -r '.id // ""' "$T2")" = "$ID" ] || \
    reject "the review names slice '$(jq -r '.id // ""' "$T2")', not '${ID}'" \
        "a review of another slice cannot close this one" 6
[ "$(jq -r '.review' "$T2")" = "complete" ] || \
    reject "review is $(jq -r '.review' "$T2"), not complete" \
        "the reviewer did not finish; see out_of_scope[] and re-run it" 6
check_same_source "$T1" "$T2"
check_coverage "$T1" "$T2"

# Does this evidence still describe the tree? plan_blob catches a plan edited
# after the review; source_drift catches code edited after it, committed or
# not. Neither is expressible as a status field, which is why the records
# carry a revision at all.
HEAD_REC=$(jq -r '.source.head_commit // ""' "$T1")
IN_REPO=false
( cd "$PROJECT_DIR" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 ) && IN_REPO=true
if [ "$IN_REPO" = true ]; then
    [ -n "$HEAD_REC" ] && [ "$HEAD_REC" != "null" ] || \
        reject "the evidence is not bound to a revision in a git project" \
            "re-record the slice so the record carries source.head_commit" 5
    ( cd "$PROJECT_DIR" && git cat-file -e "${HEAD_REC}^{commit}" 2>/dev/null ) || \
        reject "the recorded revision ${HEAD_REC} is not in this repository" \
            "the evidence was produced somewhere else; re-verify here" 5
    BLOB_REC=$(jq -r '.source.plan_blob // ""' "$T1")
    BLOB_NOW=$(cd "$PROJECT_DIR" && git hash-object ".se/plans/${ID}.md" 2>/dev/null || echo "")
    [ "$BLOB_REC" = "$BLOB_NOW" ] || \
        reject "the plan changed after it was verified" \
            "re-run the slice's checks and the review against the current plan" 5
    DRIFT=$(source_drift "$HEAD_REC")
    if [ -n "$DRIFT" ]; then
        reject "source changed after it was verified: $(printf '%s' "$DRIFT" | head -3 | tr '\n' ' ')" \
            "the evidence describes an older tree; re-run the checks and the review" 5
    fi
fi

# The verdict itself.
ST2=$(jq -r '.status' "$T2")
[ "$ST2" != "fail" ] || reject "the review verdict is fail" \
    "fix the findings and re-run the verifier" 7
jq -e '[.criteria[] | select(.status == "unverified")] | length == 0' "$T2" >/dev/null 2>&1 || \
    reject "the review leaves acceptance criteria unverified" \
        "every criterion needs met or unmet with evidence before a slice closes" 7

# Tier-1's own verdict, last — because the runner-less path needs the review
# in hand to decide it. A red check is never coverable: only a run that never
# happened can be stood in for.
case "$ST1" in
    pass) ;;
    fail)
        reject "Tier-1 status is fail" \
            "a failing check is not closed by a review or an accepted risk; fix it and re-record" 5
        ;;
    incomplete)
        [ "$TESTS_STATUS" = "not_run" ] || reject "Tier-1 status is incomplete" \
            "the slice has no usable mechanical evidence; re-record it" 5
        TA=$(jq -r '.tests_assessment.status // ""' "$T2")
        case "$TA" in
            accepted) ;;
            insufficient)
                reject "the reviewer judged the missing test run insufficient" \
                    "$(jq -r '.tests_assessment.reason // ""' "$T2")" 7
                ;;
            *)
                reject "no test run, and the review does not assess what stands in for it" \
                    'the reviewer must record tests_assessment: {status, reason}' 6
                ;;
        esac
        ;;
    *)
        reject "Tier-1 status is '${ST1}', which is not a status this contract defines" "" 5
        ;;
esac

if [ "$ST2" = "partial" ] && [ "$ACCEPT_RISK" = false ]; then
    reject "the review verdict is partial" \
        'fix the findings, or accept them explicitly: --accept-risk "<reason>"' 7
fi

exit 0
