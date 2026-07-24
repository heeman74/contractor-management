---
phase: 29-client-contracts-and-esignature
plan: "03"
subsystem: web
tags: [contracts, esignature, nextjs, react-query, rbac, ui]
dependency_graph:
  requires:
    - 29-01/29-02 API (contracts, contract-template, companies license_number)
    - web usePermissions (contracts.manage), api-client, react-query
  provides:
    - web/src/lib/api/contracts.ts (contracts + company hooks)
    - Company settings (license # + terms editor with attorney-review banner)
    - Quote -> Create/Send contract actions + Contracts list/detail + signed download
    - permission-gated Contracts nav
key_files:
  created:
    - web/src/lib/api/contracts.ts
    - web/src/app/(dashboard)/settings/company/{page.tsx,_components/company-settings-form.tsx,_components/contract-terms-editor.tsx}
    - web/src/app/(dashboard)/quotes/[id]/_components/quote-contract-card.tsx
    - web/src/app/(dashboard)/contracts/{page.tsx,[id]/page.tsx}
  modified:
    - web/src/types/api.ts (Company, Contract, ContractTemplate, Send/PublicContractView)
    - web/src/components/shared/status-badge.tsx (signed/voided)
    - web/src/components/layout/sidebar.tsx (Contracts nav, contracts.manage)
    - web/src/app/(dashboard)/quotes/[id]/page.tsx (QuoteContractCard when approved)
key_decisions:
  - "company_id comes from the verified JWT via getServerUser() (Redux auth has no company_id); settings page is a Server Component."
  - "Reused the shared StatusBadge (added signed/voided) instead of a new badge."
  - "Terms editor shows a persistent attorney-review banner + merge-field reference."
requirements-completed: [CONTRACT-UI-01, CONTRACT-UI-02]
completed: 2026-07-24
---

# Phase 29-03: Web Admin Contracts UI Summary

**Owner/admin (contracts.manage) can set the CSLB license #, edit the attorney-reviewed terms
template, and turn an approved quote into a contract they send for signature — with a Contracts
list/detail and signed-PDF download.**

## Accomplishments
- `lib/api/contracts.ts` react-query hooks (contracts CRUD + send, template get/put, company get/patch).
- **Settings → Company**: license_number form + `ContractTermsEditor` (persistent amber
  "attorney review required" banner, merge-field reference, Save).
- **Quote detail → `QuoteContractCard`** (shown when quote is approved): Create contract →
  Send for signature → status chip → Download signed PDF.
- **Contracts list + detail** (lifecycle stepper, signer details, signed download); permission-gated
  Contracts nav item.

## Verification
- `npx tsc --noEmit` clean; `npx eslint --max-warnings 0` clean on all 14 changed files.
