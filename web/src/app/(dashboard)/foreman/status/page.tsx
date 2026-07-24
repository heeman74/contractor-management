"use client";

import { useAssignedProjects } from "@/lib/hooks/useForeman";
import Link from "next/link";
import { ClipboardList, ArrowRight } from "lucide-react";

export default function ForemanStatusIndexPage() {
  const { data: assignments, isLoading, isError, refetch } = useAssignedProjects();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900 flex items-center gap-2">
          <ClipboardList className="h-5 w-5" />
          Daily Status Updates
        </h1>
        <p className="text-sm text-gray-500">
          Select a project to view or submit daily status updates.
        </p>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-24 animate-pulse rounded-xl bg-gray-100" />
          ))}
        </div>
      ) : isError ? (
        <div className="rounded-xl bg-red-50 border border-red-200 px-4 py-6 text-center">
          <p className="text-sm text-red-600 font-medium">
            Failed to load your project assignments.
          </p>
          <button
            onClick={() => refetch()}
            className="mt-2 text-xs text-red-500 underline hover:text-red-700"
          >
            Retry
          </button>
        </div>
      ) : !assignments || assignments.length === 0 ? (
        <div className="rounded-xl bg-gray-50 border border-gray-200 px-4 py-8 text-center text-sm text-gray-500">
          You have no project assignments yet. Contact your admin to get assigned to a project.
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {assignments.map((a) => (
            <Link
              key={a.id}
              href={`/foreman/status/${a.project_id}`}
              className="flex items-center justify-between rounded-xl border border-gray-200 bg-white px-5 py-4 shadow-sm hover:border-brand/60 hover:shadow-md transition-all group"
            >
              <div>
                <p className="text-sm font-medium text-gray-900">
                  {a.project_name ?? "Unnamed Project"}
                </p>
                <p className="text-xs text-gray-500 mt-0.5">
                  Assigned {new Date(a.assigned_at).toLocaleDateString()}
                </p>
              </div>
              <ArrowRight className="h-4 w-4 text-gray-400 group-hover:text-foreground transition-colors" />
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
