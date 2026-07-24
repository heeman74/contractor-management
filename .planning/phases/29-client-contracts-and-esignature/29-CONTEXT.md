# Phase 29 — Client Contracts & E-Signature

## Goal

Turn an approved quote into a **California-compliant contract** that the client **e-signs**
through a third-party provider, with the **signed PDF stored back in ContractorHub**. Also
add a **"valid today only" validity statement** to sent quotes.

## ⚠️ Legal disclaimer (read first)

This phase builds the *system* for contracts, terms, and e-signature. The default contract
terms ship as **placeholder text structured around California statute** — they are **NOT legal
advice and MUST be reviewed and finalized by a licensed attorney before any real use.** No one
on this project is acting as the user's lawyer. The template is company-editable precisely so
the user's counsel can supply the binding language. Ship with a visible "attorney review
required" banner in the terms editor.

## Decisions (from discussion — see 29-DISCUSSION-LOG.md)

| Decision | Choice |
|---|---|
| E-signature | **Third-party provider** (hosted signing + audit trail; signed PDF returned via webhook) |
| Provider | **Dropbox Sign (HelloSign)** behind a `SignatureProvider` adapter (DocuSign swappable). *Confirm before 29-02.* |
| Signing channel | **Both** — mobile in-app (embedded) **and** emailed magic-link web page |
| Contract terms | **Company-editable template with California structure** as placeholders (attorney-reviewed) |
| Quote validity | **Valid today only** — `send_quote` defaults `expiry_date = today`; PDF states it |

### Why one embedded ceremony for both channels

Rather than mix the provider's own signer-emails with in-app signing, both channels drive the
**same embedded signing session**: we create an *embedded* signature request with the provider,
then surface its signing URL two ways — (a) the mobile client portal opens it in a WebView, and
(b) we email the client **our** magic-link to a public `/sign/[token]` web page that hosts the
same embedded ceremony. One provider request, one audit trail, two front doors.

## Current-state anchors (what we build on)

- **Quote lifecycle** (`backend/app/features/quotes/`): 7 statuses (draft→sent→viewed→approved|
  declined|expired|revised); `expiry_date`, `sent_at`, `viewed_at`, `approved_at` exist.
  `send_quote` (service.py:212) sets status/sent_at but **not** expiry. `approve_quote`
  (service.py:266) already expires past-`expiry_date` quotes → the "today only" rule reuses this.
- **PDF**: WeasyPrint + Jinja2, `backend/app/features/pdf/service.py`, templates
  `pdf/templates/quote.html` (+ `invoice.html`). Client name is currently hardcoded `None`
  (service.py:134-139) — must be wired in.
- **Files**: `/files` StaticFiles mount over `uploads/`; upload endpoints save under
  `uploads/attachments/…` and `uploads/images/…`. Generated PDFs today are **streamed, never
  persisted** — signed contracts introduce first persisted documents.
- **Signature tech** exists but only as freehand job-note drawing (web `DrawingCanvas`, mobile
  `drawing_pad`); **no signature semantics** — not reused here (provider handles the ceremony).
- **Company** (`companies/models.py`): has name/address/phone/business_number; **no
  `license_number`** (legally required on CA contracts). **Client** data lives on `User`
  (first/last name, email, phone, home_address); no ClientProfile.
- **No** contract/terms/e-sign/CSLB code anywhere. **No** public/tokenized route. Latest
  migration `0028_project_assignment_roles` → new migrations start at **0029**.

## Data model (new)

- **`Company.license_number`** (`str | None`) — CSLB contractor license #. (Migration 0029.)
- **`contract_templates`** (tenant-scoped, RLS): `id, company_id, name, body (TEXT, merge-field
  placeholders), is_default, created/updated`. Seeded with a CA-structured default (see below).
- **`contracts`** (tenant-scoped, RLS):
  - `id, company_id, quote_id (FK), job_id, client_user_id, template_id`
  - `status`: `draft | sent | viewed | signed | declined | voided`
  - `terms_snapshot (TEXT)` — merged terms frozen at generation (template edits never mutate a
    sent contract)
  - `validity_statement (TEXT)`
  - `unsigned_pdf_url`, `signed_pdf_url (nullable)`
  - `provider (str)`, `provider_request_id (str)`, `provider_metadata (JSONB)`
  - `signer_name`, `signer_email`
  - `sent_at, viewed_at, signed_at, declined_at (nullable timestamptz)`
  - standard `version/created_at/updated_at/deleted_at`
- **Storage**: unsigned + signed PDFs under `uploads/contracts/{company_id}/{contract_id}/…`,
  served via `/files`.

## Merge fields (template placeholders)

`{{company_name}} {{company_address}} {{company_license_number}} {{company_phone}}
{{client_name}} {{client_address}} {{client_email}} {{project_description}} {{quote_total}}
{{quote_number}} {{today}} {{validity_statement}} {{payment_schedule}}` — resolved at contract
generation into `terms_snapshot`.

## California home-improvement contract structure (placeholder sections — attorney to finalize)

The default template ships these sections as clearly-marked placeholders (B&P Code §7159 is the
reference for the *structure*, not the wording):

- Contractor name, **CSLB license number**, and address
- Description of the work and materials; approximate **start and completion dates**
- **Total contract price** and a **schedule of payments**
- **Down-payment limit** notice (the lesser of $1,000 or 10% of the contract price)
- **Three-day right to cancel** notice (and the 5-day/senior/disaster variants)
- **Mechanics' lien warning**
- Change-order, arbitration, and dispute language (placeholder)

Each rendered with a `[ATTORNEY REVIEW REQUIRED]` marker until the user's counsel replaces it.

## E-signature architecture (provider-agnostic)

`SignatureProvider` protocol (`app/features/contracts/providers/base.py`):
- `create_embedded_request(pdf_bytes, signer_name, signer_email, metadata) -> {request_id, sign_url}`
- `get_signed_pdf(request_id) -> bytes`
- `verify_and_parse_webhook(headers, raw_body) -> {event_type, request_id}`

`DropboxSignProvider` implements it (API key from env; embedded signing; HMAC-verified webhook).
Signature/date fields placed via **text tags** embedded in `contract.html`
(e.g. `[sig|req|signer1]`, `[date|req|signer1]`). Secrets via env only — no keys in code.

### Flows

1. **Generate**: approved quote → merge terms → render `contract.html` → WeasyPrint PDF →
   persist unsigned PDF → `contracts` row (status `draft`).
2. **Send**: create embedded request with provider (signer = client) → store `request_id` +
   `sign_url` → status `sent` → email the client a magic-link to `/sign/[token]` → FCM to mobile.
3. **Sign**: client opens (mobile WebView or web `/sign` page) → embedded ceremony → provider
   fires webhook → we download signed PDF → persist → status `signed`, `signed_at` → notify admin.
4. **Access**: signed PDF downloadable by admin (web) and client (mobile portal / signed email).

### Tokenized public access

Short-lived signed JWT (`contract_id`, `client_user_id`, ~72h) → public
`GET /api/v1/public/contracts/{token}` returns the contract view + a fresh embedded `sign_url`.
The `/sign/[token]` web page is unauthenticated but token-scoped to one contract. The provider
**webhook** is separate and authenticated by the provider's HMAC signature.

## Plans in this phase

- **29-01 (backend — data + docs):** migration 0029 (Company.license_number, contract_templates,
  contracts, RLS + default-template seed), quote "valid today only" (send sets expiry + PDF
  statement), wire client name into quote PDF, `contract.html` template, contract-generation
  service (merge → PDF → persist). Tests.
- **29-02 (backend — e-sign):** `SignatureProvider` + DropboxSign impl, send-for-signature,
  embedded `sign_url` endpoints, HMAC webhook → download+persist signed PDF → status, tokenized
  public contract endpoint, admin download. Tests (mocked provider).
- **29-03 (web admin):** Company settings (license # + **terms template editor** with the
  attorney-review banner and merge-field help), quote → "Create contract" / "Send for signature"
  actions, contracts list/detail + signed-PDF download.
- **29-04 (web client):** public `/sign/[token]` page hosting the embedded ceremony + terms/quote
  view + completion handling.
- **29-05 (mobile client):** client-portal contract card → "Review & Sign" WebView embedded
  ceremony → signed status + download.

Waves: 29-01 → 29-02 (backend). 29-03/29-04/29-05 depend on the 29-02 API and can run in parallel.

## Non-goals / follow-ups

- Not a full CLM (versioned negotiation, multi-party countersign) — single client signer +
  optional company countersignature is a follow-up.
- Structured company address (city/state/zip) deferred; free-text `address` used, `license_number`
  added now.
- Provider is Dropbox Sign; DocuSign is a later adapter swap, not built here.
- **Legal wording is the user's counsel's responsibility** — we ship structure + a review banner.
