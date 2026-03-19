---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: AI-Driven Construction Management
status: Defining requirements
stopped_at: null
last_updated: "2026-03-19"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-19)

**Core value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.
**Current focus:** Defining requirements for v3.0

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-19 — Milestone v3.0 started

## Accumulated Context

### Decisions

- v3.0: Online-first architecture (AI requires connectivity), offline cache for daily task execution
- v3.0: Claude API with tool use for structured project planning (no local AI)
- v3.0: Same Flutter app for GC and contractors with role-based views
- v3.0: Project → Trade Scope → Task hierarchy with cross-trade dependency graph
- v3.0: Append-only data (notes, photos, chat) eliminates most sync conflicts
- v3.0: Version-based optimistic locking for task status conflicts
- v3.0: AI plans are server-authoritative; offline mode is read-cached + queue writes

### Pending Todos

None yet.

### Blockers/Concerns

- Anthropic API key needed for AI features — confirm billing/pricing model
- Photo annotation on web needs canvas library evaluation (existing mobile drawing pad uses CustomPainter)
- Chat system architecture: WebSocket vs polling vs server-sent events — decide during planning

## Session Continuity

Last session: 2026-03-19
Stopped at: Milestone v3.0 initialization
Resume file: None
