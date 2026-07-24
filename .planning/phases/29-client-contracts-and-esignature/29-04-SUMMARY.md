---
phase: 29-client-contracts-and-esignature
plan: "04"
subsystem: web
tags: [contracts, esignature, public, magic-link, nextjs]
dependency_graph:
  requires:
    - 29-02 GET /public/contracts/{token}
  provides:
    - Public cookie-free /sign/[token] page hosting the embedded ceremony
key_files:
  created:
    - web/src/app/api/public-contract/[token]/route.ts
    - web/src/app/sign/[token]/page.tsx
    - web/src/app/sign/[token]/_components/embedded-signer.tsx
key_decisions:
  - "Public route forwards to the backend WITHOUT the access_token cookie — the token is the capability."
  - "Embedded signer uses an iframe of sign_url (no external CDN/CSP dependency); provider specifics isolated for a DocuSign swap."
  - "terms_snapshot rendered via dangerouslySetInnerHTML (company-authored HTML), commented."
requirements-completed: [ESIGN-WEB-CLIENT-01]
completed: 2026-07-24
---

# Phase 29-04: Web Client Sign Page Summary

**The emailed magic-link opens a public, login-free `/sign/[token]` page that shows the contract
terms + validity and hosts the embedded e-signature ceremony.**

## Accomplishments
- `api/public-contract/[token]/route.ts`: cookie-free proxy to `GET /public/contracts/{token}`.
- `sign/[token]/page.tsx`: standalone public page (outside the dashboard group) — company/client
  header, validity statement, `terms_snapshot`, `<EmbeddedSigner/>`; handles invalid/expired token
  and an already-signed state (with signed-PDF link).
- `EmbeddedSigner`: iframe of the provider `sign_url`, listening for the provider's signed
  postMessage; encapsulated so a DocuSign swap is localized.

## Verification
- `npx tsc --noEmit` clean; `npx eslint --max-warnings 0` clean.
