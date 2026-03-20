"use client";

import { useState } from "react";
import { Plus, Calendar, MapPin, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/shared/status-badge";
import { AddTradeScopeSheet } from "./AddTradeScopeSheet";
import { useTradeScopes } from "@/lib/api/projects";
import type { ProjectResponse } from "@/types/projects";

interface ProjectDetailProps {
  project: ProjectResponse;
  onSelectScope: (scopeId: string) => void;
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

      {/* Trade scopes summary */}
      <div>
        <h3 className="mb-3 text-sm font-semibold text-gray-700 uppercase tracking-wide">
          Trade Scopes ({scopes?.length ?? 0})
        </h3>
        {scopes && scopes.length > 0 ? (
          <div className="space-y-2">
            {scopes.map((scope) => (
              <div
                key={scope.id}
                className="flex cursor-pointer items-center gap-3 rounded-lg border border-gray-200 bg-white p-3 transition-colors hover:bg-gray-50"
                onClick={() => onSelectScope(scope.id)}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelectScope(scope.id);
                  }
                }}
              >
                <span
                  className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
                  style={{ backgroundColor: scope.trade_color || "#6b7280" }}
                  aria-hidden="true"
                />
                <span className="flex-1 text-sm font-medium text-gray-800">
                  {scope.trade_name}
                </span>
                <StatusBadge status={scope.status} size="sm" />
              </div>
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
