"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Calendar, MapPin, Plus, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/shared/status-badge";
import { AddTradeScopeSheet } from "./AddTradeScopeSheet";
import { ProjectAssignmentsCard } from "./ProjectAssignmentsCard";
import { useTradeScopes, useTasks } from "@/lib/api/projects";
import { apiGet } from "@/lib/api-client";
import { TradeProgressCard } from "@/features/tasks/components/TradeProgressCard";
import type { ProjectResponse, TradeScopeResponse } from "@/types/projects";
import type { Job } from "@/types/api";

/**
 * Jobs belonging to this project (e.g. the per-field jobs created when a
 * project-level quote is approved). Each row links to the job for editing.
 */
function ProjectJobsCard({ projectId }: { projectId: string }) {
  const router = useRouter();
  const { data: jobs } = useQuery({
    queryKey: ["project-jobs", projectId],
    queryFn: () =>
      apiGet<Job[]>(`/api/v1/jobs/?project_id=${encodeURIComponent(projectId)}`),
  });

  return (
    <div>
      <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-700">
        Jobs ({jobs?.length ?? 0})
      </h3>
      {jobs && jobs.length > 0 ? (
        <div className="space-y-2">
          {jobs.map((job) => (
            <div
              key={job.id}
              role="button"
              tabIndex={0}
              onClick={() => router.push(`/jobs/${job.id}`)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  router.push(`/jobs/${job.id}`);
                }
              }}
              className="flex cursor-pointer items-center justify-between gap-3 rounded-lg border border-gray-200 bg-white p-3 transition-colors hover:bg-gray-50"
            >
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-gray-800">
                  {job.description}
                </p>
                <p className="text-xs text-gray-500">{job.trade_type}</p>
              </div>
              <StatusBadge status={job.status} size="sm" />
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-gray-500">No jobs yet.</p>
      )}
    </div>
  );
}

interface ProjectDetailProps {
  project: ProjectResponse;
  onSelectScope: (scope: TradeScopeResponse) => void;
}

/**
 * Inner component that renders a single scope with live task counts.
 * Isolates the per-scope `useTasks` hook so each scope fetches independently.
 */
function ScopeProgressCard({
  scope,
  onSelect,
}: {
  scope: TradeScopeResponse;
  onSelect: () => void;
}) {
  const { data: tasks } = useTasks(scope.id);

  const totalTasks = tasks?.length ?? 0;
  const completedTasks = tasks?.filter((t) => t.status === "complete").length ?? 0;

  // Capture mount time in state to avoid impure Date.now() during render
  const [mountTime] = useState(() => Date.now());

  // Format last activity from the most recently updated task
  const lastActivity = useMemo(() => {
    if (!tasks) return undefined;
    const sorted = [...tasks].sort(
      (a, b) =>
        new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
    );
    if (sorted.length === 0) return undefined;
    const diff = mountTime - new Date(sorted[0].updated_at).getTime();
    const hours = Math.floor(diff / (1000 * 60 * 60));
    if (hours < 1) return "Just now";
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }, [tasks, mountTime]);

  return (
    <TradeProgressCard
      tradeName={scope.trade_name}
      tradeColor={scope.trade_color || "#6b7280"}
      completedTasks={completedTasks}
      totalTasks={totalTasks}
      lastActivity={lastActivity}
      onClick={onSelect}
    />
  );
}

export function ProjectDetail({ project, onSelectScope }: ProjectDetailProps) {
  const [addScopeOpen, setAddScopeOpen] = useState(false);
  const { data: scopes, refetch } = useTradeScopes(project.id);

  const handleScopeAdded = () => {
    refetch();
    setAddScopeOpen(false);
  };

  return (
    <div className="flex flex-col gap-6 p-6">
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-xl font-semibold text-gray-900">{project.name}</h2>
          {project.description && (
            <p className="text-sm text-gray-500">{project.description}</p>
          )}
        </div>
        <div className="flex flex-shrink-0 items-center gap-2">
          <StatusBadge status={project.status} />
          <Button
            size="sm"
            onClick={() => setAddScopeOpen(true)}
            data-testid="add-trade-scope-button"
          >
            <Plus className="h-4 w-4" />
            Add Trade Scope
          </Button>
        </div>
      </div>

      {/* Meta row */}
      <div className="flex flex-wrap gap-4 text-sm text-gray-600">
        {project.address && (
          <span className="flex items-center gap-1">
            <MapPin className="h-3.5 w-3.5 text-gray-400" />
            {project.address}
          </span>
        )}
        {project.client_id && (
          <span className="flex items-center gap-1">
            <User className="h-3.5 w-3.5 text-gray-400" />
            Client ID: {project.client_id}
          </span>
        )}
        {project.target_start_date && (
          <span className="flex items-center gap-1">
            <Calendar className="h-3.5 w-3.5 text-gray-400" />
            Starts: {new Date(project.target_start_date).toLocaleDateString()}
          </span>
        )}
        {project.target_end_date && (
          <span className="flex items-center gap-1">
            <Calendar className="h-3.5 w-3.5 text-gray-400" />
            Ends: {new Date(project.target_end_date).toLocaleDateString()}
          </span>
        )}
      </div>

      {/* Team assignments (PM, contractor) */}
      <ProjectAssignmentsCard projectId={project.id} />

      {/* Jobs (e.g. per-field jobs created from an approved project quote) */}
      <ProjectJobsCard projectId={project.id} />

      {/* Trade scopes with progress */}
      <div>
        <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-700">
          Trade Scopes ({scopes?.length ?? 0})
        </h3>
        {scopes && scopes.length > 0 ? (
          <div className="space-y-3">
            {scopes.map((scope) => (
              <ScopeProgressCard
                key={scope.id}
                scope={scope}
                onSelect={() => onSelectScope(scope)}
              />
            ))}
          </div>
        ) : (
          <p className="text-sm text-gray-500">
            No trade scopes yet. Add one to get started.
          </p>
        )}
      </div>

      <AddTradeScopeSheet
        open={addScopeOpen}
        onOpenChange={setAddScopeOpen}
        projectId={project.id}
        onSuccess={handleScopeAdded}
      />
    </div>
  );
}
