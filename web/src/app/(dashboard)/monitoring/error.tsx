"use client";

import { useEffect } from "react";
import { logger } from "@/lib/logger";

interface ErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function MonitoringError({ error, reset }: ErrorProps) {
  useEffect(() => {
    logger.error("MonitoringError", error.message, {
      name: error.name,
      digest: error.digest,
      stack: error.stack,
    });
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center gap-4 rounded-xl border border-red-200 bg-red-50 px-6 py-12 text-center">
      <h2 className="text-lg font-semibold text-red-700">
        Something went wrong
      </h2>
      <p className="max-w-md text-sm text-red-600">
        The monitoring dashboard encountered an unexpected error. You can try
        reloading this section.
      </p>
      <button
        onClick={reset}
        className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 transition-colors"
      >
        Try again
      </button>
    </div>
  );
}
