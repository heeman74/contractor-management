/**
 * Finance feature types (cost capture). Amounts stay as strings end-to-end
 * (Decimal-as-string, mirroring quotes/invoices) — never coerced to number
 * except transiently for display/validation.
 */

export interface CostCategory {
  id: string;
  name: string;
  isSystem: boolean;
}

export interface CostReceipt {
  id: string;
  costEntryId: string;
  remoteUrl: string;
  caption?: string | null;
  createdAt: string;
}

export interface CostEntry {
  id: string;
  jobId: string | null;
  tradeScopeId: string | null;
  categoryId: string;
  categoryName?: string | null;
  amount: string;
  incurredDate: string;
  vendor?: string | null;
  note?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CategoryTotal {
  categoryId: string;
  categoryName: string;
  total: string;
}

/** Derived labor cost. unratedSeconds is the D-05 honesty contract — hours with no
 *  effective rate are reported, never silently valued at $0. basis is always
 *  "unburdened" in v4.0 (wage only, no payroll tax/insurance/overhead). */
export interface LaborCostSummary {
  total: string;
  ratedSeconds: number;
  unratedSeconds: number;
  basis: string;
}

/** Revenue basis for a margin figure. "mixed" occurs only on the project rollup. */
export type RevenueBasis = "invoiced" | "quoted" | "mixed" | "none";

/** Backend-computed margin. Money and percent stay strings (Decimal-as-string, displayed
 *  verbatim, never re-summed). null means honest absence, never zero: revenue is null when
 *  no invoice and no approved quote exists; marginPercent is null when revenue is absent
 *  or zero. */
export interface MarginSummary {
  revenue: string | null;
  revenueBasis: RevenueBasis;
  margin: string | null;
  marginPercent: string | null;
  incomplete: boolean;
  incompleteReasons: string[];
}

/** Backend-computed budget vs actual. Money stays a string end-to-end
 *  (Decimal-as-string, displayed verbatim); `remaining` goes negative when
 *  spend exceeds the budget. */
export interface BudgetVsActual {
  budgetId: string;
  total: string;
  spent: string;
  remaining: string;
  /** One decimal from the backend, e.g. "82.0" — never re-derived client-side. */
  percentUsed: string;
}

export interface CostBreakdown {
  categories: CategoryTotal[];
  labor: LaborCostSummary | null;
  laborTrackedAtJobLevel: boolean;
  grandTotal: string;
  margin: MarginSummary | null;
  /** null = no budget set or an older backend without the budget block. */
  budget: BudgetVsActual | null;
}

export interface ProjectCostRollup {
  projectId: string;
  /** Cost-entry sum only — unchanged pre-Phase-32 meaning. */
  total: string;
  entries: CostEntry[];
  categories: CategoryTotal[];
  labor: LaborCostSummary | null;
  /** All-in total including derived labor; null when the backend omits it. */
  grandTotal: string | null;
  margin: MarginSummary | null;
  /** null = no budget set or an older backend without the budget block. */
  budget: BudgetVsActual | null;
}

/** Exactly one of jobId / tradeScopeId must be set (anchor XOR, enforced backend-side). */
export interface CostEntryInput {
  jobId?: string;
  tradeScopeId?: string;
  categoryId: string;
  amount: string;
  incurredDate: string;
  vendor?: string;
  note?: string;
}

/** Anchor (jobId/tradeScopeId) is immutable after creation — not patchable. */
export interface CostEntryPatch {
  categoryId?: string;
  amount?: string;
  incurredDate?: string;
  vendor?: string;
  note?: string;
}

/** One append-only effective-dated cost rate row. Amounts stay strings end-to-end. */
export interface LaborRate {
  id: string;
  userId: string;
  hourlyCost: string;
  effectiveFrom: string; // ISO date, "2026-05-01"
  createdAt: string;
  updatedAt: string;
}

/** Payload for appending a rate. Past, today, and future effectiveFrom are all valid. */
export interface LaborRateInput {
  userId: string;
  hourlyCost: string;
  effectiveFrom: string;
}

// --- Financial dashboard (company rollup, project drill-down, margin trend) ---
//
// Every money and percent value below stays a string, exactly as the backend
// serialized its Decimal. parseFloat is permitted only to build the numeric
// value a chart needs for geometry (bar length, axis domain) — never for a
// rendered figure, which always formats from the original string. A null value
// is honest absence and stays null; coercing it to 0 fabricates a break-even.

/** The one permission key guarding every financial surface (Phase 30 RBAC). */
export const FINANCE_VIEW_PERMISSION = "finance.view";

/**
 * Statuses that mean a project is no longer actively running. Such projects are
 * de-emphasized in the dashboard (grouped, dimmed) but never excluded from a
 * total — declared here so no component hardcodes the set.
 */
export const INACTIVE_PROJECT_STATUSES: readonly string[] = [
  "draft",
  "complete",
  "archived",
];

/** Why a project appears in the Needs Attention list. */
export type AttentionTier = "overrun" | "warning" | "incomplete";

/** How far back the margin trend reaches. Slices buckets, never records. */
export type TrendWindow = "3m" | "6m" | "12m" | "all";

export const TREND_WINDOWS: readonly TrendWindow[] = ["3m", "6m", "12m", "all"];

export const DEFAULT_TREND_WINDOW: TrendWindow = "12m";

/** Company-wide totals across every project, including inactive ones. */
export interface PortfolioTotals {
  cost: string;
  /** Revenue from approved-but-not-invoiced quotes; null when there is none. */
  quotedRevenue: string | null;
  incompleteProjectCount: number;
  margin: MarginSummary;
}

/** One project's row in the company rollup. */
export interface ProjectFinancialsRow {
  projectId: string;
  name: string;
  status: string;
  cost: string;
  margin: MarginSummary;
  /** null = no budget set on this project. */
  budget: BudgetVsActual | null;
}

/** One entry in the Needs Attention list. The incomplete tier carries no percent. */
export interface AttentionRow {
  projectId: string;
  projectName: string;
  projectStatus: string;
  tier: AttentionTier;
  /** Names the offending budget: the project, or "{project} — {trade} scope". */
  anchorLabel: string;
  spent: string | null;
  budgetTotal: string | null;
  percentUsed: string | null;
}

export interface CompanyFinancials {
  portfolio: PortfolioTotals;
  projects: ProjectFinancialsRow[];
  attention: AttentionRow[];
}

/** One trade scope's spend against its own budget. Excludes job-level labor. */
export interface ScopeBudgetRow {
  tradeScopeId: string;
  tradeName: string;
  spent: string;
  budget: BudgetVsActual | null;
}

export interface ProjectFinancials {
  projectId: string;
  name: string;
  status: string;
  breakdown: CostBreakdown;
  scopes: ScopeBudgetRow[];
}

/** One month of the trend. month is "YYYY-MM" — never parsed with Date(). */
export interface TrendBucket {
  month: string;
  cost: string;
  margin: MarginSummary;
}

export interface MarginTrend {
  projectId: string;
  window: TrendWindow;
  buckets: TrendBucket[];
}
