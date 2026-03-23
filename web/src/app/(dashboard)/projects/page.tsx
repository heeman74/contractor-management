"use client";

import { useState } from "react";
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

export default function ProjectsPage() {
  const { data: projects, isLoading } = useProjects();
  const [selectedNode, setSelectedNode] = useState<SelectedNode | null>(null);
  const [createDialogOpen, setCreateDialogOpen] = useState(false);

  // Collect all scopes and tasks from projects data for lookup
  const allScopes = projects?.flatMap((p) => p.trade_scopes ?? []) ?? [];
  const allTasks = allScopes.flatMap((s) => s.tasks ?? []);

  const selectedProject =
    selectedNode?.type === "project"
      ? projects?.find((p) => p.id === selectedNode.id)
      : null;

  const selectedScope =
    selectedNode?.type === "scope"
      ? allScopes.find((s) => s.id === selectedNode.id)
      : null;

  const selectedTask =
    selectedNode?.type === "task"
      ? allTasks.find((t) => t.id === selectedNode.id)
      : null;

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

  const handleSelectScope = (scopeId: string) => {
    setSelectedNode({ type: "scope", id: scopeId });
  };

  const handleSelectTask = (taskId: string) => {
    setSelectedNode({ type: "task", id: taskId });
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
            (() => {
              // Need to find scope from the trade-scopes query — look in allScopes
              const scope = allScopes.find((s) => s.id === effectiveSelected.id);
              return scope ? (
                <TradeScopeDetail scope={scope} onSelectTask={handleSelectTask} />
              ) : (
                <div className="p-6 text-sm text-gray-500">Loading scope...</div>
              );
            })()
          ) : effectiveSelected.type === "task" ? (
            (() => {
              const task = allTasks.find((t) => t.id === effectiveSelected.id);
              return task ? (
                <TaskDetail task={task} />
              ) : (
                <div className="p-6 text-sm text-gray-500">Loading task...</div>
              );
            })()
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
