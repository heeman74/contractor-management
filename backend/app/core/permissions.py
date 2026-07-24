"""Permission catalog and default role -> permission mapping.

Single source of truth for the fixed set of granular permission keys and the
default (seed) matrix each company starts with. Companies can toggle which roles
hold which keys (see app/features/rbac), but cannot invent new keys.

Keys are CRUD-granular per resource (view/create/edit/delete) plus a few named
actions (roles.assign, inspections.perform, billing.trade.approve, ...). The role
capability tiers live in app/core/security.py; this module turns those tiers into
concrete permission keys.
"""

from __future__ import annotations

WILDCARD = "*"
PERMISSIONS_MANAGE = "roles.permissions.manage"

# Company-level keys reserved for the owner; admins deliberately do NOT get these.
_OWNER_ONLY_KEYS = ("company.settings.manage", "company.billing.manage")

# Fixed catalog. Each entry is (key, label, group). Order drives UI grouping.
PERMISSION_CATALOG: list[dict[str, str]] = [
    {"key": "company.settings.manage", "label": "Manage company settings", "group": "Company"},
    {"key": "company.billing.manage", "label": "Manage billing & subscription", "group": "Company"},
    {"key": "users.view", "label": "View users", "group": "Access"},
    {"key": "users.create", "label": "Create users", "group": "Access"},
    {"key": "users.edit", "label": "Edit / deactivate users", "group": "Access"},
    {"key": "users.delete", "label": "Delete users", "group": "Access"},
    {"key": "roles.assign", "label": "Assign roles to users", "group": "Access"},
    {"key": PERMISSIONS_MANAGE, "label": "Edit role permissions", "group": "Access"},
    {"key": "projects.view", "label": "View projects", "group": "Projects"},
    {"key": "projects.create", "label": "Create projects", "group": "Projects"},
    {"key": "projects.edit", "label": "Edit projects", "group": "Projects"},
    {"key": "projects.delete", "label": "Delete projects", "group": "Projects"},
    {"key": "jobs.view", "label": "View jobs", "group": "Jobs"},
    {"key": "jobs.create", "label": "Create jobs", "group": "Jobs"},
    {"key": "jobs.edit", "label": "Edit jobs", "group": "Jobs"},
    {"key": "jobs.delete", "label": "Delete jobs", "group": "Jobs"},
    {"key": "jobs.execute", "label": "Update status of assigned jobs", "group": "Jobs"},
    {"key": "schedule.view", "label": "View schedule", "group": "Scheduling"},
    {"key": "schedule.create", "label": "Create bookings", "group": "Scheduling"},
    {"key": "schedule.edit", "label": "Edit schedule & bookings", "group": "Scheduling"},
    {"key": "schedule.delete", "label": "Delete bookings", "group": "Scheduling"},
    {"key": "quotes.view", "label": "View quotes", "group": "Quotes"},
    {"key": "quotes.create", "label": "Create quotes", "group": "Quotes"},
    {"key": "quotes.edit", "label": "Edit & send quotes", "group": "Quotes"},
    {"key": "quotes.delete", "label": "Delete quotes", "group": "Quotes"},
    {"key": "quotes.submit", "label": "Submit quotes for assigned jobs", "group": "Quotes"},
    {"key": "invoices.view", "label": "View invoices", "group": "Invoices"},
    {"key": "invoices.create", "label": "Create invoices", "group": "Invoices"},
    {"key": "invoices.edit", "label": "Edit invoices", "group": "Invoices"},
    {"key": "invoices.finalize", "label": "Finalize / mark invoices", "group": "Invoices"},
    {"key": "invoices.delete", "label": "Delete invoices", "group": "Invoices"},
    {"key": "clients.view", "label": "View clients", "group": "Clients"},
    {"key": "clients.create", "label": "Create clients", "group": "Clients"},
    {"key": "clients.edit", "label": "Edit clients", "group": "Clients"},
    {"key": "clients.delete", "label": "Delete clients", "group": "Clients"},
    {"key": "contracts.manage", "label": "Create & manage contracts", "group": "Operations"},
    {"key": "tasks.view", "label": "View tasks & checklists", "group": "Tasks"},
    {"key": "tasks.create", "label": "Create tasks", "group": "Tasks"},
    {"key": "tasks.edit", "label": "Edit tasks & checklists", "group": "Tasks"},
    {"key": "tasks.delete", "label": "Delete tasks", "group": "Tasks"},
    {"key": "tasks.complete", "label": "Complete assigned checklist items", "group": "Tasks"},
    {"key": "inspections.view", "label": "View inspections", "group": "Inspections"},
    {"key": "inspections.perform", "label": "Approve / reject inspections", "group": "Inspections"},
    {"key": "billing.trade.approve", "label": "Approve per-trade billing", "group": "Construction"},
    {"key": "foreman.assign", "label": "Assign foremen to projects", "group": "Construction"},
    {"key": "time.log", "label": "Log time entries", "group": "Field"},
    {"key": "photos.upload", "label": "Upload job photos", "group": "Field"},
    {"key": "portal.access", "label": "Access client portal", "group": "Portal"},
]

PERMISSION_KEYS: frozenset[str] = frozenset(entry["key"] for entry in PERMISSION_CATALOG)

# Admin gets everything except the owner-only company keys — derived so it can
# never drift from the catalog as keys are added.
_ADMIN_KEYS: list[str] = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS))

DEFAULT_ROLE_PERMISSIONS: dict[str, list[str]] = {
    "owner": [WILDCARD],
    "admin": _ADMIN_KEYS,
    "project_manager": [
        "projects.view",
        "projects.create",
        "projects.edit",
        "projects.delete",
        "jobs.view",
        "jobs.create",
        "jobs.edit",
        "jobs.delete",
        "schedule.view",
        "schedule.create",
        "schedule.edit",
        "schedule.delete",
        "quotes.view",
        "quotes.create",
        "quotes.edit",
        "quotes.delete",
        "invoices.view",
        "invoices.create",
        "invoices.edit",
        "invoices.finalize",
        "clients.view",
        "clients.create",
        "clients.edit",
        "clients.delete",
        "contracts.manage",
        "tasks.view",
        "tasks.create",
        "tasks.edit",
        "tasks.delete",
    ],
    "gc": [
        "projects.view",
        "jobs.view",
        "inspections.view",
        "inspections.perform",
        "billing.trade.approve",
        "foreman.assign",
        "tasks.view",
        "tasks.create",
        "tasks.edit",
        "tasks.delete",
    ],
    "foreman": [
        "projects.view",
        "jobs.view",
        "jobs.execute",
        "tasks.view",
        "tasks.create",
        "tasks.edit",
        "tasks.complete",
        "quotes.submit",
        "time.log",
        "photos.upload",
    ],
    "contractor": [
        "jobs.view",
        "jobs.execute",
        "quotes.view",
        "quotes.submit",
        "tasks.view",
        "tasks.complete",
        "time.log",
        "photos.upload",
    ],
    "worker": [
        "tasks.view",
        "tasks.complete",
        "time.log",
        "photos.upload",
    ],
    "client": ["portal.access"],
}


def expand(keys: list[str]) -> set[str]:
    """Resolve a stored key list to concrete catalog keys.

    A wildcard entry expands to every catalog key; any unknown key is dropped.
    """
    if WILDCARD in keys:
        return set(PERMISSION_KEYS)
    return {key for key in keys if key in PERMISSION_KEYS}
