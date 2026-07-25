"use client";

import { useState, useCallback } from "react";
import {
  ChevronRight,
  ChevronDown,
  Folder,
  FolderOpen,
  CircleDot,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useTradeScopes, useTasks } from "@/lib/api/projects";
import type {
  ProjectResponse,
  TradeScopeResponse,
  TaskResponse,
} from "@/types/projects";
import { StatusBadge } from "@/components/shared/status-badge";

// The scope/task variants carry the resolved entity so the detail panel can
// render directly from it. The projects-list query does NOT embed scopes/tasks
// (they are lazy-loaded per node), so an id alone can't be resolved downstream.
export type SelectedNode =
  | { type: "project"; id: string }
  | { type: "scope"; id: string; scope: TradeScopeResponse }
  | { type: "task"; id: string; task: TaskResponse };

interface ProjectTreeProps {
  projects: ProjectResponse[];
  selectedNode: SelectedNode | null;
  onSelectNode: (node: SelectedNode) => void;
}

interface ScopeNodeProps {
  scope: TradeScopeResponse;
  selectedNode: SelectedNode | null;
  onSelectNode: (node: SelectedNode) => void;
  expandedScopes: Set<string>;
  onToggleScope: (id: string) => void;
}

function ScopeNode({
  scope,
  selectedNode,
  onSelectNode,
  expandedScopes,
  onToggleScope,
}: ScopeNodeProps) {
  const isExpanded = expandedScopes.has(scope.id);
  const isActive =
    selectedNode?.type === "scope" && selectedNode.id === scope.id;

  const { data: tasks } = useTasks(isExpanded ? scope.id : "");

  return (
    <div>
      <div
        className={cn(
          "flex cursor-pointer items-center gap-1 rounded-md py-1 pl-5 pr-2 text-sm transition-colors",
          isActive
            ? "bg-secondary text-foreground font-medium"
            : "text-gray-700 hover:bg-gray-100"
        )}
        onClick={() => onSelectNode({ type: "scope", id: scope.id, scope })}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            onSelectNode({ type: "scope", id: scope.id, scope });
          }
          if (e.key === "ArrowRight") {
            e.preventDefault();
            if (!isExpanded) onToggleScope(scope.id);
          }
          if (e.key === "ArrowLeft") {
            e.preventDefault();
            if (isExpanded) onToggleScope(scope.id);
          }
        }}
        tabIndex={0}
        role="treeitem"
        aria-selected={isActive}
        aria-expanded={isExpanded}
      >
        <button
          className="flex h-4 w-4 flex-shrink-0 items-center justify-center"
          onClick={(e) => {
            e.stopPropagation();
            onToggleScope(scope.id);
          }}
          aria-label={isExpanded ? "Collapse" : "Expand"}
          tabIndex={-1}
        >
          {isExpanded ? (
            <ChevronDown className="h-3 w-3 text-gray-400" />
          ) : (
            <ChevronRight className="h-3 w-3 text-gray-400" />
          )}
        </button>
        {/* 12px color swatch dot */}
        <span
          className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
          style={{ backgroundColor: scope.trade_color || "#6b7280" }}
          aria-hidden="true"
        />
        <span className="truncate">{scope.trade_name}</span>
      </div>

      {isExpanded && tasks && tasks.length > 0 && (
        <div role="group">
          {tasks.map((task) => {
            const isTaskActive =
              selectedNode?.type === "task" && selectedNode.id === task.id;
            return (
              <div
                key={task.id}
                className={cn(
                  "flex cursor-pointer items-center gap-1.5 rounded-md py-1 pl-10 pr-2 text-sm transition-colors",
                  isTaskActive
                    ? "bg-secondary text-foreground font-medium"
                    : "text-gray-600 hover:bg-gray-100"
                )}
                onClick={() => onSelectNode({ type: "task", id: task.id, task })}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onSelectNode({ type: "task", id: task.id, task });
                  }
                }}
                tabIndex={0}
                role="treeitem"
                aria-selected={isTaskActive}
              >
                <CircleDot className="h-3 w-3 flex-shrink-0 text-gray-400" />
                <span className="truncate">{task.title}</span>
                {task.status === "blocked" && (
                  <StatusBadge status="blocked" size="sm" />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

interface ProjectNodeProps {
  project: ProjectResponse;
  selectedNode: SelectedNode | null;
  onSelectNode: (node: SelectedNode) => void;
  expandedProjects: Set<string>;
  onToggleProject: (id: string) => void;
  expandedScopes: Set<string>;
  onToggleScope: (id: string) => void;
}

function ProjectNode({
  project,
  selectedNode,
  onSelectNode,
  expandedProjects,
  onToggleProject,
  expandedScopes,
  onToggleScope,
}: ProjectNodeProps) {
  const isExpanded = expandedProjects.has(project.id);
  const isActive =
    selectedNode?.type === "project" && selectedNode.id === project.id;

  const { data: scopes } = useTradeScopes(isExpanded ? project.id : "");

  return (
    <div>
      <div
        className={cn(
          "flex cursor-pointer items-center gap-1 rounded-md py-1.5 px-2 text-sm font-medium transition-colors",
          isActive
            ? "bg-secondary text-foreground font-medium"
            : "text-gray-800 hover:bg-gray-100"
        )}
        onClick={() => onSelectNode({ type: "project", id: project.id })}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            onSelectNode({ type: "project", id: project.id });
          }
          if (e.key === "ArrowRight") {
            e.preventDefault();
            if (!isExpanded) onToggleProject(project.id);
          }
          if (e.key === "ArrowLeft") {
            e.preventDefault();
            if (isExpanded) onToggleProject(project.id);
          }
        }}
        tabIndex={0}
        role="treeitem"
        aria-selected={isActive}
        aria-expanded={isExpanded}
      >
        <button
          className="flex h-4 w-4 flex-shrink-0 items-center justify-center"
          onClick={(e) => {
            e.stopPropagation();
            onToggleProject(project.id);
          }}
          aria-label={isExpanded ? "Collapse project" : "Expand project"}
          tabIndex={-1}
        >
          {isExpanded ? (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronRight className="h-4 w-4 text-gray-400" />
          )}
        </button>
        {isExpanded ? (
          <FolderOpen className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
        ) : (
          <Folder className="h-4 w-4 flex-shrink-0 text-gray-400" />
        )}
        <span className="truncate">{project.name}</span>
      </div>

      {isExpanded && scopes && scopes.length > 0 && (
        <div role="group">
          {scopes.map((scope) => (
            <ScopeNode
              key={scope.id}
              scope={scope}
              selectedNode={selectedNode}
              onSelectNode={onSelectNode}
              expandedScopes={expandedScopes}
              onToggleScope={onToggleScope}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function ProjectTree({
  projects,
  selectedNode,
  onSelectNode,
}: ProjectTreeProps) {
  const [expandedProjects, setExpandedProjects] = useState<Set<string>>(
    new Set()
  );
  const [expandedScopes, setExpandedScopes] = useState<Set<string>>(new Set());

  const toggleProject = useCallback((id: string) => {
    setExpandedProjects((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleScope = useCallback((id: string) => {
    setExpandedScopes((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  if (projects.length === 0) {
    return (
      <div className="px-3 py-6 text-center text-sm text-gray-500">
        No projects yet
      </div>
    );
  }

  return (
    <div
      className="space-y-0.5 p-2"
      role="tree"
      aria-label="Project hierarchy"
    >
      {projects.map((project) => (
        <ProjectNode
          key={project.id}
          project={project}
          selectedNode={selectedNode}
          onSelectNode={onSelectNode}
          expandedProjects={expandedProjects}
          onToggleProject={toggleProject}
          expandedScopes={expandedScopes}
          onToggleScope={toggleScope}
        />
      ))}
    </div>
  );
}
