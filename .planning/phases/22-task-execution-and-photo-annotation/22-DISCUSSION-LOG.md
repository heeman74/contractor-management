# Phase 22: Task Execution and Photo Annotation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-24
**Phase:** 22-task-execution-and-photo-annotation
**Areas discussed:** Daily task view, Photo annotation flow, Task detail & attachments, GC progress monitoring

---

## Daily Task View

| Option | Description | Selected |
|--------|-------------|----------|
| Checklist cards | Card per task with checkbox, title, priority badge, time estimate, photo-required indicator. Grouped by trade scope. | ✓ |
| Simple checklist | Minimal list with checkbox + title only. Flat list sorted by priority. | |
| Timeline view | Vertical timeline with time slots. Tasks at estimated start times. | |

**User's choice:** Checklist cards
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Tap checkbox | Tap to mark complete. Photo-required gate. Sync immediately. | ✓ |
| Swipe to complete | Swipe right to complete, left to block. | |
| Long-press menu | Long-press for status options (Not Started, In Progress, Complete, Blocked). | |

**User's choice:** Tap checkbox
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Block completion until photo added | Camera icon instead of checkmark when photo_required=true. | ✓ |
| Soft reminder | Allow completion but show warning. | |
| Auto-open camera | Automatically opens camera on complete tap. | |

**User's choice:** Block completion until photo added
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| All scopes, grouped | Single "My Tasks" screen, grouped by trade scope with collapsible headers. | ✓ |
| Per-scope navigation | Pick scope first, then see tasks. | |
| Both views | My Tasks + per-scope navigation. | |

**User's choice:** All scopes, grouped
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| All incomplete tasks | Show all incomplete, ordered by priority then due date. Overdue highlighted. | ✓ |
| Today + overdue only | Filter to today or overdue. Requires accurate due dates. | |
| Smart grouping | Three sections: Overdue, Today, Upcoming. | |

**User's choice:** All incomplete tasks
**Notes:** None

---

## Photo Annotation Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Overlay on photo | Full-screen viewer → Annotate mode → tools overlay photo. Pinch-to-zoom. Non-destructive. | ✓ |
| Separate drawing layer | Photo as background, transparent overlay canvas. | |
| Capture then draw | Take photo, auto-open DrawingPadScreen with photo background. | |

**User's choice:** Overlay on photo
**Notes:** None

---

### Tools (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Arrow | Point to specific areas. Already implemented. | ✓ |
| Circle/highlight | Circle problem areas. Already implemented. | ✓ |
| Text labels | Add text callouts. Partially implemented. | ✓ |
| Measurement ruler | Draw line with dimension text. NEW feature. | ✓ |

**User's choice:** All four tools selected
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| JSON annotation layer | Store as JSON, render on-the-fly. Non-destructive, toggleable, editable. | ✓ |
| Flattened PNG export | Merge annotations onto photo. Simpler but destructive. | |
| Both formats | JSON for editability + flattened PNG for sharing. | |

**User's choice:** JSON annotation layer
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Web can annotate too | Canvas-based annotation on web. Same tool set. | ✓ |
| View-only on web | Web shows annotations but only mobile creates. | |
| Basic web annotation | Web gets arrow + text only. | |

**User's choice:** Web can annotate too
**Notes:** None

---

## Task Detail & Attachments

| Option | Description | Selected |
|--------|-------------|----------|
| Scrollable detail page | Full screen with sections: Header, Details, Notes, Photos, Attachments. Bottom bar. | ✓ |
| Bottom sheet detail | DraggableScrollableSheet from list. Limited vertical space. | |
| Tabbed detail | Full page with tabs: Overview, Notes, Photos, Files. | |

**User's choice:** Scrollable detail page
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inline text input | TextField + "+" button. Timestamped, newest first. Immutable after save. | ✓ |
| Bottom sheet form | Tap "Add Note" opens bottom sheet with text + optional photo. | |
| Voice-to-text notes | Mic icon for voice input. Auto-transcribed. | |

**User's choice:** Inline text input
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Grid gallery + FAB | 3-column thumbnails. Annotation badge. Full-screen viewer. "Add Photo" button. | ✓ |
| Horizontal scroll strip | Horizontal row. More compact. | |
| Full-width cards | Each photo as full-width card with caption. | |

**User's choice:** Grid gallery + FAB
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| 10 photos + 5 PDFs | Practical limits matching existing pattern. | ✓ |
| No limits | Unlimited. Simple but storage risk. | |
| 5 photos + 3 PDFs | Tighter limits. May frustrate on complex tasks. | |

**User's choice:** 10 photos + 5 PDFs
**Notes:** None

---

## GC Progress Monitoring

| Option | Description | Selected |
|--------|-------------|----------|
| Project detail with trade cards | Trade scope cards with progress bar, task count, last activity. Tap into scope. | ✓ |
| Dashboard summary | Dedicated progress dashboard with charts and activity feed. | |
| Notification-driven | Push notifications on completions. Basic counts in project detail. | |

**User's choice:** Project detail with trade cards
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Thumbnails in task list | Small photo thumbnails (2-3 max) on each task card in GC view. | ✓ |
| Detail only | Photos visible only in task detail. | |
| Photo timeline | Separate Photos tab with chronological feed. | |

**User's choice:** Thumbnails in task list
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Batch digest | Group completions into periodic digests. Avoids spam. | ✓ |
| Per-task notification | Push for every task completion. | |
| Milestone only | Notify at 50%, 100%, or when behind. | |
| You decide | Claude's discretion. | |

**User's choice:** Batch digest
**Notes:** None

---

## Claude's Discretion

- Photo compression settings for task attachments
- PDF viewer implementation
- Measurement ruler UX details
- Offline attachment sync behavior
- Annotation JSON schema structure
- Web annotation canvas library
- Task note model design
- Progress bar animation and thresholds

## Deferred Ideas

None — discussion stayed within phase scope
