# Requirements: ContractorHub

**Defined:** 2026-07-24
**Core Value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.

## v4.0 Requirements

Requirements for the Financial Intelligence milestone. Each maps to roadmap phases.

### Cost Capture

- [x] **COST-01**: Owner/PM can record a materials cost entry (amount, category, date, vendor, note) against a job or trade scope
- [x] **COST-02**: Owner/PM can record subcontractor and other cost entries the same way
- [x] **COST-03**: Owner/PM can attach a receipt photo to a cost entry
- [x] **COST-04**: Owner/PM can set a worker's hourly cost rate with an effective date; historical rates are preserved
- [x] **COST-05**: System derives labor cost automatically from tracked time × the rate effective on the day worked
- [x] **COST-06**: Owner/PM can view itemized costs per job/trade scope/project with category totals (labor/materials/subcontractor/other)

### Budgeting

- [x] **BUDG-01**: Owner/PM can set a budget per project and per trade scope
- [x] **BUDG-02**: Owner/PM can view budgeted vs spent vs remaining at project and trade level
- [x] **BUDG-03**: Owner/PM receives alerts when spend crosses thresholds (80% warning / 100% overrun), via dashboard + FCM
- [x] **BUDG-04**: Approving a quote revision adjusts the linked budget by the revision delta

### Margin & Reporting

- [x] **MARG-01**: Owner/PM can see profit margin (revenue − actual costs) per job/trade scope
- [x] **MARG-02**: Owner/PM can see project-level margin rollup across trades
- [x] **MARG-03**: Margin views flag incomplete cost data (legacy jobs, missing rates) instead of showing misleading numbers
- [x] **MARG-04**: Owner/PM can see margin + budget-vs-actual charts on the web financial dashboard

### AI Financial Intelligence

- [x] **FINAI-01**: AI analyzes each active project's financial health on a nightly schedule, flagging margin erosion with suggested corrective actions
- [x] **FINAI-02**: Owner/PM receives finance-gated alerts for AI profitability findings
- [x] **FINAI-03**: Owner/PM can have AI pre-fill quote line items (labor hours, material quantities, unit prices) grounded in company cost history — assistive only, human reviews before sending
- [x] **FINAI-04**: AI quote suggestions show a confidence indicator based on how much historical data backs them
- [x] **FINAI-05**: Owner/PM can view quoted-vs-actual variance per completed project/trade; variance history feeds AI quote suggestions

### Financial Access Control

- [x] **FINSEC-01**: All financial endpoints are backend-gated by finance.* permissions, granted only to owner and project_manager by default
- [x] **FINSEC-02**: Companies can adjust finance.* grants via the existing Roles & Permissions matrix
- [x] **FINSEC-03**: The admin role does not inherit finance.* (explicit exclusion from the derived permission set)
- [x] **FINSEC-04**: Pre-existing surfaces (reports, dashboards, alerts, AI chat/checklists) are audited so no financial data leaks to non-finance roles

## Future Requirements

Deferred to a later milestone. Tracked but not in the current roadmap.

### Cost Capture

- **COST-F01**: Committed-cost tracking via purchase orders / subcontract agreements (obligated but unpaid)
- **COST-F02**: True labor burden rate (overhead/benefits allocation per worker)

### Accounting

- **ACCT-F01**: WIP / percentage-of-completion schedules (belongs with accounting integration)
- **ACCT-F02**: QuickBooks/Xero integration (carried from v1.0/v2.0)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| CSI MasterFormat cost coding | Small/mid contractors find 50-division coding "cumbersome and clunky"; simple labor/materials/sub/other categories win adoption |
| Enterprise procurement workflows (RFIs, submittals, PO approval chains) | The explicitly-cited reason small contractors reject Procore-tier software; cost entry stays a form, not a workflow engine |
| Double-entry / general-ledger accounting | Different product category; QuickBooks/Xero do this — this app is the operational job-costing layer |
| Autonomous AI quote sending | Pricing errors are real financial commitments; AI stays assistive (pre-fill for human review), consistent with existing AI draft patterns |
| Multi-entity / multi-currency financials | Single-company, single-currency audience; adds complexity to every calculation for zero near-term value |
| Inventory/stock management | Cost *capture* (what was spent) is in scope; warehouse-style stock tracking remains excluded per PROJECT.md |

## Traceability

Which phases cover which requirements. Filled during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| COST-01 | Phase 31: Actual Cost Capture | Complete |
| COST-02 | Phase 31: Actual Cost Capture | Complete |
| COST-03 | Phase 31: Actual Cost Capture | Complete |
| COST-04 | Phase 32: Labor Rates and Cost Rollup | Complete |
| COST-05 | Phase 32: Labor Rates and Cost Rollup | Complete |
| COST-06 | Phase 32: Labor Rates and Cost Rollup | Complete |
| BUDG-01 | Phase 34: Budgeting and Overrun Alerts | Complete |
| BUDG-02 | Phase 34: Budgeting and Overrun Alerts | Complete |
| BUDG-03 | Phase 34: Budgeting and Overrun Alerts | Complete |
| BUDG-04 | Phase 34: Budgeting and Overrun Alerts | Complete |
| MARG-01 | Phase 33: Profit Margin Tracking | Complete |
| MARG-02 | Phase 33: Profit Margin Tracking | Complete |
| MARG-03 | Phase 33: Profit Margin Tracking | Complete |
| MARG-04 | Phase 35: Web Financial Dashboard | Complete |
| FINAI-01 | Phase 36: AI Profitability Analysis | Complete |
| FINAI-02 | Phase 36: AI Profitability Analysis | Complete |
| FINAI-03 | Phase 37: AI Quote Planning | Complete |
| FINAI-04 | Phase 37: AI Quote Planning | Complete |
| FINAI-05 | Phase 37: AI Quote Planning | Complete |
| FINSEC-01 | Phase 30: Financial Schema Foundation and RBAC Audit | Complete |
| FINSEC-02 | Phase 30: Financial Schema Foundation and RBAC Audit | Complete |
| FINSEC-03 | Phase 30: Financial Schema Foundation and RBAC Audit | Complete |
| FINSEC-04 | Phase 30: Financial Schema Foundation and RBAC Audit | Complete |

**Coverage:** 23/23 v4.0 requirements mapped ✓

---
*Requirements defined: 2026-07-24*
*Previous milestone requirements: archived at milestones/v3.0-REQUIREMENTS.md*
*Roadmap created: 2026-07-24*
