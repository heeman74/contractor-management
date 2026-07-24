# Phase 29: Client Contracts & E-Signature - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-07-24
**Phase:** 29-client-contracts-and-esignature
**Areas discussed:** Quote validity statement, contract from quote, California-compliant terms, e-signature, signed-doc storage
**Mode:** interactive (AskUserQuestion)

---

## E-signature method

| Option | Description | Selected |
|--------|-------------|----------|
| Built-in capture | Reuse the drawing canvas; record consent/timestamp; flatten into PDF | |
| Third-party e-sign | DocuSign / Dropbox Sign hosted signing + audit trail; webhook returns signed PDF | ✓ |
| Built-in now, provider-ready | Built-in with a swappable model | |

**User's choice:** Third-party e-sign. Plan uses Dropbox Sign behind a `SignatureProvider`
adapter (DocuSign swappable) — provider confirmation flagged before 29-02.

---

## Signing channel

| Option | Description | Selected |
|--------|-------------|----------|
| Mobile app (authenticated) | Sign in the existing client portal | |
| Emailed magic-link web page | Tokenized public /sign page, no login | |
| Both | Mobile in-app AND emailed magic-link | ✓ |

**User's choice:** Both. Unified on a single embedded signature request surfaced via a mobile
WebView and an emailed magic-link to a public /sign/[token] page.

---

## Contract terms / California compliance

| Option | Description | Selected |
|--------|-------------|----------|
| Editable template + CA structure | Company-editable template; CA home-improvement structure as attorney-reviewed placeholders; add license_number | ✓ |
| I draft CA terms text | I write concrete CA language (still needs attorney review) | |
| Minimal terms block | One free-text terms field | |

**User's choice:** Editable template + CA structure. Default template ships CSLB/right-to-cancel/
down-payment/mechanics-lien sections as `[ATTORNEY REVIEW REQUIRED]` placeholders. **Not legal
advice — the user's counsel finalizes the wording.**

---

## Quote validity

| Option | Description | Selected |
|--------|-------------|----------|
| Per-quote, default 30 days | Admin-set expiry, 30-day default | |
| Fixed 30 days | Always 30 days | |
| Valid today only | Same-day expiry default | ✓ |

**User's choice:** Valid today only. `send_quote` defaults `expiry_date = today`; the quote PDF
states the quote is valid only for the day of issue (reuses the existing approve-time expiry check).

---

## Open items (confirm before execution)

| Item | Question | Status |
|------|----------|--------|
| Provider | Dropbox Sign vs DocuSign for the concrete adapter | Defaulted to Dropbox Sign; confirm before 29-02 |
| Legal wording | Who supplies/reviews the binding CA terms text | User's attorney — we ship structure + review banner only |
| Company countersignature | Does the company also sign, or client-only? | Assumed client-only signer for v1 (countersign = follow-up) |
| Contracts permission key | Reuse `quotes.manage` or add `contracts.manage` | Defaulted to `quotes.manage`; can add a dedicated key |
