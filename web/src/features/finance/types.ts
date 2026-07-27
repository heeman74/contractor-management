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

export interface ProjectCostRollup {
  projectId: string;
  total: string;
  entries: CostEntry[];
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
