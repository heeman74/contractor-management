---
phase: 21-ai-project-intake-and-contractor-interview
verified: 2026-03-23T12:00:00Z
status: passed
score: 25/25 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 24/25
  gaps_closed:
    - "GC can upload a site photo or blueprint that AI uses as context (Plan 06: D-07) — AIImageUpload model, POST /ai/intake/image endpoint, build_image_content_block(), migration 0018_ai_image_uploads.py, ImageUploadResponse schema, and 4 image upload tests are now all present and wired"
  gaps_remaining: []
  regressions: []

human_verification:
  - test: "Verify AI token streaming end-to-end (web)"
    expected: "Typing 'Build a 3-bedroom house' in web intake sends SSE tokens that render word-by-word in chat bubble"
    why_human: "Requires ANTHROPIC_API_KEY and live Claude API call — cannot verify programmatically without real credentials"
  - test: "Verify mobile AI chat on emulator/device"
    expected: "Tokens stream in Flutter chat screen, DraggableScrollableSheet slides up when trade scopes arrive"
    why_human: "Visual animation and real-device SSE streaming cannot be verified by static code inspection"
  - test: "Verify Playwright E2E tests pass in CI"
    expected: "npx playwright test tests/ai-intake.spec.ts tests/ai-interview.spec.ts exits 0"
    why_human: "Playwright tests depend on a running Next.js dev server and route mocking — cannot verify without runtime environment"
---

# Phase 21: AI Project Intake and Contractor Interview — Verification Report

**Phase Goal:** AI-driven project intake (GC describes project → AI generates trade scopes) and contractor interview (AI interviews contractor → generates task plan) with streaming chat UI on web and mobile.

**Requirements:** AI-01, AI-02, AI-03

**Verified:** 2026-03-23T12:00:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure (Plan 21-07 rebuilt image upload feature)

---

## Re-verification Summary

Previous verification (2026-03-24T01:30:00Z) found 24/25 truths verified with one gap: Plan 06 image upload artifacts were entirely absent despite the SUMMARY claiming completion. Plan 21-07 was executed to close that gap. This re-verification confirms all six missing artifacts are now present and correctly wired.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | A new conversation can be created and persisted for intake or interview | VERIFIED | `AIConversation`, `AIMessage`, `AITokenUsage` models with `TenantScopedModel` inheritance, lazy="raise" relationships, RLS migration |
| 2 | Claude API can be called with tool definitions and stream tokens back as SSE events | VERIFIED | `AIService.stream_turn()` async generator, `_stream_once()` uses `_anthropic_client.messages.stream()`, yields SSE event strings |
| 3 | Tool inputs are validated against TradeScopeCreate/TaskCreate field constraints | VERIFIED | `validate_tool_input()` enforces non-empty trade_name, sort_order int, title max 300 chars, valid priority enum, materials_needed structure |
| 4 | System prompts provide construction domain knowledge with runtime context injection | VERIFIED | `INTAKE_SYSTEM_PROMPT` with `{trade_catalog}` and `{project_context}` placeholders; `INTERVIEW_SYSTEM_PROMPT` with `{project_description}`, `{trade_scope}`, `{all_scopes}` |
| 5 | Token usage is tracked per conversation | VERIFIED | `AITokenUsage` model + `record_usage()` method in service |
| 6 | POST /ai/intake/start creates or resumes a conversation | VERIFIED | Route exists, `get_or_create_conversation()` called, `ConversationResponse` returned with 201 |
| 7 | POST /ai/intake/message streams SSE tokens | VERIFIED | `StreamingResponse(media_type="text/event-stream")` wraps `stream_turn()` async generator |
| 8 | intake/complete creates trade scopes in a single transaction with dependency edges | VERIFIED | Sorted scopes created, placeholder tasks created, `DependencyService.create_dependency()` called for consecutive pairs (D-23) |
| 9 | POST /ai/interview/start creates a conversation for a trade scope | VERIFIED | Route verifies scope exists, `get_or_create_conversation(conv_type='interview')` |
| 10 | POST /ai/interview/message streams SSE tokens for contractor interview | VERIFIED | Same pattern as intake/message, uses `INTERVIEW_TOOLS` |
| 11 | interview/complete soft-deletes existing tasks and creates new tasks | VERIFIED | Soft-deletes via `deleted_at = now()`, then `TaskService.create()` per task, conversation marked complete |
| 12 | All endpoints require authentication | VERIFIED | `Depends(get_current_user)` on every endpoint |
| 13 | GC can type a project description in web chat and see tokens stream word-by-word | VERIFIED | `useIntakeChat.ts` reads `pipeThrough(new TextDecoderStream()).getReader()`, appends `delta` to message on each token SSE event |
| 14 | SSE proxy correctly pipes ReadableStream without buffering | VERIFIED | `route.ts` returns `new Response(upstreamRes.body, ...)` — never calls `.text()` |
| 15 | GC sees trade scope preview card after AI generates breakdown | VERIFIED | `TradeScopePreviewCard` rendered in intake page when `tradeScopes.length > 0`; hook populates tradeScopes on `create_trade_scope` tool_call events |
| 16 | Contractor sees editable task preview list after AI interview | VERIFIED | `TaskPreviewList` rendered in interview page; `Accept Plan` and `Restart Interview` buttons present |
| 17 | Offline state disables web chat input and shows banner | VERIFIED | `ChatInput.tsx` checks `navigator.onLine`; shows destructive Alert when offline |
| 18 | SSE parse logic handles token/tool_call/done/error events | VERIFIED | `parseSSELine()` exported from useIntakeChat.ts; 9 unit tests in `__tests__/useIntakeChat.test.ts` |
| 19 | GC can open AI intake chat from mobile Projects tab (token streaming) | VERIFIED | `IntakeChatScreen` with `intakeChatProvider`, route `/ai-intake` registered in app_router.dart, FAB in project_list_screen.dart |
| 20 | Contractor can open AI interview from trade scope detail | VERIFIED | Route `/ai-interview/:scopeId` registered; `trade_scope_detail_screen.dart` pushes to `RouteNames.aiInterviewPath(scopeId)` |
| 21 | Drift schema v9 caches conversation transcripts locally | VERIFIED | `app_database.dart` has `schemaVersion => 9`, `AiConversations` and `AiMessages` tables, migration block `if (from < 9)` |
| 22 | Mobile SSE client correctly parses all event types | VERIFIED | `AiSseClient` with `parseSseEvent()` top-level function, 11 unit tests in `ai_sse_client_test.dart` |
| 23 | Flutter E2E tests cover intake and interview flows (10+ and 6+ tests each) | VERIFIED | `phase_21_ai_intake_e2e_test.dart` (10 testWidgets), `phase_21_ai_interview_e2e_test.dart` (10 testWidgets); no pumpAndSettle; MockAiSseClient used |
| 24 | Playwright E2E tests cover web intake and interview flows (8+ and 6+ tests each) | VERIFIED | `web/tests/ai-intake.spec.ts` (8 tests), `web/tests/ai-interview.spec.ts` (6 tests); text/event-stream mock SSE used |
| 25 | GC can upload a site photo that AI uses as context (Plan 06: D-07) | VERIFIED | `AIImageUpload` model (models.py:174), `POST /ai/intake/image` endpoint (router.py:133), `build_image_content_block()` (service.py:462), migration 0018_ai_image_uploads.py, `ImageUploadResponse` schema (schemas.py:46), 4 image upload tests in `TestImageUpload` class |

**Score: 25/25 truths verified**

---

## Required Artifacts

### Plan 01 — Backend AI Module Foundation

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/ai/models.py` | AIConversation, AIMessage, AITokenUsage with TenantScopedModel | VERIFIED | All three original models present plus new AIImageUpload (lines 174-206) |
| `backend/app/features/ai/service.py` | AIService with stream_turn, tool dispatch, conversation management | VERIFIED | All required methods present including new `build_image_content_block()` (lines 462-489) |
| `backend/app/features/ai/prompts/tools.py` | INTAKE_TOOLS, INTERVIEW_TOOLS | VERIFIED | `create_trade_scope`, `ask_clarifying_question`, `create_task` tool definitions present |
| `backend/migrations/versions/0017_ai_conversations.py` | Alembic migration with RLS | VERIFIED | `down_revision = "0016"`, RLS for all 3 original tables |

### Plan 02 — Backend Router and Tests

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/ai/router.py` | 7+ SSE streaming endpoints | VERIFIED | All 7 original routes present plus new `POST /ai/intake/image` (lines 133-191); `UploadFile`, `PIL`, `aiofiles` imports confirmed |
| `backend/app/main.py` | AI router registered | VERIFIED | `from app.features.ai.router import router as ai_router` + `app.include_router(ai_router, prefix="/api/v1")` |
| `backend/tests/test_ai_service.py` | Unit tests for tool validation | VERIFIED | `TestToolValidation` class with validation tests |
| `backend/tests/test_phase_21_e2e.py` | Integration tests including image upload | VERIFIED | Original tests present plus `TestImageUpload` class (lines 619-743) with 4 image tests |

### Plan 03 — Web Chat UI

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `web/src/app/api/ai-chat/route.ts` | SSE proxy, ReadableStream pipe | VERIFIED | `dynamic = "force-dynamic"`, pipes `upstreamRes.body` directly |
| `web/src/app/projects/new/ai-intake/page.tsx` | GC intake page | VERIFIED | Imports `useIntakeChat`, `TradeScopePreviewCard`, `ChatInput` |
| `web/src/app/projects/[id]/interview/[scopeId]/page.tsx` | Interview page | VERIFIED | Imports `useInterviewChat`, `TaskPreviewList`; "Accept Plan" wired |
| `web/src/features/ai/hooks/useIntakeChat.ts` | SSE streaming hook | VERIFIED | `parseSSELine` exported, `TextDecoderStream`, `create_trade_scope` tool handling |
| `web/src/features/ai/hooks/__tests__/useIntakeChat.test.ts` | 5+ SSE parse tests | VERIFIED | 9 test calls |
| `web/src/features/ai/components/ChatBubble.tsx` | Branded bubbles | VERIFIED | "ContractorHub AI", `aria-label` attributes |
| `web/src/features/ai/components/TypingIndicator.tsx` | Animated dots | VERIFIED | `bounce` CSS animation, aria-label |
| `web/src/features/ai/components/ChatInput.tsx` | Offline detection | VERIFIED | `navigator.onLine` check |
| `web/src/features/ai/components/TradeScopePreviewCard.tsx` | Editable scope preview | VERIFIED | "Create Project" button |
| `web/src/features/ai/components/TaskPreviewList.tsx` | Editable task list | VERIFIED | "Accept Plan", "Restart Interview", restart confirmation dialog |

### Plan 04 — Mobile Chat UI

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/lib/core/database/app_database.dart` | schemaVersion => 9 | VERIFIED | `schemaVersion => 9`, migration block `if (from < 9)` |
| `mobile/lib/core/database/tables/ai_conversations.dart` | AiConversations Drift table | VERIFIED | `class AiConversations extends Table` |
| `mobile/lib/features/ai/data/ai_sse_client.dart` | SSE client bypassing Dio | VERIFIED | `class AiSseClient`, `text/event-stream`, `parseSseEvent` top-level function |
| `mobile/lib/core/di/service_locator.dart` | GetIt registrations | VERIFIED | `AiSseClient` and `AiConversationDao` registered |
| `mobile/lib/features/ai/presentation/providers/intake_chat_provider.dart` | IntakeChatState | VERIFIED | `class IntakeChatState` present |
| `mobile/lib/features/ai/presentation/screens/intake_chat_screen.dart` | GC intake screen | VERIFIED | "AI Intake", `ChatInputBar`, `DraggableScrollableSheet` |
| `mobile/lib/features/ai/presentation/screens/interview_chat_screen.dart` | Interview screen | VERIFIED | "AI Interview", `TaskPreviewList` |
| `mobile/lib/features/ai/presentation/widgets/chat_bubble.dart` | Branded bubbles | VERIFIED | "ContractorHub AI", `Semantics` |
| `mobile/lib/features/ai/presentation/widgets/chat_input_bar.dart` | Offline banner | VERIFIED | "AI features require an internet connection." |
| `mobile/lib/features/ai/presentation/widgets/trade_scope_preview_card.dart` | Scope preview | VERIFIED | "Create Project" |
| `mobile/lib/features/ai/presentation/widgets/task_preview_list.dart` | Task list | VERIFIED | "Accept Plan", "Restart Interview", AlertDialog |
| `mobile/test/unit/ai_sse_client_test.dart` | SSE parse unit tests | VERIFIED | 11 test() calls |

### Plan 05 — E2E Tests

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mobile/test/e2e/phase_21_ai_intake_e2e_test.dart` | 8+ testWidgets | VERIFIED | 10 testWidgets, MockAiSseClient, no pumpAndSettle |
| `mobile/test/e2e/phase_21_ai_interview_e2e_test.dart` | 6+ testWidgets | VERIFIED | 10 testWidgets |
| `web/tests/ai-intake.spec.ts` | 8+ tests, SSE mock | VERIFIED | 8 test() calls |
| `web/tests/ai-interview.spec.ts` | 6+ tests | VERIFIED | 6 test() calls |

### Plan 06 — Image Upload (RE-VERIFIED AFTER GAP CLOSURE)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/app/features/ai/models.py` (AIImageUpload) | TenantScopedModel for images | VERIFIED | Lines 174-206 — `AIImageUpload(TenantScopedModel)`, `__tablename__ = "ai_image_uploads"`, `lazy="raise"` on conversation relationship, all required columns present |
| `backend/app/features/ai/router.py` (POST /ai/intake/image) | UploadFile endpoint | VERIFIED | Lines 133-191 — `UploadFile` in params, `PIL.Image.thumbnail((1280, 1280))`, `aiofiles` write, `db.add(image_record)` + `db.flush()`, returns `ImageUploadResponse.model_validate(image_record)` |
| `backend/app/features/ai/service.py` (build_image_content_block) | base64 vision method | VERIFIED | Lines 462-489 — `import base64` and `aiofiles` at top of file; method queries `AIImageUpload` by id, reads file with `aiofiles.open`, base64-encodes, returns Claude vision content block dict |
| `backend/migrations/versions/0018_ai_image_uploads.py` | Table + RLS + trigger | VERIFIED | `down_revision = "0017"`, creates `ai_image_uploads` table with all columns, RLS `tenant_isolation` policy, `FORCE ROW LEVEL SECURITY`, `set_updated_at` trigger, index on `conversation_id` |
| `backend/app/features/ai/schemas.py` (ImageUploadResponse) | Upload response schema | VERIFIED | Lines 46-52 — `class ImageUploadResponse(BaseResponseSchema)` with `conversation_id`, `original_filename`, `media_type`, `file_size_bytes` |
| `backend/tests/test_phase_21_e2e.py` (image tests) | 4 image upload tests | VERIFIED | `TestImageUpload` class (lines 619-743) — `test_image_upload_returns_ref_id`, `test_image_upload_rejects_non_image`, `test_image_upload_compresses_large_image`, `test_chat_turn_with_image_includes_vision_block` — all 4 required tests present |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ai/router.py` | `ai/service.py` | `AIService` instantiation + `stream_turn()` call | WIRED | Every route handler creates `AIService(db)` and calls the appropriate method |
| `main.py` | `ai/router.py` | `app.include_router(ai_router, prefix="/api/v1")` | WIRED | Confirmed in main.py |
| `ai/router.py` | `projects/service.py` | `DependencyService.create_dependency()` for scope pairs | WIRED | `dep_svc.create_dependency(succ_task_id, TaskDependencyCreate(...))` in `intake_complete` |
| `web/api/ai-chat/route.ts` | FastAPI backend | `upstreamRes.body` ReadableStream pipe | WIRED | `return new Response(upstreamRes.body, ...)` — no buffering |
| `useIntakeChat.ts` | `api/ai-chat/route.ts` | `fetch POST` + `pipeThrough(new TextDecoderStream()).getReader()` | WIRED | Both `TextDecoderStream` and `parseSSELine` confirmed |
| `intake_chat_screen.dart` | `intake_chat_provider.dart` | Riverpod `ref.watch(intakeChatProvider)` + `ref.read(intakeChatProvider.notifier)` | WIRED | Screen imports provider and calls all actions |
| `service_locator.dart` | `ai_sse_client.dart` | `getIt.registerLazySingleton<AiSseClient>()` | WIRED | Registered in service_locator.dart |
| Mobile router | `IntakeChatScreen` / `InterviewChatScreen` | GoRouter route definitions | WIRED | `RouteNames.aiIntake` and `RouteNames.aiInterview` registered |
| `ai/router.py` (image endpoint) | `ai/service.py` (build_image_content_block) | `req.image_ref_id` → `service.build_image_content_block()` | WIRED | `intake_message` (line 227) and `interview_message` (line 425) both call `await service.build_image_content_block(req.image_ref_id)` when `req.image_ref_id` is set |
| `ai/schemas.py` (ChatTurnRequest) | `image_ref_id` field | `image_ref_id: uuid.UUID | None = None` in ChatTurnRequest | WIRED | schemas.py line 24 — field present, optional |

---

## Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|---------------|-------------|--------|---------|
| AI-01 | 21-01, 21-02, 21-03, 21-04, 21-05, 21-06 | GC can describe a project in natural language and AI breaks it into trade scopes with suggested sequencing | SATISFIED | `intake_start` → `intake_message` (SSE) → `intake_complete` (creates scopes + dependency edges). Web and mobile UIs present. Image upload extends AI-01 with optional vision context. E2E tests cover full flow including image attachment. |
| AI-02 | 21-01, 21-02, 21-03, 21-04, 21-05 | AI asks follow-up questions to clarify project scope before generating trade breakdown | SATISFIED | `ask_clarifying_question` tool in `INTAKE_TOOLS`; hook handles `tool_call` with `ask_clarifying_question` by appending question text to AI message. Backend and E2E tests cover clarifying question flow. |
| AI-03 | 21-01, 21-02, 21-03, 21-04, 21-05 | AI interviews each trade contractor with trade-specific questions to generate detailed task plans | SATISFIED | `interview_start` → `interview_message` (SSE with INTERVIEW_TOOLS) → `interview_complete` (creates tasks). `INTERVIEW_SYSTEM_PROMPT` includes trade-specific question templates. E2E tests cover interview produces tasks. |

All three required requirements (AI-01, AI-02, AI-03) are SATISFIED. No orphaned requirements for Phase 21.

---

## Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `backend/app/features/ai/router.py` (L287-300) | Inline SQL query (`select(TradeScope)`) in router instead of service/repository | WARNING | Minor OOP architecture violation (CLAUDE.md requires router functions to delegate to service layer) — not a correctness issue |
| `backend/app/features/ai/router.py` (L396-409) | Inline soft-delete via direct ORM manipulation instead of service | WARNING | Bypasses service layer for re-interview cleanup — same concern as above |

No blockers found. The two warnings carry over from the initial verification and do not block goal achievement.

---

## Human Verification Required

### 1. Live Streaming End-to-End (Web)

**Test:** Start backend (`uv run uvicorn app.main:app --reload`), start web (`npm run dev`), navigate to `/projects/new/ai-intake`, type "I want to renovate a 3-bedroom house — new kitchen, bathrooms, and flooring", press Send.
**Expected:** Tokens stream word-by-word in an AI bubble; typing indicator shows before first token; after full response, if AI generates scopes the TradeScopePreviewCard appears.
**Why human:** Requires `ANTHROPIC_API_KEY` in `.env`; real-time streaming token rendering is visual.

### 2. Live Streaming End-to-End (Mobile)

**Test:** Run Flutter app on emulator, tap "New AI Project" FAB on Projects tab, type a project description, tap Send.
**Expected:** DraggableScrollableSheet slides up when trade scopes arrive; typing indicator (3 bouncing dots) shows while waiting; chat bubbles: user right-aligned (primary color), AI left-aligned (surfaceVariant) with bot avatar.
**Why human:** Visual animation and mobile SSE streaming cannot be verified by static analysis.

### 3. Playwright Test Suite Pass

**Test:** `cd web && npx playwright test tests/ai-intake.spec.ts tests/ai-interview.spec.ts --reporter=list`
**Expected:** All 14 tests pass (8 intake + 6 interview).
**Why human:** Playwright tests require a running Next.js dev server; cannot verify without runtime execution.

---

## Gaps Summary

No gaps. All 25 must-haves are verified. The single gap from the initial verification (Plan 06 image upload) has been fully closed by Plan 21-07:

- `AIImageUpload` SQLAlchemy model — present and well-formed with `TenantScopedModel` inheritance
- `POST /ai/intake/image` endpoint — present with Pillow compression, content-type validation, 10MB size guard, `aiofiles` async write, DB record creation
- `build_image_content_block()` — present with `aiofiles` file read and base64 encoding for Claude vision API
- Migration `0018_ai_image_uploads.py` — present with RLS, trigger, correct FK chain to `ai_conversations`
- `ImageUploadResponse` schema — present with all required fields
- 4 image upload integration tests — all present covering happy path, rejection, compression verification, and vision block inclusion in the Claude API call

The phase goal is fully achieved.

---

_Verified: 2026-03-23T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
