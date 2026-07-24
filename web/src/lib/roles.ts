// Shared source of truth for user roles and coarse capability checks.
// Fine-grained gating uses effective permissions (see lib/hooks/usePermissions).

export const ROLE_SLUGS = [
  "owner",
  "admin",
  "project_manager",
  "gc",
  "foreman",
  "contractor",
  "worker",
  "client",
] as const;

export type Role = (typeof ROLE_SLUGS)[number];

// Internal team/staff roles. Excludes `contractor` and `client`, which are
// created through the dedicated Contractors and Clients pages.
export const STAFF_ROLE_SLUGS = [
  "owner",
  "admin",
  "project_manager",
  "gc",
  "foreman",
  "worker",
] as const satisfies readonly Role[];

export const ROLE_LABELS: Record<Role, string> = {
  owner: "Owner",
  admin: "Admin",
  project_manager: "Project Manager",
  gc: "General Contractor",
  foreman: "Foreman",
  contractor: "Contractor",
  worker: "Worker",
  client: "Client",
};

// Project-level assignment roles (the project_assignments table), distinct from
// user-level roles: includes lead/inspector which aren't user roles.
export const PROJECT_ASSIGNMENT_ROLE_LABELS: Record<string, string> = {
  project_manager: "Project Manager",
  contractor: "Contractor",
  foreman: "Foreman",
  lead: "Lead",
  inspector: "Inspector",
};

// Roles offered in the project-detail assignment picker. Foreman/lead/inspector
// have their own dedicated Foreman Assignments flow.
export const PROJECT_DETAIL_ASSIGNABLE_ROLES = [
  "project_manager",
  "contractor",
] as const;

const ADMIN_ROLES = ["owner", "admin"] as const;
const MANAGER_ROLES = ["owner", "admin", "project_manager"] as const;
const GC_ROLES = ["owner", "admin", "gc"] as const;

export function hasAnyRole(roles: string[], allowed: readonly string[]): boolean {
  return allowed.some((role) => roles.includes(role));
}

export const isOwner = (roles: string[]): boolean => roles.includes("owner");
export const isAdmin = (roles: string[]): boolean => hasAnyRole(roles, ADMIN_ROLES);
export const isManager = (roles: string[]): boolean => hasAnyRole(roles, MANAGER_ROLES);
export const isGc = (roles: string[]): boolean => hasAnyRole(roles, GC_ROLES);
