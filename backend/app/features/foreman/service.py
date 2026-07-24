"""Service layer for the foreman role feature.

ForemanService inherits TenantScopedService and provides business logic for:
- Assigning/unassigning foremen to projects
- Creating and querying daily status updates
- Validating that users have the contractor role before assignment
- Validating that foremen are assigned to a project before creating status updates

All CLAUDE.md rules apply:
- No db.commit() — get_db handles transaction lifecycle
- No standalone service functions — class methods only
- Use db.flush() when generated IDs needed before commit
"""

from __future__ import annotations

import uuid
from datetime import date

from fastapi import HTTPException, status
from sqlalchemy import select

from app.core.base_service import TenantScopedService, entity_or_404
from app.features.foreman.models import ProjectAssignment, ProjectStatusUpdate
from app.features.foreman.repository import (
    ProjectAssignmentRepository,
    StatusUpdateRepository,
)
from app.features.foreman.schemas import StatusUpdateCreate
from app.features.projects.models import Project
from app.features.users.models import User, UserRole


class ForemanService(TenantScopedService[ProjectAssignment]):
    """Business logic for foreman project assignments and status updates."""

    repository_class = ProjectAssignmentRepository

    # -------------------------------------------------------------------
    # Assignment operations
    # -------------------------------------------------------------------

    async def assign_to_project(
        self, project_id: uuid.UUID, user_id: uuid.UUID
    ) -> ProjectAssignment:
        """Assign a foreman to a project.

        Validates:
        - The user exists and has the 'contractor' role
        - The project exists

        A foreman is a contractor assigned to manage a project — not a separate
        user role. The project_assignments table tracks the project-level role.

        Returns the created/restored ProjectAssignment.

        Raises:
            HTTPException 404: if user or project not found
            HTTPException 400: if user does not have contractor role
        """
        company_id = self._require_tenant_id()

        # Validate user exists
        entity_or_404(await self.db.get(User, user_id), "User not found")

        # Validate user has contractor role (foreman is a project-level role, not user-level)
        role_stmt = (
            select(UserRole)
            .where(UserRole.user_id == user_id)
            .where(UserRole.role == "contractor")
            .where(UserRole.deleted_at.is_(None))
        )
        role_result = await self.db.execute(role_stmt)
        if role_result.scalars().first() is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User does not have the contractor role",
            )

        # Validate project exists
        entity_or_404(await self.db.get(Project, project_id), "Project not found")

        repo = ProjectAssignmentRepository(self.db)
        return await repo.assign(company_id, project_id, user_id, role="foreman")

    async def unassign_from_project(self, assignment_id: uuid.UUID) -> bool:
        """Soft-delete a project assignment.

        Raises:
            HTTPException 404: if assignment not found
        """
        repo = ProjectAssignmentRepository(self.db)
        deleted = await repo.unassign(assignment_id)
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Assignment not found",
            )
        return True

    async def get_project_assignments(self, project_id: uuid.UUID) -> list[ProjectAssignment]:
        """List all active foreman assignments for a project with eager loading."""
        repo = ProjectAssignmentRepository(self.db)
        return await repo.get_by_project(project_id)

    async def get_assigned_projects(self, user_id: uuid.UUID) -> list[ProjectAssignment]:
        """List all projects assigned to a foreman with eager loading."""
        repo = ProjectAssignmentRepository(self.db)
        return await repo.get_by_user(user_id)

    # -------------------------------------------------------------------
    # Status update operations
    # -------------------------------------------------------------------

    async def create_status_update(
        self, data: StatusUpdateCreate, author_id: uuid.UUID
    ) -> ProjectStatusUpdate:
        """Create a daily status update for a project.

        Validates that the author (foreman) is assigned to the project.

        Raises:
            HTTPException 403: if author is not assigned to the project
            HTTPException 404: if project not found
        """
        company_id = self._require_tenant_id()

        # Validate project exists
        entity_or_404(await self.db.get(Project, data.project_id), "Project not found")

        # Validate foreman is assigned to project
        repo = ProjectAssignmentRepository(self.db)
        assigned_project_ids = await repo.get_project_ids_for_user(author_id)
        if data.project_id not in assigned_project_ids:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not assigned to this project as a foreman",
            )

        update = ProjectStatusUpdate(
            company_id=company_id,
            project_id=data.project_id,
            author_id=author_id,
            status_text=data.status_text,
            weather_conditions=data.weather_conditions,
            workers_on_site=data.workers_on_site,
            safety_incidents=data.safety_incidents,
            blockers=data.blockers,
            photos=data.photos,
            report_date=data.report_date or date.today(),
        )
        status_repo = StatusUpdateRepository(self.db)
        return await status_repo.create_update(update)

    async def get_status_updates(
        self, project_id: uuid.UUID, limit: int = 20, offset: int = 0
    ) -> tuple[list[ProjectStatusUpdate], int]:
        """Paginated list of status updates for a project.

        Returns (items, total_count).
        """
        repo = StatusUpdateRepository(self.db)
        return await repo.get_by_project(project_id, limit=limit, offset=offset)

    async def get_latest_status(self, project_id: uuid.UUID) -> ProjectStatusUpdate | None:
        """Get the most recent status update for a project."""
        repo = StatusUpdateRepository(self.db)
        return await repo.get_latest_by_project(project_id)
