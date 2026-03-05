# Phase 1: Foundation - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Flutter + FastAPI project skeletons with multi-tenant data isolation and role models. Establishes all foundational patterns that every subsequent phase builds on. No user-visible features — pure infrastructure and architecture.

Requirements: INFRA-01, INFRA-02, INFRA-05, INFRA-06

</domain>

<decisions>
## Implementation Decisions

### Project Structure
- Monorepo: single git repo with `/mobile` (Flutter) and `/backend` (Python/FastAPI) top-level folders
- Flutter app: feature-first architecture — organized by domain (jobs/, scheduling/, clients/), each feature has its own models, screens, providers
- Python backend: domain-driven structure — organized by domain (jobs/, scheduling/, users/), each domain has routes, services, models, schemas
- REST API — standard REST endpoints, no GraphQL; simpler, well-suited for mobile, easier offline sync

### Role Experience
- Same app shell with content filtered by role — not separate home screens per role
- Shared bottom navigation tabs across all three roles, content filtered by what each role can access
- A user can have multiple roles (e.g., contractor in one company, admin in another) — multi-role support from day one
- Role-gated route guards control what each role can see and access

### Company Onboarding
- Self-service signup: company admin signs up, creates company profile, starts adding contractors
- Full company profile at signup: company name, address, phone, trade types, logo, business number
- Contractors and clients added via invite (email/SMS) — admin sends invite link, person signs up and joins
- Contractors tagged with one or more trade types (builder, electrician, plumber, HVAC, etc.) — enables smart job assignment in later phases

### Dev Environment
- Docker Compose: one command starts FastAPI + PostgreSQL + Redis in containers
- Seed data script available but optional — pre-loaded demo company with contractors, clients, and sample jobs for testing
- GitHub Actions CI pipeline from day one — run tests on every push
- Strict code quality enforcement: dart analyze + ruff (Python) + pre-commit hooks from the start

### Claude's Discretion
- Bottom tab structure and icons (Claude designs based on feature set)
- Exact directory structure within feature-first and domain-driven patterns
- Docker Compose service configuration details
- CI pipeline configuration specifics
- Seed data composition (which demo entities to create)

</decisions>

<specifics>
## Specific Ideas

- Trade tags on contractors should support multiple trades per contractor (e.g., a contractor who does both plumbing and electrical)
- The app should feel like one unified app with different views, not three separate apps stitched together
- Company signup needs real business info upfront — not a "fill in later" minimal flow

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, all patterns established in this phase

### Established Patterns
- None yet — this phase SETS the patterns for all subsequent phases

### Integration Points
- Flutter Drift local DB schema established here is the foundation for Phase 2 (Offline Sync)
- FastAPI tenant middleware and RLS policies established here govern all future endpoints
- Role model and route guards established here are used by every feature phase (4-8)
- Docker Compose configuration is the dev environment for all phases

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-03-04*
