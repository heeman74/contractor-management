"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Plus, Bot } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useProjects } from "@/lib/api/projects";
import { ProjectTree } from "./components/ProjectTree";
import { ProjectDetail } from "./components/ProjectDetail";
import { TradeScopeDetail } from "./components/TradeScopeDetail";
import { TaskDetail } from "./components/TaskDetail";
import { CreateProjectDialog } from "./components/CreateProjectDialog";
import type { SelectedNode } from "./components/ProjectTree";
import type { TradeScopeResponse, TaskResponse } from "@/types/projects";

export default function ProjectsPage() {
  return (
    <Suspense fallback={<div className="p-6" />}>
      <ProjectsContent />
    </Suspense>
  );
}

function ProjectsContent() {
  const { data: projects, isLoading } = useProjects();
  const searchParams = useSearchParams();
  // A ?project=<id> param (e.g. from the AI-intake redirect) opens that project
  // pre-selected in the detail panel.
  const preselectedProjectId = searchParams.get("project");
  const [selectedNode, setSelectedNode] = useState<SelectedNode | null>(
    preselectedProjectId ? { type: "project", id: preselectedProjectId } : null
  );
  const [createDialogOpen, setCreateDialogOpen] = useState(false);

  // Auto-select first project on initial load
  const displayProjects = projects ?? [];
  const effectiveSelected: SelectedNode | null =
    selectedNode ??
    (displayProjects.length > 0
      ? { type: "project", id: displayProjects[0].id }
      : null);

  const effectiveProject =
    effectiveSelected?.type === "project"
      ? displayProjects.find((p) => p.id === effectiveSelected.id) ?? null
      : null;

  const handleSelectNode = (node: SelectedNode) => setSelectedNode(node);

  const handleSelectScope = (scope: TradeScopeResponse) => {
    setSelectedNode({ type: "scope", id: scope.id, scope });
  };

  const handleSelectTask = (task: TaskResponse) => {
    setSelectedNode({ type: "task", id: task.id, task });
  };

  return (
    <div className="flex h-full flex-col">
      {/* Page header */}
      <div className="flex items-center justify-between border-b border-gray-200 px-4 py-3">
        <h1 className="text-xl font-semibold text-gray-900">Projects</h1>
        <div className="flex items-center gap-2">
          <Link
            href="/projects/new/ai-intake"
            className="inline-flex h-7 items-center gap-1 rounded-[min(var(--radius-md),12px)] border border-border bg-background px-2.5 text-[0.8rem] font-medium text-foreground transition-colors hover:bg-muted"
          >
            <Bot className="h-3.5 w-3.5" />
            New AI Project
          </Link>
          <Button
            size="sm"
            onClick={() => setCreateDialogOpen(true)}
            data-testid="create-project-button"
          >
            <Plus className="h-4 w-4" />
            New Project
          </Button>
        </div>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* Left: project tree sidebar (280px) */}
        <div className="w-[280px] flex-shrink-0 overflow-y-auto border-r border-gray-200 bg-white">
          {isLoading ? (
            <div className="space-y-2 p-3">
              {[...Array(4)].map((_, i) => (
                <Skeleton key={i} className="h-8 w-full rounded-md" />
              ))}
            </div>
          ) : (
            <ProjectTree
              projects={displayProjects}
              selectedNode={effectiveSelected}
              onSelectNode={handleSelectNode}
            />
          )}
        </div>

        {/* Right: detail panel */}
        <div className="flex-1 overflow-y-auto bg-gray-50">
          {isLoading ? (
            <div className="space-y-4 p-6">
              <Skeleton className="h-8 w-64" />
              <Skeleton className="h-4 w-96" />
              <Skeleton className="h-32 w-full" />
            </div>
          ) : effectiveSelected === null ? (
            <div className="flex h-full items-center justify-center">
              <div className="text-center">
                <p className="text-sm font-medium text-gray-900">No projects yet</p>
                <p className="mt-1 text-sm text-gray-500">
                  Create your first project to get started.
                </p>
                <Button
                  className="mt-4"
                  onClick={() => setCreateDialogOpen(true)}
                >
                  <Plus className="h-4 w-4" />
                  New Project
                </Button>
              </div>
            </div>
          ) : effectiveSelected.type === "project" && effectiveProject ? (
            <ProjectDetail
              project={effectiveProject}
              onSelectScope={handleSelectScope}
            />
          ) : effectiveSelected.type === "scope" ? (
            <TradeScopeDetail
              scope={effectiveSelected.scope}
              onSelectTask={handleSelectTask}
            />
          ) : effectiveSelected.type === "task" ? (
            <TaskDetail
              task={effectiveSelected.task}
              onTaskDeleted={() => setSelectedNode(null)}
            />
          ) : null}
        </div>
      </div>

      <CreateProjectDialog
        open={createDialogOpen}
        onOpenChange={setCreateDialogOpen}
      />
    </div>
  );
}
