"use client";

import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import type { ContractorResource } from "@/types/schedule";

interface UserResponse {
  id: string;
  full_name?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  avatar_url?: string | null;
  trade_type?: string | null;
}

export function useContractors() {
  const { data: contractors, isLoading, isError } = useQuery({
    queryKey: ["contractors"],
    queryFn: () => apiGet<UserResponse[]>("/api/v1/users?role=contractor"),
    select: (users: UserResponse[]): ContractorResource[] => {
      return users
        .map((user) => ({
          id: user.id,
          name:
            user.full_name ??
            (`${user.first_name ?? ""} ${user.last_name ?? ""}`.trim() ||
              "Unknown"),
          avatarUrl: user.avatar_url ?? undefined,
          tradeType: user.trade_type ?? undefined,
        }))
        .sort((a, b) => a.name.localeCompare(b.name));
    },
    staleTime: 5 * 60 * 1000, // 5 minutes - contractors change infrequently
  });

  return {
    contractors: contractors ?? [],
    isLoading,
    isError,
  };
}
