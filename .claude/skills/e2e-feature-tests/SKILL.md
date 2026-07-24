---
name: e2e-feature-tests
description: Create and run end-to-end tests for a new or changed feature in ContractorHub, across whichever layers it touches (FastAPI backend, Next.js web, Flutter mobile). Use this whenever a feature is added or modified — new endpoint, new page/flow, new screen — to write the E2E test alongside the code and drive it to green before considering the work done.
---

# E2E Feature Tests (ContractorHub)

Every new or changed feature ships with E2E tests **in the same change** and is not
done until those tests pass (see `CLAUDE.md` → Testing Rules). This skill is the
concrete workflow for producing and running them.

## Workflow

1. **Identify the layers the feature touches.** A feature usually spans some subset of:
   - **Backend** — a new/changed endpoint, service, or model → `backend/`
   - **Web** — a new page, dialog, or flow → `web/`
   - **Mobile** — a new screen or provider → `mobile/`
   Write an E2E test for **each layer touched**. A full-stack feature (e.g. "assign a
   PM to a project") gets a backend pytest E2E **and** a web Playwright E2E.

2. **Write the test next to the feature**, following the per-layer conventions below.
   Cover: happy path, validation/error path, an edge case (empty/missing data), and —
   where relevant — cross-role visibility and tenant isolation.

3. **Run it, read the output, fix, re-run until green.** Never report a feature done
   on an unverified or red test. If a test is genuinely blocked (e.g. needs a real
   service), say so explicitly rather than skipping silently.

4. **Run the affected layer's full suite once** at the end so a shared change
   (a type, a helper, a global setup) didn't break a sibling test.

---

## Backend — pytest E2E (real test DB)

- **Location / name:** `backend/tests/test_<feature>_e2e.py` (phase work uses
  `test_phase_<N>_e2e.py`).
- **DB:** runs against `contractorhub_test`, which `conftest.py` **force-selects**
  (via `DATABASE_URL`/`TEST_DATABASE_URL`) and migrates automatically — it can never
  touch the dev DB. `clean_tables` truncates between tests.
- **Auth:** use the `conftest.py` fixtures — `seed_two_tenants`, `tenant_a_client`,
  `tenant_b_client` (JWT Bearer pre-set). Exercise the full ASGI stack; don't inject
  sessions. Two tenants exist specifically so you can assert **RLS isolation**
  (tenant B must not see tenant A's data → expect 404/empty).
- **Run:**
  ```bash
  cd backend && source .venv/bin/activate
  python -m pytest tests/test_<feature>_e2e.py -q          # one file
  python -m pytest -q                                       # full suite (slow, ~25m)
  ```
- **Shape:**
  ```python
  async def test_<action>_happy_path(tenant_a_client, seed_two_tenants):
      resp = await tenant_a_client.post("/api/v1/<...>", json={...})
      assert resp.status_code == 201
      # assert the persisted effect via a follow-up GET

  async def test_<action>_rls_isolation(tenant_a_client, tenant_b_client, seed_two_tenants):
      # tenant B must not reach tenant A's resource
      resp = await tenant_b_client.get("/api/v1/<...>/{tenant_a_id}")
      assert resp.status_code == 404
  ```
- If you added a **migration**, it applies automatically on the next test run (conftest
  runs `alembic upgrade head`). Confirm the new column/table/constraint is exercised.

---

## Web — Playwright E2E (mock the proxy, no live backend)

- **Location / name:** `web/tests/<feature>.spec.ts`.
- **Convention:** these specs **mock `/api/proxy`** with `page.route` and set a mock
  `access_token` cookie — they do **not** need a running backend or DB. Assert both the
  **captured request** (path + payload) and the **resulting UI**. Cover happy path and
  the error path (server error → snackbar/inline message). This mirrors
  `web/tests/create-contractor.spec.ts` — read it as the template.
- **Run:**
  ```bash
  cd web
  npx playwright test tests/<feature>.spec.ts        # one spec (chromium is the project)
  npm run test-e2e                                    # all specs
  ```
- **Skeleton:**
  ```ts
  import { test, expect, type Page, type Route } from "@playwright/test";

  async function mockApi(page: Page) {
    await page.context().addCookies([
      { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
    ]);
    await page.route("**/api/proxy**", async (route: Route) => {
      const path = new URL(route.request().url()).searchParams.get("path") ?? "";
      const method = route.request().method();
      if (method === "GET" && path.includes("/me/permissions"))
        return route.fulfill({ json: { permissions: ["users.view", "users.create"] } });
      if (method === "GET" && path.includes("/<resource>"))
        return route.fulfill({ json: [/* seed rows */] });
      if (method === "POST" && path.includes("/<resource>"))
        return route.fulfill({ json: { id: "new-id" } });
      return route.fulfill({ status: 404, json: { detail: "unmatched" } });
    });
  }

  test("creates a <thing>", async ({ page }) => {
    await mockApi(page);
    await page.goto("/<route>");
    // ...drive the UI, then assert both request payload and UI update
  });
  ```
- **Permission-gated UI:** mock `GET /me/permissions` to return the keys the page needs
  (e.g. `users.view`, `users.create`) or the gated element won't render. **Important:**
  `isAuthenticated` is only set by the login flow (there is no cookie rehydration), so a
  hard `page.goto` to a deep route leaves permissions unloaded and gated controls hidden.
  For permission-gated flows, **log in through the UI first** — mock `**/api/auth/login`
  (the Next route, not `/api/proxy`) to return `{ roles: [...], display_name, ... }`, fill
  the login form, then navigate to the target page by **clicking a sidebar link** (SPA nav
  keeps the auth state; another `goto` would reset it). See
  `web/tests/project-assignments.spec.ts` for the pattern.
- **Radix widgets (Select, etc.):** jsdom shims live in `jest.setup.ts`; in Playwright
  they work natively (`getByRole("combobox")` → `getByRole("option", { name })`).

**Also add a jest component test** (`src/**/__tests__/*.test.tsx`) for pure logic /
validation / rendering — faster than Playwright. Wrap hooks that use React Query in a
`QueryClientProvider`; mock `@/lib/api-client`. Run: `npx jest <pattern>`.

**Before committing web code:** `npx eslint .` (must be 0 warnings), `npx tsc --noEmit`,
`npx jest`.

---

## Mobile — Flutter E2E

- **Location / name:** `mobile/test/e2e/<feature>_e2e_test.dart` (phase work:
  `phase_<N>_<feature>_e2e_test.dart`).
- **Convention:** mock Dio at `MockDioClient.instance` and assert captured request
  paths/payloads; use a **real Drift in-memory DB** (don't mock what a real DB can
  cover). Mock plugins (Geolocator, camera, file picker) at the plugin level. Exercise
  the full flow: UI interaction → provider → DAO/service → persistence → UI update.
- **Run:**
  ```bash
  cd mobile && flutter test test/e2e/<feature>_e2e_test.dart
  flutter test                                        # full suite
  ```
- **Before committing:** `dart analyze`.

---

## Manual smoke against the running app (optional, for verifying by eye)

The committed web specs mock the API. To sanity-check a change against the **real**
running stack (dev server on `:3000`, backend on `:8000`, dev DB `contractorhub`):
log in as `admin@ace.com` / `password123`, and navigate by **clicking sidebar links**
(client-side nav preserves auth/permission state) rather than `page.goto` (a hard reload
resets Redux auth and can transiently disable permission-gated UI). This is for
eyeballing only — the committed test is the mocked Playwright spec above.

---

## Definition of done

- [ ] An E2E test exists for **each layer the feature touches**, created in the same change.
- [ ] Happy path + error/validation path + one edge case covered (plus RLS isolation for backend, cross-role visibility where relevant).
- [ ] The new test(s) **pass**, and the affected layer's full suite still passes.
- [ ] Lint + typecheck clean for the touched layer (`ruff` / `eslint`+`tsc` / `dart analyze`).
