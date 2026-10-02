"use client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";
import { useState } from "react";
import { ApiError } from "@/lib/api-client";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // Every browser request reaches the API through this app, over a
            // hop the platform rate limits in bursts. Refetching all of a
            // dashboard's queries each time the tab regains focus is the
            // largest avoidable source of that traffic, and none of this data
            // changes second to second — a job does not become a different job
            // because somebody switched windows.
            refetchOnWindowFocus: false,
            staleTime: 120_000,
            retry: (failureCount, error) => {
              // Client errors (4xx) won't succeed on retry — retrying only
              // doubles the error logs. Retry once for everything else (5xx,
              // network blips). 401 is handled separately by the api client.
              if (
                error instanceof ApiError &&
                error.status >= 400 &&
                error.status < 500
              ) {
                return false;
              }
              return failureCount < 1;
            },
          },
        },
      })
  );
  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
