---
status: resolved
trigger: "GET /api/v1/sync?cursor= returns 422 validation error for empty cursor string"
created: 2026-03-05T00:00:00Z
updated: 2026-03-06T00:00:00Z
---

## Current Focus

hypothesis: FastAPI/Pydantic parses `cursor=` (empty string) as a non-None string and tries to coerce it to datetime, which fails validation
test: Confirmed by reading router.py — the type annotation is `datetime | None` with `default=None`
expecting: Empty string "" is not None and not a valid datetime, so Pydantic raises 422
next_action: Return diagnosis

## Symptoms

expected: GET /api/v1/sync?cursor= should accept empty cursor and default to epoch for full first-launch download
actual: Returns 422 validation error "Input should be a valid datetime or date, input is too short"
errors: 422 Unprocessable Entity — "Input should be a valid datetime or date, input is too short"
reproduction: GET /api/v1/sync?cursor= (with empty string as cursor value)
started: Since endpoint was created — the None default only works when cursor param is fully omitted

## Eliminated

(none needed — root cause identified on first pass)

## Evidence

- timestamp: 2026-03-05T00:00:00Z
  checked: backend/app/features/sync/router.py lines 30-38
  found: cursor parameter declared as `cursor: datetime | None = Query(default=None)`. The default=None only applies when the query parameter is completely absent from the URL. When present but empty (`?cursor=`), FastAPI receives the empty string "" and attempts to parse it as a datetime via Pydantic, which fails.
  implication: This is the root cause. The type union `datetime | None` does not include `str`, so empty string "" cannot pass validation. FastAPI/Pydantic distinguishes between "parameter absent" (gets default None) and "parameter present but empty" (gets "" which must match the type).

- timestamp: 2026-03-05T00:00:00Z
  checked: FastAPI query parameter parsing behavior
  found: FastAPI handles three distinct cases for optional query params: (1) param absent -> default value used, (2) param present with valid value -> parsed value used, (3) param present with empty string -> Pydantic tries to coerce "" to the declared type. For `datetime | None`, "" is not None and not a valid datetime string, so Pydantic raises a validation error.
  implication: The fix must handle the empty-string case explicitly.

- timestamp: 2026-03-05T00:00:00Z
  checked: backend/app/features/sync/router.py line 47
  found: `since = cursor if cursor is not None else _EPOCH_START` — this fallback logic is correct but never reached when cursor="" because Pydantic rejects the request before the handler runs.
  implication: The application logic is fine. The problem is purely at the parameter validation layer.

## Resolution

root_cause: FastAPI/Pydantic type coercion rejects empty string "" for `datetime | None` query parameter. When Flutter SyncEngine sends `GET /api/v1/sync?cursor=` (empty cursor for first launch), FastAPI receives "" as the cursor value. Since "" is not None (param IS present) and not a valid datetime string, Pydantic raises a 422 validation error before the handler function ever executes. The `default=None` only applies when the parameter is completely absent from the URL (i.e., `GET /api/v1/sync` with no cursor param at all).

fix: (not applied — diagnosis only)
verification: (not applied — diagnosis only)
files_changed: []
