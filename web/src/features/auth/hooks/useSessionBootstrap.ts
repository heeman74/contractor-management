"use client";

import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";

import { apiGet } from "@/lib/api-client";
import { useAppDispatch, useAppSelector } from "@/store/hooks";
import { setAuthUser } from "@/store/slices/auth-slice";
import type { MeResponse } from "@/types/api";

const IDENTITY_STALE_TIME_MS = 5 * 60_000;

/**
 * Restores who the user is after a page load.
 *
 * Redux held the identity and only the login page ever wrote it, so a browser
 * refresh reset the store: the name fell back to a generic placeholder and
 * `isAuthenticated` went false. That second part was the real damage —
 * usePermissions gates its query on it, so `can()` answered false for
 * everything and permission-gated UI silently disappeared until the next login.
 *
 * Deliberately not gated on isAuthenticated: that is the value being restored,
 * so keying the fetch off it would mean it never runs.
 */
export function useSessionBootstrap(): void {
  const dispatch = useAppDispatch();
  const isAuthenticated = useAppSelector((state) => state.auth.isAuthenticated);
  const displayName = useAppSelector((state) => state.auth.displayName);

  const { data } = useQuery<MeResponse>({
    queryKey: ["me-identity"],
    queryFn: () => apiGet<MeResponse>("/api/v1/auth/me"),
    staleTime: IDENTITY_STALE_TIME_MS,
    // A 401 means the session is genuinely gone, and api-client already
    // redirects to login — retrying would only delay that.
    retry: false,
  });

  useEffect(() => {
    if (!data) return;
    const alreadyCurrent = isAuthenticated && displayName === data.display_name;
    if (alreadyCurrent) return;

    dispatch(
      setAuthUser({
        displayName: data.display_name,
        companyName: data.company_name,
        roles: data.roles,
      })
    );
  }, [data, dispatch, isAuthenticated, displayName]);
}
