"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { X } from "lucide-react";
import { toast } from "sonner";
import { apiGet } from "@/lib/api-client";
import {
  assignToProject,
  unassignFromProject,
  useProjectAssignments,
} from "@/lib/api/projects";
import { usePermissions } from "@/lib/hooks/usePermissions";
import {
  PROJECT_ASSIGNMENT_ROLE_LABELS,
  PROJECT_DETAIL_ASSIGNABLE_ROLES,
} from "@/lib/roles";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { UserResponse } from "@/types/api";

function userLabel(user: UserResponse): string {
  const name = `${user.first_name ?? ""} ${user.last_name ?? ""}`.trim();
  return name || user.email;
}

function roleLabel(role: string): string {
  return PROJECT_ASSIGNMENT_ROLE_LABELS[role] ?? role;
}

export function ProjectAssignmentsCard({ projectId }: { projectId: string }) {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canEdit = can("projects.edit");

  const { data: assignments } = useProjectAssignments(projectId);
  const { data: users } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<UserResponse[]>("/api/v1/users/"),
    enabled: canEdit,
  });

  const [role, setRole] = useState<string>("");
  const [userId, setUserId] = useState<string>("");

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: ["project-assignments", projectId] });

  const assignMutation = useMutation({
    mutationFn: () => assignToProject(projectId, { user_id: userId, role }),
    onSuccess: () => {
      toast.success("Assigned to project");
      setUserId("");
      setRole("");
      invalidate();
    },
    onError: (err: Error) => {
      const detail = "detail" in err ? (err as { detail: string }).detail : err.message;
      toast.error(detail || "Failed to assign", { duration: Infinity });
    },
  });

  const removeMutation = useMutation({
    mutationFn: (assignmentId: string) => unassignFromProject(projectId, assignmentId),
    onSuccess: invalidate,
    onError: (err: Error) => toast.error(err.message || "Failed to remove"),
  });

  const canSubmit = Boolean(role && userId) && !assignMutation.isPending;

  return (
    <div>
      <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-700">
        Team ({assignments?.length ?? 0})
      </h3>

      {assignments && assignments.length > 0 ? (
        <ul className="mb-3 space-y-2">
          {assignments.map((a) => (
            <li
              key={a.id}
              className="flex items-center justify-between gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2"
            >
              <span className="flex items-center gap-2 text-sm text-gray-900">
                {a.user_name}
                <Badge className="bg-gray-100 text-gray-700 border-0">
                  {roleLabel(a.role)}
                </Badge>
              </span>
              {canEdit && (
                <button
                  type="button"
                  aria-label={`Remove ${a.user_name}`}
                  className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-700"
                  onClick={() => removeMutation.mutate(a.id)}
                  disabled={removeMutation.isPending}
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-3 text-sm text-gray-500">No one assigned yet.</p>
      )}

      {canEdit && (
        <div className="flex flex-wrap items-center gap-2">
          <Select value={role} onValueChange={(v) => setRole(v ?? "")}>
            <SelectTrigger className="w-[170px] text-sm" aria-label="Role">
              <SelectValue placeholder="Role..." />
            </SelectTrigger>
            <SelectContent>
              {PROJECT_DETAIL_ASSIGNABLE_ROLES.map((r) => (
                <SelectItem key={r} value={r}>
                  {roleLabel(r)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          <Select value={userId} onValueChange={(v) => setUserId(v ?? "")}>
            <SelectTrigger className="w-[220px] text-sm" aria-label="User">
              <SelectValue placeholder="Select a person..." />
            </SelectTrigger>
            <SelectContent>
              {(users ?? []).map((u) => (
                <SelectItem key={u.id} value={u.id}>
                  {userLabel(u)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          <Button
            size="sm"
            onClick={() => assignMutation.mutate()}
            disabled={!canSubmit}
          >
            {assignMutation.isPending ? "Assigning..." : "Assign"}
          </Button>
        </div>
      )}
    </div>
  );
}
