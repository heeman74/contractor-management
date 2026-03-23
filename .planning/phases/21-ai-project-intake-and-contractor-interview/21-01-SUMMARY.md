---
phase: 21-ai-project-intake-and-contractor-interview
plan: 01
subsystem: backend-ai
tags: [ai, claude, fastapi, sqlalchemy, streaming, sse, tool-use]
dependency_graph:
  requires: [phase-20-dependency-engine]
  provides: [ai-conversation-models, ai-service, claude-streaming, tool-definitions, system-prompts, migration-0017]
  affects: [phase-21-02-ai-endpoints, phase-21-03-intake-web, phase-21-04-interview-mobile]
tech_stack:
  added: [anthropic>=0.86.0]
  patterns: [TenantScopedService, TenantScopedModel, BaseRepository, async-generator-sse, exponential-backoff]
key_files:
  created:
    - backend/app/features/ai/__init__.py
    - backend/app/features/ai/models.py
    - backend/app/features/ai/schemas.py
    - backend/app/features/ai/repository.py
    - backend/app/features/ai/service.py
    - backend/app/features/ai/prompts/__init__.py
    - backend/app/features/ai/prompts/tools.py
    - backend/app/features/ai/prompts/intake_system.py
    - backend/app/features/ai/prompts/interview_system.py
    - backend/migrations/versions/0017_ai_conversations.py
  modified:
    - backend/requirements.txt
decisions:
  - "anthropic SDK installed via uv pip into venv (pyproject.toml has no [project] section — requirements.txt is canonical)"
  - "stream_turn and _call_with_retry are async generators (yield) not coroutines (return) — callers iterate with async for"
  - "_stream_once uses Anthropic streaming context manager and emits tool_call events after stream completion via get_final_message()"
  - "retry only on APITimeoutError and RateLimitError — non-transient APIError raises immediately"
  - "build_system_prompt_with_context method exposes explicit context injection for endpoints that load project/scope data"
metrics:
  duration: 5m
  completed_date: "2026-03-23"
  tasks_completed: 2
  files_created: 10
  files_modified: 1
---

# Phase 21 Plan 01: AI Backend Foundation Summary

**One-liner:** SQLAlchemy AI conversation models with Alembic migration 0017, Pydantic schemas, repositories, Claude SDK streaming service with retry and tool validation, and construction domain system prompts.

## What Was Built

### Task 1 — AI Models, Schemas, Repository, Migration

Three SQLAlchemy models inheriting `TenantScopedModel`, all with `lazy="raise"` relationships:

- **AIConversation** — top-level chat session with `conv_type` (intake/interview) and `status` (active/complete/abandoned), nullable FKs to projects and trade_scopes with ON DELETE SET NULL
- **AIMessage** — individual message with `role` (user/assistant), `content_json` JSONB storing the full Claude API content array verbatim, and `sequence_num` with UNIQUE constraint
- **AITokenUsage** — immutable token analytics records (no cascade on conversation FK)

Pydantic schemas: `ConversationCreate`, `ChatTurnRequest`, `ConversationResponse`, `AIMessageResponse` — all following existing TenantResponseSchema pattern.

Repositories:
- `AIConversationRepository.get_active_for_project()` — lookup by project_id + conv_type
- `AIConversationRepository.get_active_for_scope()` — lookup by scope_id for interview convs
- `AIMessageRepository.list_by_conversation()` — ordered by sequence_num ASC
- `AIMessageRepository.get_next_sequence()` — SELECT MAX(sequence_num) + 1

Migration 0017 creates all three tables with RLS policies (using `current_setting('app.current_company_id', TRUE)::UUID`), `set_updated_at` triggers on conversations and messages, and three indexes for FK lookups.

### Task 2 — AIService + Prompts + Tools

**Tool definitions** (`prompts/tools.py`):
- `INTAKE_TOOLS`: `create_trade_scope` (trade_name, trade_color, sort_order) + `ask_clarifying_question`
- `INTERVIEW_TOOLS`: `create_task` (title, description, priority, estimated_hours, sort_order, materials_needed)

**System prompts**:
- `INTAKE_SYSTEM_PROMPT`: Construction domain knowledge including 17 residential trades with typical sequencing, 7 commercial trades, sequencing heuristics (demolition → structural → rough MEP → insulation → drywall → finishes). Runtime placeholders: `{trade_catalog}`, `{project_context}`.
- `INTERVIEW_SYSTEM_PROMPT`: Trade-specific question templates for 10+ trades (electrical, plumbing, HVAC, framing, drywall, painting, flooring, roofing, tile, concrete). Runtime placeholders: `{project_description}`, `{trade_scope}`, `{all_scopes}`.

**AIService** extends `TenantScopedService[AIConversation]`:
- `get_or_create_conversation()` — looks up active conv or creates new
- `load_conversation_context()` — fetches conversation + message history + formats system prompt
- `build_system_prompt_with_context()` — explicit context injection for endpoints with project/scope data
- `persist_user_message()`, `persist_assistant_message()`, `persist_tool_result()` — message persistence
- `record_usage()` — token analytics
- `stream_turn()` — async generator yielding SSE strings (`event: token`, `event: tool_call`, `event: done`, `event: error`)
- `_call_with_retry()` — 3 attempts with 1s/2s/4s exponential backoff on transient errors only
- `validate_tool_input()` — validates and cleans tool inputs against TradeScopeCreate/TaskCreate field constraints
- `mark_complete()`, `mark_abandoned()` — conversation lifecycle

## Deviations from Plan

None — plan executed exactly as written.

**Minor adaptation:** `_stream_once` return type annotation uses `AsyncGenerator[str, None]` but the method contains `yield` making it an async generator function — this is the correct Python pattern for streaming.

## Self-Check

PASSED — all files exist and verified below.

```
backend/app/features/ai/models.py: FOUND
backend/app/features/ai/schemas.py: FOUND
backend/app/features/ai/repository.py: FOUND
backend/app/features/ai/service.py: FOUND
backend/app/features/ai/prompts/tools.py: FOUND
backend/app/features/ai/prompts/intake_system.py: FOUND
backend/app/features/ai/prompts/interview_system.py: FOUND
backend/migrations/versions/0017_ai_conversations.py: FOUND
Commits: 646b1fe (Task 1), 3122ca9 (Task 2)
ruff check: PASSED
Full import: PASSED
```
