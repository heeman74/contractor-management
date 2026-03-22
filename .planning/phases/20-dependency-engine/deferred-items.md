# Deferred Items

## Pre-existing TypeScript Build Errors (Out of Scope)

These errors existed in the committed codebase before Phase 20-03 execution:

### 1. create-contractor-dialog.tsx:208
**File:** `web/src/app/(dashboard)/contractors/_components/create-contractor-dialog.tsx`
**Error:** `Type 'Dispatch<SetStateAction<string>>' is not assignable to type '(value: string | null, eventDetails: SelectRootChangeEventDetails) => void'`
**Root cause:** Select `onValueChange` callback receives `string | null` but state setter is typed for `string`. Fix: use `(value: string | null) => setTradeType(value ?? "")` wrapper.

### 2. create-job-dialog.tsx (lines 172, 195, 218, 243)
**File:** `web/src/app/(dashboard)/jobs/_components/create-job-dialog.tsx`
**Same issue as above** — Select `onValueChange` type mismatch.

These errors cause `npx next build` to fail but are not introduced by Phase 20-03 changes.
All new files created in Phase 20-03 compile without TypeScript errors (verified via `npx tsc --noEmit`).
