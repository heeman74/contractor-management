"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { useStatusUpdates, useLatestStatus } from "@/lib/hooks/useForeman";
import { useAppSelector } from "@/store/hooks";
import { isGc } from "@/lib/roles";
import type { ProjectStatusUpdate } from "@/lib/types/foreman";
import { StatusUpdateForm } from "../_components/StatusUpdateForm";
import {
  AlertTriangle,
  CloudSun,
  Users,
  ShieldAlert,
  Clock,
  FileText,
} from "lucide-react";

function getCardColorClass(update: ProjectStatusUpdate): string {
  if (update.safety_incidents > 0) {
    return "border-red-300 bg-red-50";
  }
  if (update.blockers) {
    return "border-yellow-300 bg-yellow-50";
  }
  return "border-green-300 bg-green-50";
}

function getCardAccentClass(update: ProjectStatusUpdate): string {
  if (update.safety_incidents > 0) return "bg-red-500";
  if (update.blockers) return "bg-yellow-500";
  return "bg-green-500";
}

export default function ProjectStatusPage() {
  const params = useParams<{ projectId: string }>();
  const projectId = params.projectId;
  const roles = useAppSelector((state) => state.auth.roles);
  const isForeman = roles.includes("foreman") || isGc(roles);

  const [showForm, setShowForm] = useState(false);

  const {
    data: updates,
    isLoading,
    isError,
    refetch,
  } = useStatusUpdates(projectId);

  const { data: latestStatus } = useLatestStatus(projectId);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 flex items-center gap-2">
            <FileText className="h-5 w-5" />
            Daily Status Updates
          </h1>
          <p className="text-sm text-gray-500">
            Project status history and daily reports.
          </p>
        </div>
        {isForeman && (
          <button
            onClick={() => setShowForm((prev) => !prev)}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary/90 transition-colors"
          >
            {showForm ? "Cancel" : "New Status Update"}
          </button>
        )}
      </div>

      {/* Status update form */}
      {showForm && (
        <StatusUpdateForm
          projectId={projectId}
          onSuccess={() => setShowForm(false)}
        />
      )}

      {/* Latest status highlight */}
      {latestStatus && !showForm && (
        <div className="rounded-xl border-2 border-brand/40 bg-secondary p-4">
          <div className="flex items-center gap-2 mb-2">
            <span className="text-xs font-semibold uppercase tracking-wide text-foreground">
              Latest Update
            </span>
            <span className="text-xs text-gray-500">
              {new Date(latestStatus.report_date).toLocaleDateString()}
            </span>
          </div>
          <p className="text-sm text-gray-800">{latestStatus.status_text}</p>
          <div className="mt-2 flex flex-wrap gap-3 text-xs text-gray-600">
            {latestStatus.weather_conditions && (
              <span className="flex items-center gap-1">
                <CloudSun className="h-3.5 w-3.5" />
                {latestStatus.weather_conditions}
              </span>
            )}
            {latestStatus.workers_on_site != null && (
              <span className="flex items-center gap-1">
                <Users className="h-3.5 w-3.5" />
                {latestStatus.workers_on_site} workers
              </span>
            )}
            <span className="flex items-center gap-1">
              <ShieldAlert className="h-3.5 w-3.5" />
              {latestStatus.safety_incidents} incidents
            </span>
          </div>
        </div>
      )}

      {/* Timeline of status updates */}
      {isLoading ? (
        <div className="space-y-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="h-32 animate-pulse rounded-xl bg-gray-100" />
          ))}
        </div>
      ) : isError ? (
        <div className="rounded-xl bg-red-50 border border-red-200 px-4 py-6 text-center">
          <p className="text-sm text-red-600 font-medium">
            Failed to load status updates.
          </p>
          <button
            onClick={() => refetch()}
            className="mt-2 text-xs text-red-500 underline hover:text-red-700"
          >
            Retry
          </button>
        </div>
      ) : !updates || updates.length === 0 ? (
        <div className="rounded-xl bg-gray-50 border border-gray-200 px-4 py-8 text-center text-sm text-gray-500">
          No status updates yet for this project.
        </div>
      ) : (
        <div className="relative space-y-4">
          {/* Vertical timeline line */}
          <div className="absolute left-4 top-0 bottom-0 w-0.5 bg-gray-200" />

          {updates.map((update) => (
            <div key={update.id} className="relative pl-10">
              {/* Timeline dot */}
              <div
                className={`absolute left-2.5 top-4 h-3 w-3 rounded-full ring-2 ring-white ${getCardAccentClass(update)}`}
              />

              <div
                className={`rounded-xl border p-4 shadow-sm ${getCardColorClass(update)}`}
              >
                {/* Header row */}
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Clock className="h-3.5 w-3.5 text-gray-400" />
                    <span className="text-xs font-medium text-gray-600">
                      {new Date(update.report_date).toLocaleDateString("en-US", {
                        weekday: "short",
                        month: "short",
                        day: "numeric",
                        year: "numeric",
                      })}
                    </span>
                  </div>
                  {update.author_name && (
                    <span className="text-xs text-gray-500">
                      by {update.author_name}
                    </span>
                  )}
                </div>

                {/* Status text */}
                <p className="text-sm text-gray-800 mb-3">
                  {update.status_text}
                </p>

                {/* Metadata row */}
                <div className="flex flex-wrap gap-3 text-xs text-gray-600">
                  {update.weather_conditions && (
                    <span className="flex items-center gap-1 rounded-full bg-white/60 px-2 py-0.5">
                      <CloudSun className="h-3 w-3" />
                      {update.weather_conditions}
                    </span>
                  )}
                  {update.workers_on_site != null && (
                    <span className="flex items-center gap-1 rounded-full bg-white/60 px-2 py-0.5">
                      <Users className="h-3 w-3" />
                      {update.workers_on_site} workers
                    </span>
                  )}
                  {update.safety_incidents > 0 && (
                    <span className="flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-red-700 font-medium">
                      <ShieldAlert className="h-3 w-3" />
                      {update.safety_incidents} safety incident{update.safety_incidents !== 1 ? "s" : ""}
                    </span>
                  )}
                  {update.blockers && (
                    <span className="flex items-center gap-1 rounded-full bg-yellow-100 px-2 py-0.5 text-yellow-700 font-medium">
                      <AlertTriangle className="h-3 w-3" />
                      Blockers
                    </span>
                  )}
                </div>

                {/* Blockers detail */}
                {update.blockers && (
                  <div className="mt-2 rounded-md bg-yellow-100/50 px-3 py-2 text-xs text-yellow-800">
                    <span className="font-medium">Blockers:</span> {update.blockers}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
