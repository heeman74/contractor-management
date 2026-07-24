"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import { useAppSelector } from "@/store/hooks";
import type { MyPermissionsResponse } from "@/types/api";

const PERMISSIONS_STALE_TIME_MS = 5 * 60_000;

/**
 * The current user's effective permission keys, from GET /me/permissions
 * (the union across their roles, resolved server-side against the company matrix).
 *
 * `can(key)` returns false while loading and for any key the user lacks, so gated
 * UI stays hidden until permissions are known rather than flashing.
 */
export function usePermissions() {
  const isAuthenticated = useAppSelector((state) => state.auth.isAuthenticated);

  const { data, isLoading } = useQuery<MyPermissionsResponse>({
    queryKey: ["me-permissions"],
    queryFn: () => apiGet<MyPermissionsResponse>("/api/v1/me/permissions"),
    enabled: isAuthenticated,
    staleTime: PERMISSIONS_STALE_TIME_MS,
  });

  const permissions = useMemo(() => new Set(data?.permissions ?? []), [data]);
  const can = useMemo(() => (key: string) => permissions.has(key), [permissions]);

  return { can, permissions, isLoading };
}
