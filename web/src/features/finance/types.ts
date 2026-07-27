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

export interface CostBreakdown {
  categories: CategoryTotal[];
  labor: LaborCostSummary | null;
  laborTrackedAtJobLevel: boolean;
  grandTotal: string;
  margin: MarginSummary | null;
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
