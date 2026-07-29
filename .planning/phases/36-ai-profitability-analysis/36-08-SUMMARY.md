---
phase: 36-ai-profitability-analysis
plan: 08
subsystem: api
tags: [anthropic, claude, ai-grounding, sqlalchemy, decimal, structlog, profitability]

requires:
  - phase: 36-01
    provides: ProfitabilityRepository.upsert_finding + FindingUpsert + the DB length CHECKs
  - phase: 36-03
    provides: profitability_math (CandidateSignal, bands, fingerprints)
  - phase: 36-05
    provides: ai_grounding (collect_allowed_values, validate_grounding), call_claude_json_strict, PROFITABILITY_SYSTEM_PROMPT, GROUNDING_RETRY_TEMPLATE
  - phase: 36-07
    provides: ProfitabilityService.scan_candidates + the closed aggregates-only payload
provides:
  - "ProfitabilityService._draft_for: one Claude call per candidate with the D-05 validate-and-block loop (GROUNDING_RETRY_LIMIT = 1)"
  - "ProfitabilityService.publish_findings -> PublishResult(published, qualifying_fingerprints): the D-06 keep-set is every candidate, not just the published ones"
  - "PublishedFinding: the six fields plan 36-09's alerting step reads, resolved in the request session"
  - "_within_length_contract: the SERVICE half of the UI-SPEC length contract, checked against the same constants the DB CHECKs use"
  - "MAX_FINDINGS_PER_COMPANY_PER_NIGHT = 10, counted after validation"
  - "Keystone #1 green: a finding citing an absent figure is retried once, then dropped with nothing persisted and nothing alerted"
affects: [36-09, 36-10, ai-quote-planning]

tech-stack:
  added: []
  patterns:
    - "Validate-and-block with one bounded retry: the model is shown its own reply plus the literals it may not use, and a second failure drops the finding rather than publishing or clipping it"
    - "Fail-closed AI calls: call_claude_json_strict only — the shipped fallback parameter would publish a finding with no AI content behind it"
    - "Keep-set means still-qualifying, not successfully-narrated: publish returns every candidate's fingerprint so a transient API failure cannot resolve a live finding"
    - "Content-driven Claude mocks: replies are chosen from the request payload, never from call order, because bounded concurrency interleaves calls"
    - "Synthetic candidates for orchestration properties: cap and length behaviors are proven against one seeded project instead of a dozen"

key-files:
  created: []
  modified:
    - backend/app/features/finance/profitability_service.py
    - backend/tests/test_phase_36_e2e.py

key-decisions:
  - "_within_length_contract's docstring says 'rejected whole rather than shortened' — the task's own acceptance grep forbids the token 'truncate' anywhere in the service, so the plan's suggested wording would have failed it (same trap as 36-03 and 36-05)"
  - "The service checks lengths against profitability_models' MAX_* constants (the DB CHECK source), not the prompt module's copies, and a new test pins the two sets equal so the model can never be told a looser bound than the row is judged by"
  - "A confirmed reply with empty text is dropped as malformed (EMPTY_DRAFT_LOG_TEMPLATE): the prompt reserves empty strings for a dismissal, so publishing one would ship a blank card and a blank alert"
  - "The keystone drives publish_findings, not the drafting half — its zero-rows/zero-alerts assertions would be vacuous against a path that cannot persist; it also asserts the dropped candidate stays in the keep-set"
  - "Cap and length tests hand publish_findings synthetic ProfitabilityCandidates with distinct fingerprints against one seeded project; identical fingerprints would upsert onto a single open row and make a cap assertion meaningless"
  - "The mixed grounded/ungrounded mock answers from the payload's project_name, not from a positional side_effect list — gather_with_concurrency interleaves calls under its semaphore, so positional replies would be flaky"
  - "ProfitabilityCandidate gained a project_id property: the candidate.candidate.project_id double hop appears on every log line in the publish path"
  - "_persist takes a _PublishContext (company_id + target_date) so both it and _persist_publishable stay within CLAUDE.md's 3-argument limit"

patterns-established:
  - "Cap-after-validation is mutation-verified: moving the cap check ahead of the draft and length verdicts makes both cap tests fail (12 grounded -> 10 became 0 cap logs; 3 ungrounded + 10 grounded -> 7 findings), then the correct order restores 28/28"
  - "Every AI string is validated, not just the narrative — a parametrized test fabricates a figure in each of narrative, corrective_action and alert_summary in turn"

requirements-completed: [FINAI-01]

duration: 26min
completed: 2026-07-29
---

# Phase 36 Plan 08: Publish Path Summary

**`ProfitabilityService.publish_findings` — one Claude call per candidate under bounded concurrency, the D-05 validate-and-block loop with exactly one retry, over-length drafts rejected whole, a nightly cap counted after validation, and persistence through the idempotent upsert with the D-06 keep-set built from every candidate.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-07-29T21:59:57Z
- **Completed:** 2026-07-29T22:26:18Z
- **Tasks:** 2 (both TDD: 4 commits)
- **Files modified:** 2

## Accomplishments

- **Nothing reaches `ai_profitability_findings` ungrounded.** `_draft_for` validates all three AI strings against `collect_allowed_values(payload)`, names the offending literals back in one retry turn, and drops the finding on a second failure — keystone #1 asserts zero rows and zero `ai_profitability` alerts after exactly two Claude calls.
- **The nightly cap cannot be spent by a drop.** `MAX_FINDINGS_PER_COMPANY_PER_NIGHT` is counted over published findings only; three ungrounded candidates ahead of ten grounded ones still publish ten. Mutation-verified.
- **The D-06 keep-set means "still qualifying".** `PublishResult.qualifying_fingerprints` is every candidate's fingerprint, including ones whose call raised, whose draft was over-length, or that the cap dropped — so plan 36-09 can never resolve a live finding because of a transient API failure.
- **Over-length text is dropped whole.** No slice, no clamp, no shortening anywhere on the path; a draft exactly at 280/600 publishes and stores its full string.
- **Eligible non-candidates never reach the API** (2 calls for 5 eligible projects), and one candidate's failure leaves the rest of the company's run intact.

## Task Commits

1. **Task 1: per-candidate Claude call with the D-05 one-retry grounding loop**
   - `f8d7d22` (test — RED: 9 behaviors, keystone included)
   - `fdb82f0` (feat — GREEN: `_draft_for`, `FindingDraft`, `GROUNDING_RETRY_LIMIT`, `PROFITABILITY_MAX_OUTPUT_TOKENS`)
2. **Task 2: length contract, per-company nightly cap, and persistence**
   - `83d55a9` (test — RED: length/cap/persistence + keystone re-pointed at `publish_findings`)
   - `b9613e1` (feat — GREEN: `publish_findings`, `PublishResult`, `PublishedFinding`, `_within_length_contract`, `MAX_FINDINGS_PER_COMPANY_PER_NIGHT`)

## Files Created/Modified

- `backend/app/features/finance/profitability_service.py` — publish half: `publish_findings`, `_draft_for`, `_persist_publishable`, `_persist`, plus module helpers `_payload_turn`, `_retry_turns`, `_to_draft`, `_ungrounded_literals`, `_within_length_contract`, `_to_upsert`, `_jsonb_payload` and five run-log templates.
- `backend/tests/test_phase_36_e2e.py` — 13 new tests (23 → 28 test functions; the grounding test is parametrized over three fields), content-driven Claude mocks, the publish driver, and synthetic-candidate fixtures.

## Decisions Made

- **Prose avoids the token `truncate`.** The task's acceptance criteria grep for the ABSENCE of `truncate` in the service, so `_within_length_contract` documents "rejected whole rather than shortened". Third occurrence of this trap in Phase 36 (36-03, 36-05).
- **Length bounds come from `profitability_models`, and prompt-vs-DB agreement is now pinned.** The service rejects against the constants the DB CHECKs are built from; `test_prompt_and_database_state_the_same_length_bounds` fails if the prompt module's copies ever drift, which would otherwise turn every long finding into a silent drop.
- **A textless confirmation is a drop, not a publish** (Rule 2, below).
- **The keystone drives the full publish path.** Written in Task 1 against the drafting half, then re-pointed in Task 2's RED step so "zero rows, zero alerts" is asserted against code that could actually have written them, and extended to assert the dropped candidate remains in the keep-set.
- **Synthetic candidates for the cap and length tests.** Both are properties of the orchestration, not of detection; twelve real projects would buy twelve slow fixtures and no extra coverage. Fingerprints are distinct per candidate because identical ones would upsert onto one open row.
- **Mocks answer from payload content, not call order** — `gather_with_concurrency` interleaves calls under its semaphore.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] A confirmed reply with empty text is dropped instead of published**

- **Found during:** Task 1 (`_to_draft`)
- **Issue:** The plan validated grounding and length but nothing rejected `{"confirmed": true, "narrative": "", "corrective_action": "", "alert_summary": ""}`. Empty strings pass grounding (no figures) and pass the length bounds, so a malformed reply would have persisted a finding with no text — a blank card on `/financials/[projectId]` and a blank dashboard alert body. The prompt reserves empty strings for a *dismissal*.
- **Fix:** `_to_draft` returns `None` when any of the three strings is empty; `_draft_for` logs `EMPTY_DRAFT_LOG_TEMPLATE` and drops the candidate. `_ai_string` also coerces a missing or null field defensively so a JSON `null` can never reach a NOT NULL column.
- **Files modified:** `backend/app/features/finance/profitability_service.py`
- **Verification:** `test_confirmed_finding_without_text_is_dropped` — one Claude call, no draft, zero rows, drop line logged.
- **Committed in:** `fdb82f0` (Task 1 commit)

**2. [Rule 2 - Missing Critical] Prompt-vs-database length-bound drift guard**

- **Found during:** Task 2 (`_within_length_contract`)
- **Issue:** `prompts/profitability_system.py` and `profitability_models.py` each declare the three bounds as independent literals (600/280/280). The service must reject against the DB's numbers, but the model is instructed with the prompt's — if the two ever diverge, every finding written to the looser bound becomes a silent service-side drop with no failing test.
- **Fix:** Added `test_prompt_and_database_state_the_same_length_bounds` pinning `NARRATIVE_MAX_CHARS == MAX_NARRATIVE_LENGTH`, `CORRECTIVE_ACTION_MAX_CHARS == MAX_CORRECTIVE_ACTION_LENGTH`, `ALERT_SUMMARY_MAX_CHARS == MAX_ALERT_SUMMARY_LENGTH`.
- **Files modified:** `backend/tests/test_phase_36_e2e.py`
- **Verification:** Test passes; it is a pure constant assertion with no DB cost.
- **Committed in:** `83d55a9` (Task 2 RED commit)

**3. [Rule 1 - Bug] `_draft_for` moved below the read half, and a `project_id` property added**

- **Found during:** Task 2 (class layout)
- **Issue:** Task 1 inserted `_draft_for` between `_candidate_for_project` and `_quote_gap_inputs`, splitting the read half's helpers; `candidate.candidate.project_id` also appeared on every publish log line (Law of Demeter).
- **Fix:** Class now reads read-half → publish-half (`publish_findings`, `_draft_for`, `_persist_publishable`, `_persist`); `ProfitabilityCandidate.project_id` exposes the signal's id. The `candidate.candidate.fingerprint` path is kept verbatim at the keep-set site, where the plan's contract note points at it deliberately.
- **Files modified:** `backend/app/features/finance/profitability_service.py`
- **Verification:** Full phase-36 suite plus `tests/unit` green (257 passed); ruff clean.
- **Committed in:** `b9613e1` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (2 missing critical, 1 structural/readability)
**Impact on plan:** Both critical fixes close silent-publish paths the plan's own contracts imply (a finding must have text; the model must be told the bounds it is judged by). No scope creep — no new endpoints, tables or dependencies.

## Issues Encountered

- **Verifying the cap tests were not vacuous.** Both cap assertions pass trivially against several wrong implementations, so the ordering was mutation-tested: incrementing a per-candidate counter and capping on it made `test_findings_cap_counted_after_validation` publish 7 findings and `test_per_company_findings_cap` log 0 cap drops. The correct implementation was restored from a scratch copy (not `git checkout`, since Task 2's work was uncommitted at that point) and the suite returned 28/28.
- **`ruff` autoformatted both files on first write** (line wrapping only); no logic changed.

## User Setup Required

None — no external service configuration required. Claude is reached through the already-provisioned `ANTHROPIC_API_KEY`; every test in this plan patches the client.

## Next Phase Readiness

Ready for **36-09** (alerting + resolution). It consumes, verbatim:

- `PublishResult.published: list[PublishedFinding]` with exactly `finding_id`, `project_id`, `fingerprint`, `severity_band`, `alert_summary`, `corrective_action`.
- `PublishResult.qualifying_fingerprints: list[str]` as the `resolve_absent_fingerprints(keep=...)` argument — every still-qualifying candidate, so a Claude failure never resolves a live finding.
- `ProfitabilityRepository.claim_alert(finding_id)` (shipped 36-01) is still the exactly-once gate; `publish_findings` deliberately leaves `alerted_at` NULL and creates no `DashboardAlert`.

No blockers. `publish_findings` does not commit — the scheduler entry point in a later plan owns the commit, matching `_run_for_all_companies` elsewhere in the codebase.

## Self-Check: PASSED

- Both modified files present on disk.
- All four task commits present in history (`f8d7d22`, `fdb82f0`, `83d55a9`, `b9613e1`).
- `pytest tests/test_phase_36_e2e.py tests/unit -q` → 257 passed; `ruff check .` and `ruff format --check .` clean.
- Every Task 1 and Task 2 acceptance-criteria grep verified, including the negative ones (`fallback=`, `call_claude_json(`, `[:280]`/`[:600]`/`truncate`, `test_alert_summary_length_contract`).

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*
</content>
</invoke>
