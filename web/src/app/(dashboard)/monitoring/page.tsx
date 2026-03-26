"use client";

import { useState, useCallback } from "react";
import { useDashboardProjects } from "@/lib/hooks/useDashboard";
import { ProjectStatusCard } from "./_components/ProjectStatusCard";
import { AlertPanel } from "./_components/AlertPanel";
import { TradeTimeline } from "./_components/TradeTimeline";

export default function MonitoringPage() {
  const { data: projects, isLoading, isError, refetch } = useDashboardProjects();
  const [selectedProjectId, setSelectedProjectId] = useState<string | null>(null);

  const handleSelectProject = useCallback((projectId: string) => {
    setSelectedProjectId((prev) => (prev === projectId ? null : projectId));
  }, []);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Project Monitoring</h1>
        <p className="text-sm text-gray-500">
          Monitor all active projects and AI-generated alerts in real time.
        </p>
      </div>

      <div className="flex flex-col xl:flex-row gap-6">
        {/* Left column: project cards */}
        <div className="flex-1 min-w-0 space-y-4">
          {isLoading ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {[...Array(4)].map((_, i) => (
                <div
                  key={i}
                  className="h-48 animate-pulse rounded-xl bg-gray-100"
                />
              ))}
            </div>
          ) : isError ? (
            <div className="rounded-xl bg-red-50 border border-red-200 px-4 py-6 text-center">
              <p className="text-sm text-red-600 font-medium">
                Failed to load projects.
              </p>
              <button
                onClick={() => refetch()}
                className="mt-2 text-xs text-red-500 underline hover:text-red-700"
              >
                Retry
              </button>
            </div>
          ) : !projects || projects.length === 0 ? (
            <div className="rounded-xl bg-gray-50 border border-gray-200 px-4 py-8 text-center text-sm text-gray-500">
              No active projects found.
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {projects.map((project) => (
                <ProjectStatusCard
                  key={project.project_id}
                  project={project}
                  isSelected={selectedProjectId === project.project_id}
                  onSelect={() => handleSelectProject(project.project_id)}
                />
              ))}
            </div>
          )}

          {/* Trade timeline expands below the grid when a project is selected */}
          {selectedProjectId && (
            <div className="mt-4">
              <TradeTimeline projectId={selectedProjectId} />
            </div>
          )}
        </div>

        {/* Right column: alert panel */}
        <div className="xl:w-80 flex-shrink-0">
          <AlertPanel projectId={selectedProjectId ?? undefined} />
        </div>
      </div>
    </div>
  );
}
