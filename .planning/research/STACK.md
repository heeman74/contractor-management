# Stack Research

**Domain:** Contractor management SaaS — Flutter mobile + Python backend + Next.js web admin dashboard
**Researched:** 2026-03-14 (v1.0/v2.0) | Updated 2026-03-19 (v3.0 AI additions)
**Confidence:** HIGH (web additions verified via WebSearch against npm/official docs; Flutter/backend sections carried from prior research at 2026-03-04)

---

## Recommended Stack

### Core Technologies — Existing (DO NOT CHANGE)

These are already built, tested, and validated in v1.0. Do not replace or re-research.

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Flutter | 3.32+ (SDK) | Android mobile app (contractors + clients) | Shipped v1.0 |
| FastAPI | 0.115+ | Python backend API (shared by mobile + web) | Shipped v1.0 |
| PostgreSQL | 13 | Primary database with RLS multi-tenancy | Shipped v1.0 |
| SQLAlchemy | 2.0 async | ORM + async DB access | Shipped v1.0 |
| JWT (python-jose) | 3.3+ | Access tokens (15 min) + refresh rotation (30 days) | Shipped v1.0 |

---

### Core Technologies — New (Web Admin Dashboard)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Next.js | 16.x | Web framework (App Router) | App Router + React Server Components enable server-side rendering for fast initial page loads. Version 16 is stable in 2026. Vercel's official framework for React, with built-in caching, route handlers (API proxying for auth), and middleware for JWT auth guards. Use over Create React App (abandoned) or Vite SPA (no SSR) because admin dashboards benefit from SSR for analytics pages. |
| React | 19.x | UI library | Required by Next.js 16. React 19 ships with improved Suspense batching, the `use()` hook for async data, and concurrent features that reduce perceived load time on complex admin views. |
| TypeScript | 5.x | Type safety | Required. Admin dashboards have complex data shapes (jobs, quotes, invoices). TypeScript catches mismatches between API response shapes and UI expectations at compile time, not runtime. |
| Redux Toolkit | 2.11.x | Client-side state management | RTK is the mandated choice per PROJECT.md. Use for server-actionable client state: currently selected company/tenant context, auth session (user, roles, token), active sidebar/filter state, and optimistic updates. RTK 2.x ships with Immer 11 (~30% faster mutations). Do NOT use for server data — that is TanStack Query's job. |
| React-Redux | 9.x | Redux ↔ React bindings | Required peer of Redux Toolkit. Version 9 ships alongside RTK 2.0/Redux 5.0. |
| TanStack Query | 5.90.x | Server state / data fetching | Handles all API data: caching, background refetch, stale-while-revalidate, pagination, and optimistic updates for mutations. Removes the need to manually manage loading/error states in Redux for server data. Works alongside Redux: TQ owns server state, Redux owns client state. |
| Tailwind CSS | v4.x | Utility-first CSS | v4 is the correct choice for new Next.js 16 projects. v4 uses CSS-first configuration (`@theme` directive), produces ~70% smaller production CSS than v3, and builds 5x faster. shadcn/ui officially supports Tailwind v4. |
| shadcn/ui | latest (copy-paste) | Component system | The dominant React admin UI library in 2026 (shipped 600+ components in Feb 2026). Zero runtime dependency — components are copied into your project as local TypeScript files. No version lock, no breaking upgrades. Provides DataTable, Sidebar, Card, Dialog, Form, Chart wrappers, Command palette, and all primitives needed for admin dashboards. Built on Radix UI (accessibility) + Tailwind CSS. Use over MUI (too opinionated, large bundle) or Ant Design (outdated aesthetics). |

---

### Supporting Libraries — Web Admin

#### Authentication

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| (None — custom implementation) | — | JWT session management | Do NOT use Auth.js/NextAuth for this project. The existing FastAPI backend issues its own JWT access + refresh tokens with a specific rotation protocol. Auth.js adds a translation layer that fights your existing token format. Instead: implement a thin custom auth layer using Next.js Route Handlers as an API proxy, store tokens in httpOnly cookies (not localStorage — XSS protection), and use Next.js Middleware to guard routes by checking cookie presence. This is 50 lines of code, not a library. |
| jose | 5.x | JWT decode (client-side, no verify) | Decodes JWT claims in Next.js Middleware and Server Components to extract user roles/company_id without network round-trips. Do not use for verification — the FastAPI backend verifies tokens. |

#### Forms and Validation

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| react-hook-form | 7.71.x | Form state management | Industry standard for React forms. Uncontrolled-component approach means zero re-renders on keypress. Handles all admin forms: job creation, quote line items, contractor profiles. shadcn/ui Form components are designed for react-hook-form. |
| zod | 3.x | Schema validation | Validates form inputs client-side and API payloads. Share schemas between client validation and (optionally) typed API response parsing. Use `zodResolver` from `@hookform/resolvers` to connect with react-hook-form. |
| @hookform/resolvers | 3.x | zod ↔ react-hook-form bridge | Connects zod schemas to react-hook-form's validation pipeline. |

#### Data Display

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| @tanstack/react-table | 8.21.x | Headless data table engine | Powers sortable, filterable, paginated tables for jobs list, contractor list, invoice list. shadcn/ui's DataTable component is built on TanStack Table. Headless means full control over rendering — no style conflicts. Same library used by Linear and Notion. |

#### Charts and Reporting

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Recharts | 3.8.x | Charts for reporting dashboard | React-native SVG charting library. Version 3.x rewrote state management for better React 19 compatibility. shadcn/ui's Chart components (BarChart, LineChart, AreaChart, PieChart) are thin wrappers over Recharts — using Recharts directly through shadcn/ui gives accessibility, theming, and responsive wrappers for free. Covers all reporting needs: jobs by status (bar), revenue over time (line/area), contractor utilization (bar), job completion rate (pie). 3.6M weekly downloads — well maintained. |

#### Calendar and Scheduling

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| react-big-calendar | 1.19.x | Scheduling calendar with drag-and-drop | Google Calendar / Outlook-style calendar component. Supports month, week, and day views. Built-in drag-and-drop addon (`react-big-calendar/lib/addons/dragAndDrop`) for rescheduling jobs by dragging between time slots — mirrors the Flutter drag-and-drop schedule from v1.0. MIT license, no premium tier required. Use `date-fns` as the localizer (not Moment.js). |
| date-fns | 3.x | Date formatting and arithmetic | Required as the localizer for react-big-calendar when avoiding Moment.js. Functional, tree-shakeable, TypeScript-first. Use for all date display formatting in the dashboard (job dates, schedule views, invoice due dates). Prefer over dayjs for this project because shadcn/ui's date picker components are built around date-fns. |

#### HTTP and API

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Native `fetch` | built-in | API calls from Server Components and Route Handlers | Next.js 16's App Router extends native fetch with caching, revalidation tags, and memoization. Axios opts out of this system on the server. Use native fetch in Server Components and Route Handlers. |
| TanStack Query client | 5.90.x | API calls from Client Components | In Client Components (DataTables, forms, real-time updates), use TanStack Query `useQuery`/`useMutation` with native fetch under the hood. This gives automatic caching, background refresh, and stale-while-revalidate. |

#### Utilities

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| clsx | 2.x | Conditional class names | Required by shadcn/ui for merging Tailwind classes conditionally. Included in shadcn/ui setup by default. |
| tailwind-merge | 2.x | Tailwind class deduplication | Prevents conflicting Tailwind utilities when merging class strings. Required by shadcn/ui's `cn()` utility. |
| lucide-react | 0.4x+ | Icon library | shadcn/ui's default icon set. Consistent with the component library. MIT licensed. |

---

### Testing Stack — Web Admin

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| Vitest | 2.x | Unit + component test runner | 10-20x faster than Jest on large codebases. Native ESM + TypeScript support without Babel. Jest-compatible API means minimal migration cost if team knows Jest. Next.js officially documents Vitest as a supported test runner. |
| @testing-library/react | 16.x | Component test utilities | User-centric assertions (`getByRole`, `getByText`) that mirror how real users interact with the UI. Works with Vitest via `@testing-library/jest-dom` matchers. |
| @testing-library/user-event | 14.x | Realistic user interaction simulation | Simulates real browser events (type, click, tab, keyboard navigation) more accurately than `fireEvent`. Required for testing form flows. |
| Playwright | 1.4x+ | E2E browser testing | Faster than Cypress in CI (290ms vs 420ms per action). Free built-in test sharding (no paid cloud). Supports Chromium, Firefox, and WebKit. TypeScript-first. Next.js has official Playwright integration docs. Use for: full auth flows, job creation wizard, drag-and-drop calendar, calendar conflict detection. |
| MSW (Mock Service Worker) | 2.x | API mocking in tests | Intercepts fetch calls at the network level — no Axios adapter needed. Works in both Vitest (Node environment) and Playwright. Use to mock FastAPI responses in component tests without spinning up the backend. |

---

### Development Tools — Web Admin

| Tool | Purpose | Notes |
|------|---------|-------|
| ESLint | Lint TypeScript + React | Use `eslint-config-next` (bundled with Next.js) — covers React hooks rules, import order, and Next.js-specific rules. |
| Prettier | Code formatting | Set up alongside ESLint. Use `prettier-plugin-tailwindcss` to auto-sort Tailwind class names. |
| TypeScript strict mode | Type checking | Enable `"strict": true` in tsconfig. Next.js 16 defaults to strict mode. Catches API response shape mismatches early. |

---

---

## v3.0 AI Feature Additions

**These are NEW additions only. Do not reinstall or replace anything from the section above.**

This section answers: what specific libraries enable the five new v3.0 capabilities — Claude API integration, real-time chat, photo annotation (web + mobile), dependency graph engine, and online-first sync architecture.

---

### 1. Claude API Integration (Tool Use + Streaming)

#### Backend: Python SDK

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| anthropic | 0.86.0 | Claude API client — tool use, streaming, structured outputs | The official SDK released March 18, 2026. Use `AsyncAnthropic` (async client) to keep FastAPI's event loop unblocked during AI calls. Supports: `tool_runner` for automated tool-call loops, `client.messages.stream()` async context manager for token streaming, and Pydantic-native structured outputs via JSON schema. Do NOT use LangChain or LlamaIndex — they add abstraction that fights Claude's native tool use and structured output APIs, which Anthropic just launched in beta (November 2025). Direct SDK is 50 lines; a framework is 500 lines with worse observability. |

**Integration pattern with FastAPI:**

```python
# AI calls stay on the backend — never expose ANTHROPIC_API_KEY to clients
from anthropic import AsyncAnthropic

client = AsyncAnthropic()  # reads ANTHROPIC_API_KEY from env

# Tool use: AI breaks project into trade scopes
async def plan_project(description: str) -> ProjectPlan:
    async with client.messages.stream(
        model="claude-opus-4-5",
        max_tokens=4096,
        tools=[TRADE_BREAKDOWN_TOOL, TASK_PLANNER_TOOL],
        messages=[{"role": "user", "content": description}],
    ) as stream:
        # collect structured tool call results
        async for event in stream:
            ...
```

**Structured outputs for AI planning responses** (PUBLIC BETA as of November 2025):

Define Pydantic models for `ProjectPlan`, `TradeScope`, `Task` and pass them to the API. Claude's response is guaranteed to conform to the schema — no defensive parsing needed.

#### Backend: SSE Streaming to Web Clients

AI responses are streamed token-by-token to the web dashboard using SSE. WebSocket is overkill for unidirectional AI text streaming.

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| sse-starlette | 3.3.3 | SSE streaming for FastAPI AI responses | Production-ready W3C SSE implementation for Starlette/FastAPI. FastAPI 0.135.0+ also ships built-in SSE, but sse-starlette 3.x is more battle-tested for streaming LLM responses and provides `EventSourceResponse` with proper client disconnect detection. Use for: AI project intake chat streaming, AI contractor interview streaming, AI daily checklist generation. |

**Note:** FastAPI's built-in native WebSocket (no external library) handles bidirectional GC ↔ contractor chat. SSE handles unidirectional AI response streaming. These are different use cases — do not conflate them.

#### Web: Consuming Streamed AI Responses

No new library needed. Use the native `EventSource` browser API (or a thin wrapper) in the Next.js Client Component handling AI chat:

```typescript
// web — no library needed for SSE consumption
const source = new EventSource('/api/ai/plan-project');
source.onmessage = (e) => appendToken(e.data);
source.onerror = () => source.close();
```

#### Mobile: AI Chat (No Streaming on Mobile)

Mobile clients receive completed AI-generated plans from the REST API, not streamed tokens. AI planning happens in the background on the server; mobile receives the finished artifact (task list, checklist). The exception: if GC uses the mobile app for AI intake chat, display a loading state and poll or use a WebSocket for completion notification. Do NOT implement SSE on mobile — Dio does not natively support it cleanly, and mobile users expect a "generating..." state, not streaming text.

---

### 2. Real-Time Chat (GC ↔ Contractor Bidirectional)

FastAPI's built-in WebSocket support (zero new backend libraries needed) handles bidirectional chat. The existing FastAPI setup already supports `@app.websocket()` routes via ASGI.

#### Backend: Connection Management + Scaling

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| redis | 7.1.1 | WebSocket pub/sub for horizontal scaling | When the app runs on multiple FastAPI workers (multiple uvicorn processes or multiple servers), each worker only knows its own WebSocket connections. A message from GC connected to worker A must reach a contractor connected to worker B. Redis pub/sub solves this: each worker subscribes to a Redis channel per conversation; any worker publishes to Redis and all subscribers deliver to their local connections. Use `redis.asyncio` (included in `redis` package v7 — do NOT install separate `aioredis`, which is deprecated and merged into `redis`). For v3.0 single-server deployments, this can be skipped initially and added when scaling. |

**Integration point:** Redis is already used (or likely used) for rate limiting via `slowapi`. Reuse the same Redis instance. Add a `REDIS_URL` env var if not already present.

**Single-server alternative (no Redis):** An in-process `ConnectionManager` dict suffices for single-server deployments. Plan for Redis when adding a second worker.

#### Mobile: Flutter WebSocket Client

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| web_socket_channel | 3.0.3 | Flutter WebSocket client for chat | Google's official Dart WebSocket package. Cross-platform (Android, iOS, web). Provides `WebSocketChannel` as a Dart `Stream` — integrates naturally with Riverpod `StreamProvider`. Handles the GC ↔ contractor chat channel and real-time task progress updates pushed from the server. Use `IOWebSocketChannel.connect()` for Android/iOS. |

**Note:** `web_socket_channel` is already likely in the Flutter pubspec if used anywhere — verify before adding. It is a transitive dependency of several packages.

#### Web: Next.js WebSocket Client

No new library needed. The browser's native `WebSocket` API suffices for the chat UI. Wrap it in a custom React hook (`useChatWebSocket`) that manages connection lifecycle, reconnection, and message queue. Do not add `socket.io-client` — the backend uses native FastAPI WebSocket, not Socket.io protocol.

```typescript
// web/src/hooks/useChatWebSocket.ts — no external library
function useChatWebSocket(conversationId: string) {
  const ws = useRef<WebSocket | null>(null);
  // reconnect on disconnect, parse messages, pipe to state
}
```

---

### 3. Photo Annotation Canvas

Two separate implementations are required: one for the web dashboard (React + Canvas), one for the mobile app (Flutter). They produce the same annotation data format (stored as JSON overlay on the image) so the server-side storage schema is shared.

#### Web: Fabric.js

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| fabric | 7.2.0 | Interactive canvas for photo annotation (web) | Fabric.js is the most mature JavaScript canvas library with a complete interactive object model. Version 7 (latest as of March 2026) removes Node 18 support (no issue for browsers) and requires Node 20+ for build tooling. Provides: `IText` for editable text overlays, `Arrow` and `Line` for directional annotations, `Circle`/`Rect` for shape callouts, `Image` for loading the source photo onto canvas, and JSON serialization of all annotations (`canvas.toJSON()` / `canvas.loadFromJSON()`). Use over marker.js (headless, requires UI wrapper, linkware license that requires attribution), Annotorious (specialized for academic image annotation, not construction use case), and react-image-annotation (unmaintained since 2021). Fabric.js has 29K GitHub stars, active maintenance, and a direct React integration pattern via `useEffect` + `ref`. MIT license. |

**React integration pattern:**

```typescript
// web — no React wrapper package needed
import { Canvas, IText, Circle } from 'fabric';

useEffect(() => {
  const canvas = new Canvas(canvasRef.current);
  canvas.add(new IText('crack here', { left: 100, top: 150 }));
  return () => canvas.dispose();
}, []);
```

**Annotation data stored as JSON:** `canvas.toJSON()` produces a serializable annotation overlay. Store this JSON alongside the image URL in the backend. Render on read with `canvas.loadFromJSON()`. This is framework-agnostic and works for both web and any future platform.

#### Mobile: pro_image_editor

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| pro_image_editor | 12.0.7 | Photo annotation on Flutter mobile | The most actively maintained Flutter image annotation package as of March 2026 (published 5 days before research date). Provides: Paint Editor with freehand brushes, circles, and arrows; Text Editor with full text styling; supports Android, iOS, web, and desktop. Critical: it exports annotated images as pixel-composited PNGs (not JSON overlay). Store the exported PNG for display, and optionally store the annotation state JSON for re-editing. Use over `image_painter` (basic, no arrows), `image_editor_plus` (less maintained), and custom `CustomPainter` (requires building all annotation tools from scratch). MIT license. |

**Integration with existing photo flow:** The existing v1.0 photo capture uses `image_picker` and uploads to the backend. Extend this flow: capture → open `pro_image_editor` → user annotates → export PNG → upload. The exported PNG replaces the raw photo for task-level annotations.

**Annotation storage decision:** The backend stores the annotated PNG URL. If re-editing is required, also store the `pro_image_editor` state JSON separately. For v3.0, store the composited PNG only — re-editing is a v4.0 concern.

---

### 4. Dependency Graph Engine

The dependency graph is a directed acyclic graph (DAG) where nodes are tasks and edges represent "task A must complete before task B can start." This is a data model and algorithm problem, not a heavyweight framework problem.

#### Backend: Python Standard Library + NetworkX

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| networkx | 3.x | DAG operations: cycle detection, topological sort, critical path | NetworkX is the standard Python graph library with 14K GitHub stars. Use it for: `nx.is_directed_acyclic_graph()` (validate no circular dependencies), `nx.topological_sort()` (determine task execution order), `nx.dag_longest_path()` (critical path for schedule estimates). NetworkX is NOT stored in the database — it is a compute library. Build the graph in-memory from the SQLAlchemy-stored adjacency list, run algorithms, discard. For ContractorHub's scale (100–500 tasks per project), NetworkX is instantaneous; no distributed scheduler needed. |

**Database storage:** Store dependencies as an adjacency list in PostgreSQL. No graph database (Neo4j etc.) is needed — the graph is per-project and small:

```sql
-- New table: task_dependencies
CREATE TABLE task_dependencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    predecessor_task_id UUID NOT NULL REFERENCES tasks(id),
    successor_task_id UUID NOT NULL REFERENCES tasks(id),
    UNIQUE(predecessor_task_id, successor_task_id)
);
-- RLS policy: same as other tenant tables
```

**Python standard library `graphlib`:** Python 3.9+ ships `graphlib.TopologicalSorter`. Use this for simple topological sorts without adding NetworkX. Use NetworkX when you need cycle detection AND topological sort AND path length calculations in one place. For v3.0, NetworkX is the correct choice because critical path computation is required for schedule adaptation.

**Installation:** `pip install networkx` (no extra dependencies — pure Python).

#### Frontend: Dependency Graph Visualization

For the GC cross-trade monitoring dashboard (timeline with dependencies shown as Gantt-style connectors), the existing Recharts library handles basic bar/timeline charts. For interactive dependency graph visualization (nodes and edges):

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| @xyflow/react (React Flow) | 12.x | Interactive dependency graph UI (web only) | React Flow is the standard library for interactive node-edge diagrams in React (30K GitHub stars, MIT license). Use for the GC monitoring dashboard's "dependency graph view" showing trade scopes as nodes and dependencies as edges. Provides drag-to-rearrange, zoom/pan, and custom node renderers. Do NOT use D3.js directly — D3 requires imperative DOM manipulation that fights React's rendering model. React Flow wraps D3's layout algorithms in a React-friendly API. Only add this if the cross-trade monitoring dashboard includes a dependency graph view; if the Gantt timeline view is sufficient, skip it. |

---

### 5. Online-First Sync Architecture

v3.0 shifts from offline-first (Drift as source of truth) to online-first (API as source of truth) with a local Drift cache for field execution. This is an architectural shift, not a library change.

#### No New Libraries Required

The existing Drift + Riverpod + Dio stack already supports this pattern:

- **API as source of truth:** Dio calls the FastAPI backend. Riverpod providers fetch on load and background-refresh.
- **Drift as read-through cache:** After fetching from API, write results to Drift. Riverpod StreamProviders read from Drift for reactive UI. This gives offline cache "for free" using existing infrastructure.
- **Selective offline support:** AI-generated daily checklists and task lists are cached in Drift on fetch. Field contractors can execute tasks offline; completions are queued via the existing transactional outbox pattern.
- **What changes:** Remove the "offline-first write" assumption. Writes (task completion, notes, photos) go to the API first; Drift is updated on success (or queued in the outbox for retry if offline). This is the reverse of v1.0's approach.

#### Cache Invalidation Strategy

Use Riverpod's `ref.invalidate()` and `ref.refresh()` to force re-fetch from API after mutations. Drift cache is invalidated by overwriting with fresh API data — no cache TTL management needed.

#### What NOT to Add

Do NOT add PowerSync, Supabase Realtime, or any sync-as-a-service middleware. The existing outbox pattern handles offline sync for the cases that need it (field task completion). Adding a sync service creates a third data layer and fights the existing RLS architecture.

---

## Installation

### Next.js App Bootstrap (v1.0/v2.0 — Already Done)

```bash
# Scaffold with App Router + TypeScript + Tailwind v4
npx create-next-app@latest web --typescript --tailwind --app --turbopack

cd web

# Core state management
npm install @reduxjs/toolkit react-redux @tanstack/react-query

# Auth utilities
npm install jose

# Forms and validation
npm install react-hook-form zod @hookform/resolvers

# Data tables
npm install @tanstack/react-table

# Charts
npm install recharts

# Calendar and dates
npm install react-big-calendar date-fns

# shadcn/ui CLI (installs components on demand)
npx shadcn@latest init

# Icons (pulled in by shadcn init, but explicit)
npm install lucide-react

# Utilities
npm install clsx tailwind-merge

# Dev dependencies
npm install -D vitest @vitejs/plugin-react jsdom
npm install -D @testing-library/react @testing-library/user-event @testing-library/jest-dom
npm install -D msw
npm install -D @playwright/test
npm install -D prettier prettier-plugin-tailwindcss eslint-config-prettier
```

### v3.0 Additions — Backend (Python)

```bash
cd backend

# Claude API
uv add anthropic  # installs 0.86.0

# SSE streaming for AI responses
uv add sse-starlette  # installs 3.3.3

# Redis for WebSocket pub/sub (optional for single-server; required for multi-worker)
uv add redis  # installs 7.1.1, includes redis.asyncio

# Dependency graph algorithms
uv add networkx  # installs 3.x
```

### v3.0 Additions — Flutter (Mobile)

```yaml
# mobile/pubspec.yaml — add these dependencies
dependencies:
  web_socket_channel: ^3.0.3      # WebSocket client for real-time chat
  pro_image_editor: ^12.0.7       # Photo annotation on mobile
```

```bash
cd mobile && flutter pub get
```

### v3.0 Additions — Web (Next.js)

```bash
cd web

# Photo annotation canvas
npm install fabric  # installs 7.2.0

# Interactive dependency graph (only if graph view is built)
npm install @xyflow/react  # installs 12.x
```

### shadcn/ui Core Components for Admin Dashboard

```bash
# Run after `npx shadcn@latest init`
npx shadcn@latest add button input label card table dialog form
npx shadcn@latest add sidebar navigation-menu dropdown-menu
npx shadcn@latest add data-table chart badge select textarea
npx shadcn@latest add toast sonner calendar date-picker
npx shadcn@latest add command sheet popover
```

---

## Alternatives Considered

### v1.0/v2.0 Alternatives

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Next.js 16 (App Router) | Next.js 16 (Pages Router) | Never on a new project. App Router enables Server Components, async/await in components, and Next.js Middleware for route guards. Pages Router is for projects already on it. |
| shadcn/ui | Material UI (MUI) | If the organization has existing MUI design system tokens and wants consistency across multiple apps. MUI is a heavy dependency (~300KB) vs shadcn's zero runtime cost. |
| shadcn/ui | Ant Design | If building a data-heavy internal tool for Chinese enterprise — Ant Design has strong support for that ecosystem. Otherwise shadcn has better React 19/Tailwind v4 support. |
| Recharts (via shadcn) | Chart.js (react-chartjs-2) | Chart.js uses Canvas, which can handle 1M+ data points smoothly. If the reporting dashboard needs to render thousands of data points simultaneously, switch to react-chartjs-2. For ContractorHub's scale (< 10K jobs per company), Recharts SVG is fine. |
| react-big-calendar | FullCalendar | FullCalendar has more built-in features (timeline view, resource scheduling) but drag-and-drop and resource views require the premium Scheduler package ($200+/year/developer). react-big-calendar covers ContractorHub's needs (week/day drag-and-drop) under MIT for free. |
| TanStack Query | SWR | SWR is simpler but less capable. TanStack Query's mutation API, cache invalidation strategies, and devtools are superior for a complex admin dashboard with many interdependent data entities. |
| Playwright | Cypress | Cypress is better for DX (visual time-travel debugger) but requires paid Cypress Cloud for parallelization. Playwright's free sharding and WebKit support make it the better choice for a full-stack project with limited CI budget. |
| Vitest | Jest | Jest is the legacy choice. Vitest is 10-20x faster and has first-class ESM/TypeScript support. No reason to use Jest for a new Next.js 16 project. |
| Native fetch + TanStack Query | Axios | Axios opts out of Next.js App Router's extended fetch caching system on the server side. Native fetch gets automatic request memoization, revalidation tags, and CDN caching. Use native fetch everywhere; TanStack Query wraps it client-side. |
| Custom JWT auth (httpOnly cookies) | Auth.js / NextAuth | Auth.js is the right choice when you use social OAuth providers (Google, GitHub). For this project, the FastAPI backend is the only auth authority and uses its own JWT format with refresh token rotation. Auth.js would add complexity without benefit. |

### v3.0 Alternatives

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Claude SDK | `anthropic` direct SDK | LangChain, LlamaIndex | Framework abstractions add 500+ LOC of configuration that fights Claude's native tool use and structured output APIs. Direct SDK is more observable and debuggable. |
| AI streaming transport | SSE (sse-starlette) | WebSocket for AI | AI text generation is unidirectional (server → client). SSE is the correct protocol. WebSocket adds bidirectional complexity that is not needed for token streaming. |
| Photo annotation (web) | Fabric.js 7.x | marker.js 3 | marker.js requires attribution linkware license for free use. Fabric.js is fully MIT. marker.js is "headless" so you need to build all toolbar UI anyway. Fabric.js has a richer object model for construction-specific annotations (measurements, callouts). |
| Photo annotation (web) | Fabric.js 7.x | Annotorious | Annotorious is specialized for academic/scholarly image annotation (text tags, polygons for regions). Fabric.js is better for construction site annotation (arrows, measurements, text callouts). |
| Photo annotation (mobile) | pro_image_editor | Custom CustomPainter | Building annotation tools from scratch (arrow tool, circle tool, text input, erase) is 1,000+ lines of Flutter canvas code. pro_image_editor ships all of this battle-tested. Only use CustomPainter if the annotation UX requirements differ dramatically from a standard editor. |
| Dependency graph DB | PostgreSQL adjacency list | Neo4j, ArangoDB | Graph databases add operational complexity for a problem that is small-scale (100–500 tasks per project). PostgreSQL adjacency list + NetworkX in Python gives 99% of the capability. Add a graph DB if project sizes exceed 10K nodes or if graph traversal queries become a bottleneck. |
| Dependency graph algorithms | NetworkX | Python `graphlib` | `graphlib` does topological sort only. NetworkX adds cycle detection AND critical path calculation AND the full graph API in one library. For v3.0's schedule adaptation (critical path = required), NetworkX wins. |
| WebSocket scaling | Redis pub/sub | Socket.io | Socket.io requires `python-socketio` on the backend, which is a separate server protocol (not native WebSocket). The existing FastAPI stack uses standard WebSocket. Adding Socket.io means migrating the protocol layer. Redis pub/sub with native FastAPI WebSocket is architecturally cleaner. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| LangChain / LlamaIndex | Over-abstracted AI framework that fights Claude's native tool use API. Makes prompt engineering opaque and debugging hard. | Direct `anthropic` SDK |
| Local/on-device LLM | Out of scope per PROJECT.md. Claude API provides superior quality and zero mobile compute burden. | Claude API (server-side) |
| Socket.io (python-socketio) | Separate WebSocket subprotocol that requires matching client. FastAPI's native WebSocket is cleaner and already available. | FastAPI native WebSocket + `redis.asyncio` for pub/sub |
| aioredis | Deprecated. Merged into the `redis` package as `redis.asyncio`. | `redis` >= 7.1 |
| Neo4j / ArangoDB | Graph database adds operational complexity for small-scale DAGs. PostgreSQL adjacency list + NetworkX is sufficient. | PostgreSQL + NetworkX |
| PowerSync / Supabase Realtime | Third-party sync service creates a third data layer and fights PostgreSQL RLS. The existing outbox pattern handles the offline sync cases that need it. | Existing Drift transactional outbox |
| localStorage for JWT storage | JavaScript-accessible storage is vulnerable to XSS attacks. OWASP explicitly recommends against it for session tokens. | httpOnly cookies set by Next.js Route Handler |
| Redux for server/API data | Requires manual loading/error/success state management. | TanStack Query for server state; Redux for client-only state |
| Moment.js | Effectively unmaintained, ships non-tree-shakeable 300KB bundle. | date-fns |
| Tailwind CSS v3 | v3 requires a config file and produces larger CSS bundles. v4 is the correct choice for new Next.js 16 projects. | Tailwind CSS v4 |

---

## Integration Points with Existing FastAPI Backend

### Auth Flow (Web)

1. `POST /auth/login` → FastAPI returns `{ access_token, refresh_token }` (existing endpoint, no changes needed)
2. Next.js Route Handler (`/api/auth/login`) receives credentials from the browser, calls FastAPI, then sets httpOnly cookies: `access_token` and `refresh_token`
3. Subsequent requests from Client Components go through Next.js Route Handlers (acting as API proxy) or directly to FastAPI with the access token forwarded from the cookie
4. Token refresh: Next.js Middleware or Route Handler calls `POST /auth/refresh` (existing endpoint) when access token is expired
5. Logout: Route Handler clears cookies and calls `POST /auth/logout` (existing endpoint)

No FastAPI auth changes required. The web dashboard is a new consumer of the existing auth API.

### CORS Configuration (Backend Change Required)

The existing FastAPI CORS config likely allows only the Flutter dev origin. Add the Next.js dev/prod origins:

```python
# backend/app/main.py — add web origins
ALLOWED_ORIGINS = [
    "http://localhost:3000",        # Next.js dev
    "https://admin.contractorhub.com",  # Next.js prod
    # existing mobile origins...
]
```

### company_id / Tenant Context

The existing JWT carries `company_id`. The web admin reads this from the decoded JWT (via `jose`) to:
- Display the correct company name in the nav
- Include in API requests (FastAPI extracts it from the JWT server-side via RLS — the web client does not need to manually inject it)

### API Response Schemas

The existing FastAPI Pydantic schemas are the source of truth. Define TypeScript types in `web/src/types/` that mirror them. Do not redefine business logic — the FastAPI backend owns all validation and conflict detection.

```typescript
// web/src/types/job.ts — mirrors FastAPI JobResponse schema
export interface Job {
  id: string;
  company_id: string;
  title: string;
  status: 'quote' | 'scheduled' | 'in_progress' | 'complete' | 'invoiced';
  scheduled_start: string;   // ISO 8601
  scheduled_end: string;
  contractor_id: string | null;
  client_id: string;
}
```

### New v3.0 Integration Points

**Claude API:**
- `ANTHROPIC_API_KEY` in backend env (never exposed to clients)
- AI endpoints are FastAPI routes authenticated with existing JWT middleware
- AI-generated plans stored as structured JSON in PostgreSQL (new `projects`, `trade_scopes`, `tasks` tables)
- Tenant isolation via existing RLS — AI content is company-scoped

**WebSocket chat:**
- New FastAPI WebSocket endpoint: `ws://api/ws/conversations/{conversation_id}`
- Auth: pass JWT as a query param or in the initial handshake message (httpOnly cookies are not sent with WebSocket connections by default)
- `REDIS_URL` env var for pub/sub (add to backend `.env`)

**Photo annotations:**
- Annotated images stored as PNGs in the existing file upload infrastructure (backend `/api/attachments` endpoint already exists from v1.0)
- Annotation metadata (fabric.js JSON or pro_image_editor state) stored as a `JSONB` column on the `task_attachments` table (extend existing schema)

**Dependency graph:**
- New `task_dependencies` table (adjacency list, RLS-scoped)
- NetworkX graph is constructed in-memory from this table for each API request that needs graph operations
- No graph data sent to clients as a graph structure — send as a serialized list of `{ predecessor_task_id, successor_task_id }` pairs; client reconstructs for visualization

---

## Stack Patterns by Variant

**For server-rendered analytics/reporting pages:**
- Fetch data in Next.js Server Components (no TanStack Query needed)
- Use native fetch with `{ next: { revalidate: 60 } }` for 1-minute cache
- Render Recharts charts as Client Components (charts require browser APIs)

**For interactive scheduling calendar:**
- Calendar itself is a Client Component (drag-and-drop requires browser events)
- Seed initial calendar data via Server Component → pass as props
- Use TanStack Query `useMutation` to update job times after drag; invalidate calendar query on success

**For data tables (jobs list, contractor list, invoices):**
- Use TanStack Table with server-side pagination (pass `page` and `limit` to FastAPI)
- Use TanStack Query with `keepPreviousData: true` to avoid loading flicker on page change
- Column definitions typed against the TypeScript API types

**For multi-step job creation wizard:**
- Use `react-hook-form` with `useFormContext` to share state across steps
- Each step validates only its own fields before advancing
- Final submission via TanStack Query `useMutation` to `POST /jobs`

**For AI project intake chat (v3.0):**
- Web: Client Component with `EventSource` for SSE token streaming
- AI endpoint: `POST /api/ai/plan-project` returns SSE stream
- Store completed plan to PostgreSQL after stream ends; notify client via SSE `[DONE]` event

**For GC ↔ contractor chat (v3.0):**
- Web: native `WebSocket` in a custom React hook
- Mobile: `web_socket_channel` `IOWebSocketChannel` in a Riverpod `StreamProvider`
- Backend: FastAPI `@app.websocket()` route with in-process `ConnectionManager` (single server) or Redis pub/sub (multi-worker)

**For photo annotation (v3.0):**
- Web: Fabric.js canvas overlay on the photo; save `canvas.toJSON()` to backend
- Mobile: `pro_image_editor` → export composited PNG → upload to existing attachments endpoint

**For dependency graph visualization (v3.0):**
- Web: React Flow (`@xyflow/react`) renders trade scopes as nodes and dependencies as edges
- Backend: NetworkX computes critical path; returns `{ critical_path: [task_id,...], earliest_start: {...} }` as JSON
- Mobile: Display dependency info as text (predecessor/successor list) — no graph UI on mobile

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Next.js 16 | React 19, TypeScript 5, Tailwind v4 | App Router requires React 19 for full feature set |
| shadcn/ui | Tailwind v4, Radix UI primitives, react-hook-form 7.x | shadcn has dedicated Tailwind v4 docs — follow them exactly |
| Redux Toolkit 2.11 | React-Redux 9.x, Redux 5.x, Reselect 5.x | These must all be at major versions that shipped together (all November 2023+) |
| TanStack Query 5.x | React 18+ (uses useSyncExternalStore) | v5 requires React 18 minimum — React 19 fully supported |
| react-big-calendar 1.19 | date-fns 3.x | Use `dateFnsLocalizer` from `react-big-calendar/lib/localizers/date-fns`. Do NOT use the Moment.js localizer. |
| Recharts 3.x | React 18+, React 19 | Recharts 3.0 rewrote state management for React 19 compatibility |
| Playwright 1.4x | Node 18+ | Install via `npm init playwright@latest` for proper browser binary setup |
| Vitest 2.x | Vite 5+, Next.js 16 | Requires vite config alongside next.config — see Next.js Vitest docs |
| anthropic 0.86 | Python 3.9+, FastAPI async | Use `AsyncAnthropic` — the sync client blocks the event loop |
| sse-starlette 3.3.3 | Starlette 0.27+, FastAPI 0.100+ | Works with existing FastAPI 0.115 |
| redis 7.1.1 | Python 3.10+ | Use `redis.asyncio` — the sync client blocks the event loop |
| networkx 3.x | Python 3.9+, no other deps | Pure Python — no C extensions, no platform issues |
| fabric 7.2.0 | React 19, TypeScript 5, Node 20+ | Use `useEffect` + `ref` pattern; Fabric mutates the DOM directly |
| @xyflow/react 12.x | React 19 | Requires React 18+ |
| pro_image_editor 12.0.7 | Flutter 3.22+ | Check Flutter SDK version constraint before adding |
| web_socket_channel 3.0.3 | Dart 3.x, Flutter 3.x | Cross-platform: Android, iOS, web |

---

## Sources

**v1.0/v2.0 sources:**
- [Next.js 15/16 features 2026](https://jishulabs.com/blog/nextjs-15-16-features-migration-guide-2026) — Next.js 16 stable confirmed (MEDIUM confidence)
- [Redux Toolkit npm](https://www.npmjs.com/package/@reduxjs/toolkit) — version 2.11.2 verified (HIGH confidence)
- [shadcn/ui 2026 admin dashboard guide](https://adminlte.io/blog/build-admin-dashboard-shadcn-nextjs/) — shadcn/ui as standard choice confirmed (MEDIUM confidence)
- [Tailwind CSS v4 announcement](https://tailwindcss.com/blog/tailwindcss-v4) — v4 performance improvements verified (HIGH confidence)
- [Recharts npm](https://www.jsdocs.io/package/recharts) — version 3.8.0 verified (HIGH confidence)
- [react-big-calendar npm](https://www.npmjs.com/package/react-big-calendar) — version 1.19.4 verified (HIGH confidence)
- [TanStack Query npm](https://www.npmjs.com/package/@tanstack/react-query) — version 5.90.21 verified (HIGH confidence)
- [TanStack Table npm](https://www.npmjs.com/package/@tanstack/react-table) — version 8.21.3 verified (HIGH confidence)
- [react-hook-form npm](https://www.npmjs.com/package/react-hook-form) — version 7.71.2 verified (HIGH confidence)
- [Playwright vs Cypress 2026](https://www.getautonoma.com/blog/playwright-vs-cypress) — Playwright recommended for enterprise (MEDIUM confidence)
- [Vitest Next.js guide](https://nextjs.org/docs/app/guides/testing/vitest) — Official Next.js Vitest docs (HIGH confidence)

**v3.0 sources:**
- [anthropic PyPI](https://pypi.org/project/anthropic/) — version 0.86.0 released March 18, 2026 (HIGH confidence)
- [Anthropic Python SDK GitHub](https://github.com/anthropics/anthropic-sdk-python) — tool use, streaming, structured outputs (HIGH confidence)
- [Anthropic structured outputs announcement](https://platform.claude.ai/docs/en/build-with-claude/structured-outputs) — public beta November 2025 (HIGH confidence)
- [sse-starlette PyPI](https://pypi.org/project/sse-starlette/) — version 3.3.3, March 2026 (HIGH confidence)
- [FastAPI SSE docs](https://fastapi.tiangolo.com/tutorial/server-sent-events/) — official FastAPI SSE documentation (HIGH confidence)
- [redis PyPI](https://pypi.org/project/redis/) — version 7.1.1, February 2026, requires Python 3.10+ (HIGH confidence)
- [web_socket_channel pub.dev](https://pub.dev/packages/web_socket_channel) — version 3.0.3, Google-maintained (HIGH confidence)
- [pro_image_editor pub.dev](https://pub.dev/packages/pro_image_editor) — version 12.0.7, March 2026 (HIGH confidence)
- [fabric npm](https://www.npmjs.com/package/fabric) — version 7.2.0, March 2026 (HIGH confidence)
- [Fabric.js v7 upgrade guide](https://fabricjs.com/docs/upgrading/upgrading-to-fabric-70/) — v7 migration notes (MEDIUM confidence)
- [marker.js 3 blog](https://blog.ailon.org/marker-js-3-is-here-add-image-annotation-to-your-web-apps-9139dcc2bdd2) — headless library, linkware license confirmed (MEDIUM confidence)
- [NetworkX documentation](https://networkx.org/documentation/stable/) — DAG algorithms: cycle detection, topological sort, critical path (HIGH confidence)
- [FastAPI WebSocket scaling with Redis](https://medium.com/@nandagopal05/scaling-websockets-with-pub-sub-using-python-redis-fastapi-b16392ffe291) — Redis pub/sub pattern for multi-worker scaling (MEDIUM confidence)
- [React Flow (@xyflow/react)](https://reactflow.dev/) — dependency graph visualization (MEDIUM confidence)

---

*Stack research for: ContractorHub — v3.0 AI-Driven Construction Management additions*
*Researched: 2026-03-19*
