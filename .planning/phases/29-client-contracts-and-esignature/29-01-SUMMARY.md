---
phase: 29-client-contracts-and-esignature
plan: "01"
subsystem: backend
tags: [contracts, quotes, pdf, weasyprint, rbac, migration, california]
dependency_graph:
  requires:
    - backend/app/features/quotes/ (Quote lifecycle, expiry_date, approve-time expiry check)
    - backend/app/features/pdf/service.py (WeasyPrint + Jinja2)
    - backend/app/features/companies/models.py (Company)
  provides:
    - Company.license_number (CSLB)
    - contract_templates + contracts tables (migration 0029, RLS, CA-structured default seed)
    - ContractService.generate_from_quote (merge -> render -> persist unsigned PDF)
    - Quote "valid today only" (send defaults expiry to today) + client name on quote PDF
    - contracts.manage permission key + POST /contracts, GET/PUT /contract-template
  affects:
    - 29-02 (e-sign) consumes Contract + unsigned_pdf_url + provider fields
    - 29-03 (web admin) consumes /contracts + /contract-template
tech_stack:
  added: []
  patterns:
    - "Terms frozen into terms_snapshot at generation (template edits never mutate a sent contract)"
    - "Merge fields ({{...}}) resolved into the snapshot; company-editable template seeded lazily"
    - "Contract PDF signature text-tags ([sig|req|signer1]) for the e-sign provider (29-02)"
    - "db.refresh after onupdate flush so server defaults serialize (avoids MissingGreenlet)"
key_files:
  created:
    - backend/migrations/versions/0029_contracts_and_license.py
    - backend/app/features/contracts/{__init__,models,repository,schemas,service,router,templates_default}.py
    - backend/app/features/pdf/templates/contract.html
    - backend/tests/test_quote_validity.py
    - backend/tests/test_contracts_generation.py
  modified:
    - backend/app/features/companies/models.py (license_number)
    - backend/app/features/quotes/service.py (send_quote defaults expiry to today)
    - backend/app/features/quotes/router.py (resolve client -> quote PDF)
    - backend/app/features/pdf/service.py (client wired in, validity statement, generate_contract_pdf)
    - backend/app/features/pdf/templates/quote.html (validity statement block)
    - backend/app/core/permissions.py (contracts.manage key, 48 total)
    - backend/app/main.py (contracts + contract-template routers)
    - backend/tests/conftest.py (truncate contracts + contract_templates)
key_decisions:
  - "Contracts gated on a NEW contracts.manage permission (owner/admin/project_manager) — NOT quotes.manage (removed in 27-04's CRUD split) nor company.settings.manage (owner-only, admin lacks it)."
  - "Default terms are CA-structured PLACEHOLDERS marked [ATTORNEY REVIEW REQUIRED] — not legal advice; company edits via the template editor (29-03)."
  - "Valid today only: send_quote defaults expiry_date=today; reuses approve_quote's existing past-expiry check."
  - "Contract PDF is persisted (uploads/contracts/{company}/{id}/unsigned.pdf via /files) — first persisted generated document."
patterns_established:
  - "Contract generation freezes terms; e-sign anchors embedded for 29-02."
requirements-completed: [CONTRACT-01, CONTRACT-02, QUOTE-VALIDITY-01]
duration: ~50min
completed: 2026-07-24
---

# Phase 29-01: Contracts Data + Documents Summary

**Approved quotes can be turned into a persisted, California-structured contract PDF (with
e-sign signature anchors and frozen terms), and sent quotes now state "valid today only" with
the real client name on the PDF.**

## Accomplishments
- **Migration 0029**: `Company.license_number`; `contract_templates` (RLS, CA default seeded per
  company); `contracts` (RLS, full e-sign lifecycle fields). Round-trips up/down/up.
- **Default terms template** (`templates_default.py`): CA home-improvement sections (license,
  3-day right-to-cancel, down-payment cap, mechanics'-lien, change orders, arbitration) as
  `[ATTORNEY REVIEW REQUIRED]` placeholders with merge fields.
- **Quote validity**: `send_quote` defaults `expiry_date` to today; `quote.html` shows the
  statement; the quote PDF now shows the real client (resolved quote→job→client).
- **ContractService.generate_from_quote**: requires an approved quote (409 otherwise), merges
  terms into a frozen `terms_snapshot`, renders `contract.html` via WeasyPrint, and persists the
  unsigned PDF. Terms/template editable via `GET/PUT /contract-template`.
- **New `contracts.manage` permission** (owner/admin/project_manager) gates all contract routes.

## Verification
- `alembic upgrade/downgrade/upgrade` clean.
- **6 new tests pass** (send-expiry-today, validity statement, generate-from-approved,
  409-on-non-approved, default-template-seeded); PDF rendering stubbed (no libpango in this env).
- Regression: **66 passed, 1 skipped** (quotes lifecycle + RBAC + contracts). `ruff` clean.

## Notes for downstream
- 29-02 uses `Contract.unsigned_pdf_url` + `provider*` fields; the PDF already carries
  `[sig|req|signer1]` / `[date|req|signer1]` anchors for Dropbox Sign.
- The permission catalog grew 47 → **48** (`contracts.manage`); the web editor renders from the
  API catalog so no client mirror change was needed.
- **WeasyPrint needs libpango** — not installed in this dev env; install it for real PDF output
  (tests stub the HTML→PDF step).
