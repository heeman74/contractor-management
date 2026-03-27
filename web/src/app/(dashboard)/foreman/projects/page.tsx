"use client";

import { useAssignedProjects, useLatestStatus } from "@/lib/hooks/useForeman";
import Link from "next/link";
import type { ProjectAssignment } from "@/lib/types/foreman";
import { HardHat, ArrowRight, CloudSun, Users, ShieldAlert } from "lucide-react";

function ProjectCard({ assignment }: { assignment: ProjectAssignment }) {
  const { data: latest } = useLatestStatus(assignment.project_id);

  return (
    <Link
      href={`/foreman/status/${assignment.project_id}`}
      className="flex flex-col rounded-xl border border-gray-200 bg-white p-5 shadow-sm hover:border-indigo-300 hover:shadow-md transition-all group"
    >
      <div className="flex items-center justify-between mb-3">
        <p className="text-sm font-semibold text-gray-900">
          {assignment.project_name ?? "Unnamed Project"}
        </p>
        <ArrowRight className="h-4 w-4 text-gray-400 group-hover:text-indigo-500 transition-colors" />
      </div>

      <p className="text-xs text-gray-500 mb-2">
        Assigned {new Date(assignment.assigned_at).toLocaleDateString()}
      </p>

      {latest ? (
        <div className="rounded-lg bg-gray-50 p-3 text-xs text-gray-600 space-y-1">
          <p className="font-medium text-gray-700 truncate">
            Latest: {latest.status_text}
          </p>
          <div className="flex flex-wrap gap-2">
            {latest.weather_conditions && (
              <span className="flex items-center gap-1">
                <CloudSun className="h-3 w-3" />
                {latest.weather_conditions}
              </span>
            )}
            {latest.workers_on_site != null && (
              <span className="flex items-center gap-1">
                <Users className="h-3 w-3" />
                {latest.workers_on_site}
              </span>
            )}
            {latest.safety_incidents > 0 && (
              <span className="flex items-center gap-1 text-red-600 font-medium">
                <ShieldAlert className="h-3 w-3" />
                {latest.safety_incidents}
              </span>
            )}
          </div>
          <p className="text-gray-400">
            {new Date(latest.report_date).toLocaleDateString()}
          </p>
        </div>
      ) : (
        <p className="text-xs text-gray-400 italic">No status updates yet</p>
      )}
    </Link>
  );
}

export default function ForemanProjectsPage() {
  const { data: assignments, isLoading, isError, refetch } = useAssignedProjects();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900 flex items-center gap-2">
          <HardHat className="h-5 w-5" />
          My Projects
        </h1>
        <p className="text-sm text-gray-500">
          Projects you are assigned to supervise as foreman.
        </p>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-40 animate-pulse rounded-xl bg-gray-100" />
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
            <ProjectCard key={a.id} assignment={a} />
          ))}
        </div>
      )}
    </div>
  );
}
