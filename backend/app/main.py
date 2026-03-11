from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from starlette.types import Scope, Send

from app.core.base_middleware import ASGIMiddleware
from app.core.config import settings
from app.core.rate_limit import limiter
from app.core.tenant import TenantMiddleware
from app.features.auth.router import router as auth_router
from app.features.companies.router import router as companies_router
from app.features.files.router import router as files_router
from app.features.jobs.router import router as jobs_router
from app.features.scheduling.router import router as scheduling_router
from app.features.sync.router import router as sync_router
from app.features.users.router import router as users_router

# Ensure the uploads directory exists on startup
_UPLOADS_DIR = Path("uploads")
_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------
app = FastAPI(
    title="ContractorHub API",
    description="Multi-tenant contractor management platform",
    version="0.2.0",
    # Disable Swagger/ReDoc in production
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
)

app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={"detail": "Rate limit exceeded. Try again later."},
    )


# ---------------------------------------------------------------------------
# Security headers middleware
# ---------------------------------------------------------------------------
class SecurityHeadersMiddleware(ASGIMiddleware):
    """Pure ASGI middleware to add security headers to all HTTP responses."""

    async def process_response(self, scope: Scope, send: Send) -> Send:
        if scope["type"] != "http":
            return send

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                extra = [
                    (b"x-content-type-options", b"nosniff"),
                    (b"x-frame-options", b"DENY"),
                    (b"cache-control", b"no-store"),
                    (b"strict-transport-security", b"max-age=63072000; includeSubDomains"),
                ]
                message = {
                    **message,
                    "headers": list(message.get("headers", [])) + extra,
                }
            await send(message)

        return send_with_headers


# ---------------------------------------------------------------------------
# Middleware stack (order matters — Starlette processes in reverse add order)
# ---------------------------------------------------------------------------

# CORS — specific origins from env, restricted methods/headers
cors_origins = settings.cors_origin_list
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins if cors_origins else ["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "Idempotency-Key"],
)

# Security headers
app.add_middleware(SecurityHeadersMiddleware)

# Tenant context reset
app.add_middleware(TenantMiddleware)

# ---------------------------------------------------------------------------
# Feature routers
# ---------------------------------------------------------------------------
app.include_router(auth_router, prefix="/api/v1")
app.include_router(companies_router, prefix="/api/v1")
app.include_router(users_router, prefix="/api/v1")
app.include_router(sync_router, prefix="/api/v1")
app.include_router(scheduling_router, prefix="/api/v1")
app.include_router(jobs_router, prefix="/api/v1")
# Phase 6: file upload endpoint for job note attachments
app.include_router(files_router, prefix="/api/v1")

# Serve uploaded files (job request photos, note attachments etc.)
# IMPORTANT: StaticFiles mounts MUST be added AFTER all router includes.
# main.py mounts uploads/ at /files so attachment remote_urls (/files/attachments/...) resolve.
app.mount("/uploads", StaticFiles(directory=str(_UPLOADS_DIR)), name="uploads")
# Phase 6: serve attachments at /files/ (uploads/ dir re-mapped to match remote_url prefix)
app.mount("/files", StaticFiles(directory=str(_UPLOADS_DIR)), name="files")


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint — returns 200 when server is running."""
    return {"status": "ok", "service": "contractorhub-api"}
