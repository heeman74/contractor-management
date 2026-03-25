# Phase 24: GC Inspection Workflow - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 24-gc-inspection-workflow
**Areas discussed:** Inspection flow, Rejection experience, Punch list design, Site walk flagging

---

## Inspection Flow

### Q1: How should a GC inspect a completed task?

| Option | Description | Selected |
|--------|-------------|----------|
| Inline on task detail | Add approve/reject buttons to existing task detail bottom bar | ✓ |
| Dedicated inspection screen | Separate screen with side-by-side evidence + form layout | |
| Bottom sheet overlay | Tap "Inspect" for bottom sheet with quick options | |

**User's choice:** Inline on task detail
**Notes:** Simplest approach, reuses existing screen.

### Q2: What should the GC see during inspection?

| Option | Description | Selected |
|--------|-------------|----------|
| Just existing content | Photos, notes, attachments are enough | |
| Existing + time summary | Add total hours and status timeline | |
| Existing + time summary + checklist | Add mini inspection checklist before approve enables | ✓ |

**User's choice:** Existing content + time summary + checklist

### Q3: Should checklist items be fixed or configurable?

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed checklist | Same universal items for every task | |
| Per-trade defaults | Each trade scope defines its own checklist items with universal fallback | ✓ |
| Claude decides | Claude picks pragmatic approach | |

**User's choice:** Per-trade configurable with universal fallback

---

## Rejection Experience

### Q4: What status does a rejected task get?

| Option | Description | Selected |
|--------|-------------|----------|
| New "rejected" status | Distinct state in task lifecycle | ✓ |
| Revert to "in_progress" | Simple revert, less clear | |
| Revert with rejection flag | Back to in_progress but with rejectedAt/rejectionReason fields | |

**User's choice:** New "rejected" status

### Q5: What does the GC provide when rejecting?

| Option | Description | Selected |
|--------|-------------|----------|
| Free-text comment only | Flexible, no constraints | |
| Structured reason + comment | Pick reason then optional comment | |
| Structured reason + comment + annotated photo | Full evidence trail | ✓ |

**User's choice:** Structured reason + comment + annotated photo

---

## Punch List Design

### Q6: Is a punch list item a task or separate entity?

| Option | Description | Selected |
|--------|-------------|----------|
| Regular task with "punch" flag | Reuses task infrastructure, isPunchList field | |
| Separate punch_list_items table | New entity, clean domain boundary | ✓ |
| Regular task with "punch" priority | Convention-based, no new fields | |

**User's choice:** Separate entity

### Q7: How do punch items appear in contractor's view?

| Option | Description | Selected |
|--------|-------------|----------|
| Separate "Punch List" section | Distinct collapsible section at top of My Tasks | |
| Mixed with regular tasks | Inline with "Punch" badge, sorted by priority | ✓ |
| Separate tab | New tab alongside task view | |

**User's choice:** Mixed with badge

---

## Site Walk Flagging

### Q8: How does a GC start flagging an issue?

| Option | Description | Selected |
|--------|-------------|----------|
| Camera-first | Camera opens immediately, then annotate, then form | |
| Form-first | Description form first, photo optional | |
| Camera-first with form fallback | Default opens camera, "Skip photo" goes to form | ✓ |

**User's choice:** Camera-first with skip option

### Q9: Where do site walk flags live?

| Option | Description | Selected |
|--------|-------------|----------|
| Project-scoped | Flag belongs to project, optional scope assignment | |
| Always trade-scope-scoped | Every flag must have a trade scope | |
| Project-scoped, auto-converts to punch item | Observation → punch item when scope assigned | ✓ |

**User's choice:** Project-scoped observations that promote to punch items

---

## Claude's Discretion

- Inspection checklist storage schema
- Predefined rejection reason list
- Universal default checklist items
- Site walk flag form fields
- Punch list item status lifecycle
- Flag-to-punch-item conversion linking

## Deferred Ideas

None
