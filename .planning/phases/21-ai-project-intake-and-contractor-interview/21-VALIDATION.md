---
phase: 21
slug: ai-project-intake-and-contractor-interview
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-23
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.3.4 (backend) + flutter_test (mobile) |
| **Config file** | `backend/pyproject.toml` (pytest section) |
| **Quick run command** | `cd backend && uv run python -m pytest tests/test_ai_service.py -x` |
| **Full suite command** | `cd backend && uv run python -m pytest && cd ../mobile && flutter test` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd backend && uv run python -m pytest tests/test_ai_service.py -x`
- **After every plan wave:** Run `cd backend && uv run python -m pytest && cd ../mobile && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | AI-01 | integration | `pytest tests/test_phase_21_e2e.py::test_intake_produces_trade_scopes -x` | ❌ W0 | ⬜ pending |
| 21-01-02 | 01 | 1 | AI-01 | unit | `pytest tests/test_ai_service.py::test_tool_input_validates_trade_scope_create -x` | ❌ W0 | ⬜ pending |
| 21-01-03 | 01 | 1 | AI-02 | integration | `pytest tests/test_phase_21_e2e.py::test_intake_asks_clarifying_questions -x` | ❌ W0 | ⬜ pending |
| 21-01-04 | 01 | 1 | AI-03 | integration | `pytest tests/test_phase_21_e2e.py::test_interview_produces_tasks -x` | ❌ W0 | ⬜ pending |
| 21-01-05 | 01 | 1 | AI-03 | unit | `pytest tests/test_ai_service.py::test_tool_input_validates_task_create -x` | ❌ W0 | ⬜ pending |
| 21-01-06 | 01 | 1 | D-22 | unit | `pytest tests/test_ai_service.py::test_malformed_tool_input_rejected -x` | ❌ W0 | ⬜ pending |
| 21-01-07 | 01 | 1 | D-05 | unit | `pytest tests/test_ai_repository.py::test_message_persistence -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `backend/tests/test_ai_service.py` — stubs for AI-01, AI-03, D-22 tool validation
- [ ] `backend/tests/test_ai_repository.py` — conversation/message persistence tests
- [ ] `backend/tests/test_phase_21_e2e.py` — full intake + interview E2E tests
- [ ] `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart` — Flutter chat UI E2E tests
- [ ] `anthropic` package added to requirements.txt via `uv add anthropic`
- [ ] `backend/app/features/ai/` directory structure created

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSE streaming feels responsive (tokens appear word-by-word) | D-03 | Perceived latency is subjective | Open AI chat, type description, observe token-by-token appearance |
| Chat bubble styling matches design (rounded, branded colors) | D-25 | Visual/aesthetic check | Compare chat UI to design spec |
| Typing indicator animation is smooth | D-25 | Animation quality is visual | Observe three-dot animation during AI response |
| Image thumbnails display correctly in bubbles | D-27 | Visual layout check | Upload image, verify thumbnail renders in bubble |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
