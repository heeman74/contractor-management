---
phase: 17
slug: crm-clients-and-contractors
status: approved
reviewed_at: 2026-03-17
shadcn_initialized: true
preset: base-nova
created: 2026-03-17
---

# Phase 17 — UI Design Contract

> Visual and interaction contract for CRM Clients & Contractors phase.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | shadcn/ui (style: base-nova) |
| Preset | base-nova |
| Component library | shadcn/ui (Card, Badge, Button, Input, Table, Tabs, Dialog, Sheet, Skeleton, Popover, Calendar, Select, Separator, Avatar, Breadcrumb, DropdownMenu, Sonner) |
| Icon library | lucide-react (already installed) |
| Font | Geist Sans (--font-geist-sans via next/font/google) |

> No new packages required. All primitives are already installed. This phase is composition only.

---

## Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon gap within a badge chip; table cell vertical padding |
| sm | 8px | Gap between chips in a tag cluster; icon + label gap in nav links |
| md | 16px | Card internal padding (horizontal); form field gap; input → button gap in search bar |
| lg | 24px | Section-to-section gap within a page column; card-to-card gap in two-column layout |
| xl | 32px | Page top padding; gap between the weekly grid and the overrides section |
| 2xl | 48px | Vertical space between breadcrumb row and first content card |
| 3xl | 64px | Minimum empty-state illustration area height |

Exceptions:
- **Schedule editor grid cells**: 28px tall × 40px wide per hour-cell (does not map to scale; derived from legibility constraint). Default: `h-7 w-10` Tailwind classes.
- **Two-column detail layout**: `gap-8` (32px) between main and sidebar columns — maps to `xl` token.

---

## Typography

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 14px (text-sm) | 400 | 1.5 (leading-relaxed) |
| Label | 12px (text-xs) | 500 | 1.4 (leading-snug) — used for table column headers, badge text, card meta |
| Heading | 18px (text-lg) | 600 | 1.3 (leading-tight) — used for card titles, section headers, page h1 |
| Display | 24px (text-2xl) | 700 | 1.2 (leading-tight) — used for page-level title in topbar |

> All sizes follow Tailwind's default scale (1rem = 16px base). Font is Geist Sans across all roles.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `oklch(1 0 0)` — white (#ffffff) | Page background, card backgrounds, table row backgrounds |
| Secondary (30%) | `oklch(0.97 0 0)` — near-white gray (#f7f7f7) and sidebar `gray-900` (#111827) | Sidebar bg, muted text areas, table header row bg, skeleton fills, input bg |
| Accent (10%) | `indigo-600` (#4f46e5) | Primary action buttons, active sidebar link, schedule grid filled cells, cross-page link hover state, NProgress bar |
| Destructive | `oklch(0.577 0.245 27.325)` — red (#dc2626 equivalent) | Delete confirmation dialog actions, "Remove override" button, destructive DropdownMenuItem |

**Availability badge color assignments (extending StatusBadge colorMap):**

| Status | Classes | Visible meaning |
|--------|---------|-----------------|
| `available` | `bg-green-100 text-green-800` | Contractor has ≥ 4 hours free today |
| `partially_booked` | `bg-yellow-100 text-yellow-800` | Contractor has some free time (< 4 hours) today |
| `fully_booked` | `bg-red-100 text-red-800` | Contractor has no free windows today or no schedule configured |

**Trade type badge (default):** `bg-gray-100 text-gray-700` — neutral; no semantic meaning.

**Tag chip color:** `bg-indigo-50 text-indigo-700` — visually distinct from availability badges and trade type badges; consistent with the accent palette.

**Schedule grid cell states:**

| State | Classes |
|-------|---------|
| Empty (unpainted) | `bg-gray-100 hover:bg-indigo-100 border border-gray-200` |
| Filled (working hour) | `bg-indigo-500 hover:bg-indigo-600 border border-indigo-600` |
| Currently dragging | `bg-indigo-300` — provides in-progress visual feedback |

**Default badge (no match in colorMap):** `bg-gray-100 text-gray-700` — already the StatusBadge fallback.

Accent reserved for:
1. Primary CTA buttons (`Button` default variant) — "Edit Schedule", "Save Override", "Add Override"
2. Active sidebar navigation item — `bg-indigo-600 text-white`
3. Filled cells in the weekly schedule grid
4. Cross-page link hover/active underline color
5. NProgress route transition bar (already set to `#4f46e5` in layout.tsx)
6. Tag chips — `bg-indigo-50 text-indigo-700`
7. ContractorHub brand name in sidebar header — `text-indigo-300`

---

## Copywriting Contract

### Client Pages

| Element | Copy |
|---------|------|
| Page title — client list | "Clients" |
| Search placeholder | "Search by name or email..." |
| Column: job count | "Jobs" |
| Column: preferred contractor | "Preferred Contractor" |
| Column: tags | "Tags" |
| Empty state heading (no clients) | "No clients yet" |
| Empty state body (no clients) | "Clients will appear here once they submit a job request or are added to the system." |
| Empty state heading (search no results) | "No clients found" |
| Empty state body (search no results) | "Try a different name or email address." |
| Error state (list fetch failure) | "Failed to load clients. Please refresh the page." |
| Page title — client detail | "{First} {Last}" |
| Section heading — job history | "Job History" |
| Section heading — saved properties | "Saved Properties" |
| Property badge: default address | "Default" |
| Section heading — admin notes | "Admin Notes" |
| Empty state — no jobs for client | "No jobs found for this client." |
| Empty state — no properties | "No saved properties." |
| Empty state — no admin notes | "No notes have been added for this client." |
| Error state (client detail fetch) | "Failed to load client profile. Please refresh the page." |

### Contractor Pages

| Element | Copy |
|---------|------|
| Page title — contractor list | "Contractors" |
| Search placeholder | "Search by name or email..." |
| Column: trade type | "Trade" |
| Column: availability | "Availability" |
| Column: active jobs | "Active Jobs" |
| Empty state heading (no contractors) | "No contractors yet" |
| Empty state body (no contractors) | "Contractors will appear here once they are assigned the contractor role." |
| Empty state heading (search no results) | "No contractors found" |
| Empty state body (search no results) | "Try a different name or email address." |
| Error state (list fetch failure) | "Failed to load contractors. Please refresh the page." |
| Page title — contractor profile | "{First} {Last}" |
| Section heading — weekly schedule (profile) | "Weekly Schedule" |
| Button — open schedule editor | "Edit Schedule" |
| Section heading — assigned jobs | "Assigned Jobs" |
| Empty state — no jobs for contractor | "No jobs currently assigned to this contractor." |
| Empty state — no weekly schedule configured | "No working hours configured. Click Edit Schedule to set availability." |
| Error state (profile fetch) | "Failed to load contractor profile. Please refresh the page." |

### Schedule Editor

| Element | Copy |
|---------|------|
| Page title | "Edit Schedule" |
| Breadcrumb | "Contractors / {Name} / Schedule" |
| Section heading — weekly grid | "Weekly Working Hours" |
| Grid instruction text | "Click and drag to mark working hours. Changes save automatically per day." |
| Per-day save success toast | "Schedule saved for {DayName}." |
| Per-day save error toast | "Failed to save schedule for {DayName}. Please try again." |
| Section heading — date overrides | "Date Overrides" |
| Calendar instruction text | "Select a date to set a custom override. Highlighted dates have existing overrides." |
| Toggle label — mark unavailable | "Unavailable all day" |
| Toggle label — custom hours | "Custom hours" |
| Button — save override | "Save Override" |
| Button — remove override | "Remove Override" |
| Save override success toast | "Override saved for {Date}." |
| Save override error toast | "Failed to save override. Please try again." |
| Remove override confirmation title | "Remove override?" |
| Remove override confirmation body | "This will delete the date override for {Date}. The contractor's regular weekly schedule will apply." |
| Remove override confirm button | "Remove" |
| Remove override cancel button | "Cancel" |
| Empty state — no overrides | "No date overrides set. Select a date above to add one." |
| Error state (schedule fetch) | "Failed to load schedule. Please refresh the page." |

### Cross-Page Link Copy

| Element | Copy |
|---------|------|
| Client name link (in job detail sidebar) | Display `job.client_name`; href `/clients/{job.client_id}` |
| Contractor name link (in job detail sidebar) | Display `job.contractor_name`; href `/contractors/{job.contractor_id}` |
| Client name link (in quote/invoice detail sidebar) | Display client name; href `/clients/{client_id}` |
| Preferred contractor link (in client detail sidebar) | Display contractor name; href `/contractors/{preferred_contractor_id}` |
| Schedule calendar contractor lane header | Display contractor first name; href `/contractors/{contractor_id}` |

---

## Component Registry

### Already Installed (no `npx shadcn add` needed)

| Component | Source File | Used In |
|-----------|------------|---------|
| Card, CardContent, CardHeader, CardTitle | `@/components/ui/card` | All detail page sections; sidebar contact card |
| Badge | `@/components/ui/badge` | Trade type; availability (via StatusBadge extension) |
| Button | `@/components/ui/button` | "Edit Schedule", "Save Override", "Remove Override", pagination |
| Input | `@/components/ui/input` | Search bar on client list and contractor list |
| Table, TableBody, TableCell, TableHead, TableHeader, TableRow | `@/components/ui/table` | Client list, contractor list, job history tables |
| Skeleton | `@/components/ui/skeleton` | Loading states on all list and detail pages |
| Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter | `@/components/ui/dialog` | Remove override confirmation dialog |
| Popover | `@/components/ui/popover` | Schedule editor date picker anchor |
| Calendar | `@/components/ui/calendar` | Date override date picker |
| Select | `@/components/ui/select` | Time pickers in custom-hours override flow |
| Separator | `@/components/ui/separator` | Between sections in sidebar cards |
| Avatar, AvatarFallback | `@/components/ui/avatar` | Contractor/client initials avatar in profile header |
| Breadcrumb | `@/components/ui/breadcrumb` | Schedule editor page breadcrumb |
| DropdownMenu | `@/components/ui/dropdown-menu` | "..." action menu on list rows (future-proofing) |
| Sonner (toast) | `@/components/ui/sonner` | Per-day save toasts, override save/error toasts |

### Shared Components (already built, extend or reuse)

| Component | File | Phase 17 Extension |
|-----------|------|--------------------|
| StatusBadge | `@/components/shared/status-badge.tsx` | Add `available`, `partially_booked`, `fully_booked` to colorMap |
| KpiCard | `@/components/shared/kpi-card.tsx` | Reuse for contractor profile quick stats (active jobs, hours this week) |

### New Components to Build in Phase 17

| Component | File (proposed) | Purpose |
|-----------|-----------------|---------|
| ScheduleGrid | `@/components/crm/schedule-grid.tsx` | 7-column × 15-row CSS grid with drag-to-paint pointer events |
| TagChip | inline in client detail | `bg-indigo-50 text-indigo-700 text-xs rounded-full px-2 py-0.5` span — no new file needed |
| AvailabilityBadge | reuse StatusBadge | Not a new component; use `<StatusBadge status="available" size="sm" />` after colorMap extension |

---

## Registry Safety Assessment

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn/ui (base-nova) | Card, Badge, Button, Input, Table, Skeleton, Dialog, Popover, Calendar, Select, Separator, Avatar, Breadcrumb, DropdownMenu, Sonner | SAFE — all already installed; no `npx shadcn add` commands required this phase |
| lucide-react | Search, ArrowUpDown, ArrowUp, ArrowDown, ChevronDown, ChevronRight, ChevronLeft, Edit2 (schedule edit), CalendarIcon (override section), Clock | SAFE — library already installed; tree-shaken at build time |
| react-day-picker | Consumed via shadcn Calendar component | SAFE — already a peer dependency; no direct import needed |
| date-fns | Direct use in schedule editor (date formatting, 90-day range calculation) | SAFE — already installed as peer dependency |

**No new npm packages are required for this phase.** All UI primitives and utilities are present.

---

## Page Layout Contracts

### Client List — `/clients`
- Full-width page with `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8`
- Topbar: page title "Clients", no action buttons
- Search bar: `Input` with `Search` icon, full-width on mobile, `max-w-sm` on desktop, debounced 300ms
- Table columns: Name | Email | Phone | Tags | Preferred Contractor | Jobs (right-align, numeric)
- Sortable columns: Name, Jobs — sort icon via `ArrowUpDown` / `ArrowUp` / `ArrowDown`
- Pagination: Previous / Next buttons, "Showing X–Y of Z clients" label — reuse jobs/page.tsx pattern
- Row click: `router.push("/clients/${client.id}")`
- Skeleton: 10 `Skeleton` rows of height 40px while loading

### Client Detail — `/clients/[id]`
- Two-column grid: `grid-cols-1 lg:grid-cols-[1fr_360px] gap-8`
- Main column (65%): Job History card → Saved Properties card
- Sidebar (35%): Contact card → Tags card → Average Rating card → Referral Source card → Preferred Contractor card → Billing Address card
- All content read-only; no edit controls
- Breadcrumb: Dashboard / Clients / {Name}

### Contractor List — `/contractors`
- Same layout pattern as client list
- Table columns: Name | Email | Phone | Trade | Availability | Active Jobs (right-align)
- Availability column: `StatusBadge` with `available` / `partially_booked` / `fully_booked`
- Batch availability fetch: single `POST /api/v1/scheduling/availability` after contractors load

### Contractor Profile — `/contractors/[id]`
- Two-column grid: `grid-cols-1 lg:grid-cols-[1fr_360px] gap-8`
- Main column: Weekly Schedule Summary card (read-only mini-grid + "Edit Schedule" button) → Assigned Jobs card
- Sidebar: Contact card → Trade badge → Quick Stats (KpiCard: active jobs, hours this week) → Average Rating card
- Breadcrumb: Dashboard / Contractors / {Name}

### Schedule Editor — `/contractors/[id]/schedule`
- Single-column layout, `max-w-5xl`
- Breadcrumb: Dashboard / Contractors / {Name} / Schedule
- Section 1: Weekly grid card with drag-to-paint (Mon–Sun columns, 6am–8pm rows = 15 rows)
- Section 2: Date overrides card with shadcn Calendar + toggle + time pickers

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
