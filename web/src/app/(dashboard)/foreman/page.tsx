"use client";

import { useState, useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import { useProjectAssignments, useAssignForeman, useUnassignForeman } from "@/lib/hooks/useForeman";
import { useAppSelector } from "@/store/hooks";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
  DialogClose,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { HardHat, Plus, Trash2, Loader2 } from "lucide-react";

interface ProjectListItem {
  id: string;
  name: string;
}

interface UserListItem {
  id: string;
  full_name: string;
  email: string;
}

export default function ForemanAssignmentsPage() {
  const roles = useAppSelector((state) => state.auth.roles);
  const isAdmin = roles.includes("admin") || roles.includes("owner");

  const [selectedProjectId, setSelectedProjectId] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState("");

  // Fetch projects list for the selector
  const { data: projects, isLoading: projectsLoading } = useQuery<ProjectListItem[]>({
    queryKey: ["projects-list"],
    queryFn: () => apiGet<ProjectListItem[]>("/api/v1/projects/"),
  });

  // Fetch users for assignment dialog
  const { data: users } = useQuery<UserListItem[]>({
    queryKey: ["users-list"],
    queryFn: () => apiGet<UserListItem[]>("/api/v1/users/"),
    enabled: dialogOpen,
  });

  // Fetch current assignments for selected project
  const {
    data: assignments,
    isLoading: assignmentsLoading,
  } = useProjectAssignments(selectedProjectId);

  const assignMutation = useAssignForeman();
  const unassignMutation = useUnassignForeman();

  const handleAssign = useCallback(async () => {
    if (!selectedProjectId || !selectedUserId) return;
    try {
      await assignMutation.mutateAsync({
        project_id: selectedProjectId,
        user_id: selectedUserId,
      });
      toast.success("Foreman assigned successfully");
      setDialogOpen(false);
      setSelectedUserId("");
    } catch (err) {
      const message = err instanceof Error ? err.message : "Failed to assign foreman";
      toast.error(message);
    }
  }, [selectedProjectId, selectedUserId, assignMutation]);

  const handleUnassign = useCallback(
    async (assignmentId: string) => {
      try {
        await unassignMutation.mutateAsync(assignmentId);
        toast.success("Foreman removed from project");
      } catch (err) {
        const message = err instanceof Error ? err.message : "Failed to remove foreman";
        toast.error(message);
      }
    },
    [unassignMutation]
  );

  if (!isAdmin) {
    return (
      <div className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center">
        <p className="text-sm text-yellow-700 font-medium">
          You do not have permission to manage foreman assignments.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900 flex items-center gap-2">
          <HardHat className="h-5 w-5" />
          Foreman Assignments
        </h1>
        <p className="text-sm text-gray-500">
          Assign foremen to projects and manage project supervision roles.
        </p>
      </div>

      {/* Project selector */}
      <div className="max-w-md">
        <label htmlFor="project-select" className="block text-sm font-medium text-gray-700 mb-1">
          Select Project
        </label>
        {projectsLoading ? (
          <div className="h-10 animate-pulse rounded-md bg-gray-100" />
        ) : (
          <select
            id="project-select"
            value={selectedProjectId}
            onChange={(e) => setSelectedProjectId(e.target.value)}
            className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="">-- Choose a project --</option>
            {projects?.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        )}
      </div>

      {/* Assignments list */}
      {selectedProjectId && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-base font-medium text-gray-800">
              Assigned Foremen
            </h2>
            <Button
              onClick={() => setDialogOpen(true)}
              size="sm"
              className="gap-1"
            >
              <Plus className="h-4 w-4" />
              Assign Foreman
            </Button>
          </div>

          {assignmentsLoading ? (
            <div className="space-y-3">
              {[...Array(3)].map((_, i) => (
                <div key={i} className="h-16 animate-pulse rounded-lg bg-gray-100" />
              ))}
            </div>
          ) : !assignments || assignments.length === 0 ? (
            <div className="rounded-lg border border-gray-200 bg-gray-50 px-4 py-8 text-center text-sm text-gray-500">
              No foremen assigned to this project yet.
            </div>
          ) : (
            <div className="space-y-2">
              {assignments.map((a) => (
                <div
                  key={a.id}
                  className="flex items-center justify-between rounded-lg border border-gray-200 bg-white px-4 py-3 shadow-sm"
                >
                  <div>
                    <p className="text-sm font-medium text-gray-900">
                      {a.user_name ?? "Unknown User"}
                    </p>
                    <p className="text-xs text-gray-500">
                      Assigned {new Date(a.assigned_at).toLocaleDateString()}
                    </p>
                  </div>
                  <button
                    onClick={() => handleUnassign(a.id)}
                    disabled={unassignMutation.isPending}
                    className="flex items-center gap-1 rounded-md px-2 py-1.5 text-xs text-red-600 hover:bg-red-50 transition-colors disabled:opacity-50"
                    title="Remove assignment"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    Remove
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Assign Foreman Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Assign Foreman</DialogTitle>
            <DialogDescription>
              Select a user to assign as foreman for this project.
            </DialogDescription>
          </DialogHeader>

          <div className="py-4">
            <label htmlFor="user-select" className="block text-sm font-medium text-gray-700 mb-1">
              User
            </label>
            <select
              id="user-select"
              value={selectedUserId}
              onChange={(e) => setSelectedUserId(e.target.value)}
              className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
            >
              <option value="">-- Select a user --</option>
              {users?.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.full_name} ({u.email})
                </option>
              ))}
            </select>
          </div>

          <DialogFooter>
            <DialogClose>
              <Button variant="outline" size="sm">
                Cancel
              </Button>
            </DialogClose>
            <Button
              size="sm"
              onClick={handleAssign}
              disabled={!selectedUserId || assignMutation.isPending}
            >
              {assignMutation.isPending && (
                <Loader2 className="mr-1 h-4 w-4 animate-spin" />
              )}
              Assign
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
