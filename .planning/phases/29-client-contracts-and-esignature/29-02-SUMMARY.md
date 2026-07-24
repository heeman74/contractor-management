---
phase: 29-client-contracts-and-esignature
plan: "02"
subsystem: backend
tags: [contracts, esignature, dropbox-sign, webhook, jwt, rls, fastapi]
dependency_graph:
  requires:
    - 29-01 (Contract model, unsigned_pdf_url, provider fields, contract PDF with sign anchors)
    - app/core/security.py (jwt, effective_permissions), app/core/tenant.py (set_current_tenant_id)
    - app/features/notifications/service.py (FCM patterns)
  provides:
    - SignatureProvider protocol + DropboxSignProvider (embedded request, sign-url, signed-pdf, HMAC webhook)
    - Contract e-sign lifecycle (send / sign-url / mark-signed / declined) + signed-PDF persistence
    - Tokenized public contract access (parse_contract_token) + /public/contracts/{token}
    - Endpoints: send, sign-url, signed.pdf, webhook, public view
  affects:
    - 29-04 (web /sign page consumes /public/contracts/{token})
    - 29-05 (mobile consumes /contracts/{id}/sign-url)
tech_stack:
  added: []
  patterns:
    - "Provider-agnostic SignatureProvider protocol; DropboxSign via thin httpx client (no SDK)"
    - "One embedded request serves both channels (mobile WebView + emailed magic-link web page)"
    - "Webhook resolves the RLS-forced contract via signature-request metadata (company_id) -> set_current_tenant_id"
    - "Short-lived JWT capability token for login-free public signing"
    - "FastAPI dependency-injected provider (get_signature_provider), overridden with a fake in tests"
key_files:
  created:
    - backend/app/features/contracts/providers/{__init__,base,dropbox_sign}.py
    - backend/app/features/contracts/tokens.py
    - backend/tests/test_contracts_esign.py
  modified:
    - backend/app/features/contracts/service.py (send_for_signature, get_sign_url, get_public_view, mark_signed, record_declined)
    - backend/app/features/contracts/router.py (send / sign-url / signed.pdf / webhook / public)
    - backend/app/features/contracts/schemas.py (Send/SignUrl/PublicContractView)
    - backend/app/features/notifications/service.py (contract ready/signed notifications)
    - backend/app/core/config.py (dropbox_sign_* + public_web_url)
    - backend/app/main.py (public_router registered)
key_decisions:
  - "Both signing channels reuse ONE embedded request: mobile GETs sign-url; the emailed magic-link opens /sign/{token} hosting the same ceremony."
  - "Webhook is public + HMAC-verified; it reads company_id from the provider metadata to set tenant context so it can update the RLS-forced contract without a login."
  - "Magic-link EMAIL delivery is a stubbed TODO (app has no email provider yet) — the link is logged + pushed via FCM; the token + public endpoint + web page are the real deliverables."
  - "Signed PDF download allowed for contracts.manage OR the signer client."
patterns_established:
  - "E-sign vendor is swappable behind SignatureProvider (DocuSign = one more adapter)."
requirements-completed: [ESIGN-01, ESIGN-02, ESIGN-03, ESIGN-04]
duration: ~45min
completed: 2026-07-24
---

# Phase 29-02: E-Signature Integration Summary

**Contracts are now signable end to end: send creates a Dropbox Sign embedded request (used by
both mobile in-app and the emailed magic-link web page), and the HMAC-verified webhook downloads
and stores the signed PDF back in ContractorHub.**

## Accomplishments
- **Provider adapter**: `SignatureProvider` protocol + `DropboxSignProvider` (thin httpx client:
  create_embedded_request, get_sign_url, get_signed_pdf, HMAC-verified webhook). Swappable for
  DocuSign later.
- **Service lifecycle**: `send_for_signature` (embedded request + status→sent + client notify +
  magic-link token), `get_sign_url` (+ record view), `get_public_view`, `mark_signed` (download +
  persist signed PDF, idempotent), `record_declined`.
- **Endpoints**: `POST /contracts/{id}/send`, `GET /contracts/{id}/sign-url`,
  `GET /contracts/{id}/signed.pdf` (manager or signer), `POST /contracts/webhook/dropbox-sign`
  (public, HMAC), `GET /public/contracts/{token}` (login-free view + sign_url).
- **Tokenized access**: 72h JWT capability token; the webhook resolves the RLS-forced contract
  via signature-request metadata (`company_id`).
- **Config**: `DROPBOX_SIGN_API_KEY / _CLIENT_ID / _TEST_MODE`, `PUBLIC_WEB_URL` (env-only secrets).

## Verification
- **5 e-sign tests pass** (send, webhook-signed persistence, HMAC-failure rejection, public-token
  view + tampered-token 401, signed-PDF download authz) with a mocked provider — no network I/O.
- `ruff check`/`format` clean; app builds (196 routes); 18-test regression green.

## Notes for downstream / ops
- **To go live**: set the `DROPBOX_SIGN_*` env vars and configure the Dropbox Sign account's
  webhook URL to `{backend}/api/v1/contracts/webhook/dropbox-sign`.
- **Email delivery of the magic link is a TODO** — no email provider is wired yet; the link is
  logged and pushed via FCM. Add SendGrid/SMTP in a follow-up.
- 29-04 (web) uses `GET /public/contracts/{token}`; 29-05 (mobile) uses `/contracts/{id}/sign-url`.
