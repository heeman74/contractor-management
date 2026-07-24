---
phase: 29-client-contracts-and-esignature
plan: "05"
subsystem: mobile
tags: [contracts, esignature, flutter, riverpod, webview, dio]
dependency_graph:
  requires:
    - 29-02 GET /contracts/{id}, /contracts/{id}/sign-url, signed_pdf_url
    - mobile resolveMediaUrl, DioClient + AuthInterceptor
  provides:
    - Contract domain/repository/providers
    - WebView embedded signing screen + client-job-detail contract card
key_files:
  created:
    - mobile/lib/features/contracts/domain/contract.dart
    - mobile/lib/features/contracts/data/contract_repository.dart
    - mobile/lib/features/contracts/presentation/providers/contract_providers.dart
    - mobile/lib/features/contracts/presentation/screens/contract_sign_screen.dart
    - mobile/test/unit/features/contracts/contract_repository_test.dart
  modified:
    - mobile/lib/features/client/presentation/screens/client_job_detail_screen.dart (Contract card)
    - mobile/lib/core/routing/{route_names.dart,app_router.dart} (contractSign route)
    - mobile/pubspec.yaml (webview_flutter)
key_decisions:
  - "ContractStatus.fromString is non-throwing (unknown fallback); Contract.fromJson validates shape (FormatException, no bare as)."
  - "Sign completion detected via BOTH an injected postMessage JS channel and navigation-URL fallback (heuristic — confirm against a live Dropbox Sign session)."
  - "contract_id reaches the client screen via a ?contractId= route query param (from the contract_ready FCM data payload); the card renders only when known. Wiring the FCM tap -> deep link is a noted follow-up (fcm_service.dart untouched, out of plan scope)."
  - "Signed PDF opened via url_launcher from the resolved /files URL (non-auth-gated mount)."
requirements-completed: [ESIGN-MOBILE-CLIENT-01]
completed: 2026-07-24
---

# Phase 29-05: Mobile Client Signing Summary

**A client can review a sent contract on the mobile job detail and complete the embedded
e-signature ceremony in a WebView, then see signed status + open the signed PDF.**

## Accomplishments
- `contracts` feature module: `Contract` domain model + `ContractStatus` (safe parsing),
  Dio `ContractRepository` (getContract / getSignUrl / signedPdfUrl), Riverpod providers.
- `ContractSignScreen`: loads the embedded `sign_url` in a WebView, detects completion
  (postMessage JS channel + URL fallback), refreshes + pops on success, handles load/errors.
- Client job detail gains a **Contract card**: status chip; Review & Sign (sent/viewed) → WebView;
  View signed contract (signed) → opens the signed PDF.

## Verification
- `dart analyze` (feature + client screen + router + test) → **No issues found**.
- `flutter test contract_repository_test.dart` → **14/14 pass**.

## Follow-up (noted, out of this plan's scope)
- Wire the `contract_ready` FCM notification tap to deep-link
  `/client/jobs/{jobId}?contractId={id}` so the card appears hands-free (fcm_service.dart untouched).
