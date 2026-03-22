"use client";

import { useState, useCallback } from "react";
import { useParams } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Map } from "lucide-react";
import { Button } from "@/components/ui/button";
import { GanttView } from "@/components/gantt/GanttView";
import { ConflictBadge } from "@/components/gantt/ConflictBadge";
import { CycleErrorDialog } from "@/components/gantt/CycleErrorDialog";
import { ZoneManageModal } from "@/components/gantt/ZoneManageModal";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useProject,
  useTradeScopes,
  useProjectZones,
  useProjectConflicts,
  useProjectDependencies,
  createTaskDependency,
  createProjectZone,
  deleteProjectZone,
} from "@/lib/api/projects";
import { apiPatch } from "@/lib/api-client";
import { ApiError } from "@/lib/api-client";
import type { DependencyType } from "@/components/gantt/DependencyTypeSelect";
import type { CycleErrorDetail, TaskDependencyResponse } from "@/types/dependencies";
import type { TradeScopeResponse } from "@/types/projects";

export default function GanttPage() {
  const params = useParams<{ id: string }>();
  const projectId = params.id;
  const queryClient = useQueryClient();

  // Fetch project + scopes with tasks
  const { data: project, isLoading: projectLoading } = useProject(projectId);
  const { data: scopes, isLoading: scopesLoading } = useTradeScopes(projectId);
  const { data: zonesRaw, refetch: refetchZones } = useProjectZones(projectId);
  const { data: conflictsRaw } = useProjectConflicts(projectId);
  const { data: depsRaw } = useProjectDependencies(scopes);

  const zones = Array.isArray(zonesRaw) ? zonesRaw : [];
  const conflicts = Array.isArray(conflictsRaw) ? conflictsRaw : [];

  // State
  const [cycleDialogOpen, setCycleDialogOpen] = useState(false);
  const [cycleData, setCycleData] = useState<CycleErrorDetail | null>(null);
  const [zoneModalOpen, setZoneModalOpen] = useState(false);

  // Collect all dependencies fetched via useProjectDependencies
  const allDependencies: TaskDependencyResponse[] = Array.isArray(depsRaw) ? depsRaw : [];

  const handleDependencyCreate = useCallback(
    async (
      predecessorId: string,
      successorId: string,
      type: DependencyType,
      lagDays: number
    ) => {
      try {
        await createTaskDependency(successorId, {
          predecessor_task_id: predecessorId,
          dependency_type: type,
          lag_days: lagDays,
        });
        // Invalidate queries to refresh
        await queryClient.invalidateQueries({ queryKey: ["trade-scopes", projectId] });
        await queryClient.invalidateQueries({ queryKey: ["project-conflicts", projectId] });
        await queryClient.invalidateQueries({ queryKey: ["project-dependencies"] });
      } catch (err) {
        if (err instanceof ApiError && err.status === 422) {
          // Parse cycle error detail from the error message
          // The backend returns detail as a string or object
          let cycleDetail: CycleErrorDetail = {
            message: err.detail,
            cycle: [],
            cycle_ids: [],
          };
          try {
            const parsed = JSON.parse(err.detail);
            if (parsed?.cycle) {
              cycleDetail = parsed as CycleErrorDetail;
            }
          } catch {
            // detail was a plain string, use as-is
          }
          setCycleData(cycleDetail);
          setCycleDialogOpen(true);
        } else {
          throw err;
        }
      }
    },
    [projectId, queryClient]
  );

  const handleTaskUpdate = useCallback(
    async (taskId: string, start: Date, end: Date) => {
      await apiPatch(`/api/v1/tasks/${taskId}`, {
        start_date: start.toISOString().split("T")[0],
        due_date: end.toISOString().split("T")[0],
      });
      await queryClient.invalidateQueries({ queryKey: ["trade-scopes", projectId] });
    },
    [projectId, queryClient]
  );

  const handleAddZone = useCallback(
    async (name: string) => {
      await createProjectZone(projectId, { name });
      refetchZones();
    },
    [projectId, refetchZones]
  );

  const handleDeleteZone = useCallback(
    async (id: string) => {
      await deleteProjectZone(id);
      refetchZones();
    },
    [refetchZones]
  );

  const isLoading = projectLoading || scopesLoading;

  if (isLoading) {
    return (
      <div className="flex flex-col gap-4 p-6">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-4 w-96" />
        <Skeleton className="h-[500px] w-full" />
      </div>
    );
  }

  const displayScopes: TradeScopeResponse[] = scopes ?? [];

  return (
    <div className="flex flex-col h-full">
      {/* Page header */}
      <div className="flex items-center justify-between border-b border-gray-200 px-6 py-3 bg-white flex-shrink-0">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Project Timeline</h1>
          {project?.name && (
            <p className="text-sm text-gray-500 mt-0.5">{project.name}</p>
          )}
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setZoneModalOpen(true)}
          data-testid="manage-zones-button"
        >
          <Map className="h-4 w-4" />
          Manage Zones
        </Button>
      </div>

      {/* Conflict banner */}
      {conflicts.length > 0 && (
        <div className="flex flex-col gap-2 px-6 py-3 bg-yellow-50 border-b border-yellow-200 flex-shrink-0">
          <div className="flex items-center gap-2 text-sm font-medium text-yellow-800">
            <AlertTriangle className="h-4 w-4" />
            <span>{conflicts.length} scheduling conflict{conflicts.length > 1 ? "s" : ""} detected</span>
          </div>
          <div className="flex flex-wrap gap-2">
            {conflicts.map((conflict, idx) => (
              <ConflictBadge
                key={idx}
                trade1={conflict.task1_trade_name}
                trade2={conflict.task2_trade_name}
                zone={conflict.zone_name}
                date={conflict.conflict_date}
              />
            ))}
          </div>
        </div>
      )}

      {/* Gantt chart */}
      <div className="flex-1 overflow-hidden">
        <GanttView
          projectId={projectId}
          scopes={displayScopes}
          dependencies={allDependencies}
          conflicts={conflicts}
          onDependencyCreate={handleDependencyCreate}
          onTaskUpdate={handleTaskUpdate}
        />
      </div>

      {/* Cycle error dialog */}
      <CycleErrorDialog
        open={cycleDialogOpen}
        onClose={() => {
          setCycleDialogOpen(false);
          setCycleData(null);
        }}
        cycleNames={cycleData?.cycle ?? []}
        cycleIds={cycleData?.cycle_ids ?? []}
      />

      {/* Zone manage modal */}
      <ZoneManageModal
        open={zoneModalOpen}
        onOpenChange={setZoneModalOpen}
        zones={zones}
        onAddZone={handleAddZone}
        onDeleteZone={handleDeleteZone}
      />
    </div>
  );
}
