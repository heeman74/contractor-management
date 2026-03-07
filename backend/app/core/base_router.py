"""Base router with CRUD endpoint generation.

All new routers MUST use CRUDRouter or follow the base router pattern.
Auth router stays custom due to its unique flows.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.base_schemas import BaseResponseSchema
from app.core.base_service import BaseService
from app.core.database import get_db
from app.core.security import CurrentUser, get_current_user


class CRUDRouter:
    """Mixin that generates standard CRUD endpoints.

    Subclasses set class attributes (prefix, tags, service_class, etc.)
    and override _register_routes() to pick which endpoints to include.
    """

    prefix: str
    tags: list[str]
    service_class: type[BaseService]
    create_schema: type[BaseModel]
    update_schema: type[BaseModel] | None = None
    response_schema: type[BaseResponseSchema]

    def __init__(self) -> None:
        self.router = APIRouter(prefix=self.prefix, tags=self.tags)
        self._register_routes()

    def _register_routes(self) -> None:
        """Override to customize which CRUD endpoints are registered."""
        self._register_create()
        self._register_list()
        if self.update_schema is not None:
            self._register_get()
            self._register_update()

    @staticmethod
    def _not_found(detail: str = "Not found") -> None:
        """Raise a 404 HTTPException."""
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)

    def _register_create(self) -> None:
        svc_cls = self.service_class
        resp_schema = self.response_schema

        async def create_endpoint(
            data: self.create_schema,  # type: ignore[valid-type]
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ):
            svc = svc_cls(db)
            entity = await svc.create(data)
            return resp_schema.model_validate(entity)

        self.router.add_api_route(
            "/",
            create_endpoint,
            methods=["POST"],
            response_model=self.response_schema,
            status_code=status.HTTP_201_CREATED,
        )

    def _register_list(self) -> None:
        svc_cls = self.service_class
        resp_schema = self.response_schema

        async def list_endpoint(
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ):
            svc = svc_cls(db)
            entities = await svc.list()
            return [resp_schema.model_validate(e) for e in entities]

        self.router.add_api_route(
            "/",
            list_endpoint,
            methods=["GET"],
            response_model=list[self.response_schema],
        )

    def _register_get(self) -> None:
        svc_cls = self.service_class
        resp_schema = self.response_schema
        not_found = self._not_found

        async def get_endpoint(
            entity_id: uuid.UUID,
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ):
            svc = svc_cls(db)
            entity = await svc.get(entity_id)
            if entity is None:
                not_found()
            return resp_schema.model_validate(entity)

        self.router.add_api_route(
            "/{entity_id}",
            get_endpoint,
            methods=["GET"],
            response_model=self.response_schema,
        )

    def _register_update(self) -> None:
        svc_cls = self.service_class
        resp_schema = self.response_schema
        not_found = self._not_found

        async def update_endpoint(
            entity_id: uuid.UUID,
            data: self.update_schema,  # type: ignore[valid-type]
            db: AsyncSession = Depends(get_db),
            _current_user: CurrentUser = Depends(get_current_user),
        ):
            svc = svc_cls(db)
            entity = await svc.update(entity_id, data)
            if entity is None:
                not_found()
            return resp_schema.model_validate(entity)

        self.router.add_api_route(
            "/{entity_id}",
            update_endpoint,
            methods=["PATCH"],
            response_model=self.response_schema,
        )
