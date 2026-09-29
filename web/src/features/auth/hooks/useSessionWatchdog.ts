"use client";

import { useEffect, useRef } from "react";

import { verifySession } from "@/lib/api-client";

/** Don't re-verify more often than this — alt-tabbing fires focus constantly. */
export const VERIFY_THROTTLE_MS = 60_000;

/**
 * Sends the user to the login page when they return to a tab whose session has
 * since expired, instead of leaving them looking at data loaded before it did.
 *
 * Without this the app only notices a dead session when something happens to
 * make a request, so an idle tab keeps rendering a dashboard that looks live
 * and is not.
 *
 * Focus-triggered rather than periodic on purpose: confirming a session is
 * alive necessarily renews it, so a timer would keep an abandoned tab signed
 * in rather than expiring it. See verifySession.
 */
export function useSessionWatchdog(): void {
  // Seeded in the effect, not here: Date.now() during render is impure and
  // would give an unstable value across re-renders.
  const lastVerifiedAt = useRef<number>(0);

  useEffect(() => {
    // A page that just loaded has a fresh session — start the clock rather
    // than verifying on the first focus the user gives it.
    lastVerifiedAt.current = Date.now();

    async function verifyIfStale() {
      if (document.visibilityState !== "visible") return;
      const now = Date.now();
      if (now - lastVerifiedAt.current < VERIFY_THROTTLE_MS) return;
      lastVerifiedAt.current = now;
      await verifySession();
    }

    document.addEventListener("visibilitychange", verifyIfStale);
    window.addEventListener("focus", verifyIfStale);
    return () => {
      document.removeEventListener("visibilitychange", verifyIfStale);
      window.removeEventListener("focus", verifyIfStale);
    };
  }, []);
}
