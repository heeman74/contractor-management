from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from starlette.types import Scope, Send

from app.core.base_middleware import ASGIMiddleware
from app.core.config import settings
from app.core.logging_config import setup_logging
from app.core.middleware import ExceptionHandlerMiddleware, RequestLoggingMiddleware
from app.core.rate_limit import limiter
from app.core.scheduler import lifespan
from app.core.tenant import TenantMiddleware
from app.features.ai.router import router as ai_router
from app.features.auth.router import router as auth_router
from app.features.billing_milestones.router import router as billing_milestones_router
from app.features.chat.router import router as chat_router
from app.features.checklists.router import router as checklists_router
from app.features.companies.router import router as companies_router
from app.features.dashboard.router import router as dashboard_router
from app.features.files.router import router as files_router
from app.features.foreman.router import router as foreman_router
from app.features.inspection.router import inspection_router
from app.features.invoices.router import router as invoices_router
from app.features.invoices.router import scope_invoice_router
from app.features.jobs.crm_router import router as crm_router
from app.features.jobs.router import router as jobs_router
from app.features.notifications.router import router as notifications_router
from app.features.projects.router import router as projects_router
from app.features.quotes.router import router as quotes_router
from app.features.quotes.router import scope_quote_router
from app.features.reports.router import router as reports_router
from app.features.scheduling.router import router as scheduling_router
from app.features.sync.router import router as sync_router
from app.features.users.router import router as users_router

# ---------------------------------------------------------------------------
# Structured logging — must be configured before any logger is used
# ---------------------------------------------------------------------------
setup_logging()

# Ensure the uploads directory exists on startup
_UPLOADS_DIR = Path("uploads")
_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
# Ensure chat uploads directory exists
_CHAT_UPLOADS_DIR = Path("uploads") / "chat"
_CHAT_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

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
    lifespan=lifespan,
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

# Request logging (after CORS, before tenant — logs timing and sets trace context)
app.add_middleware(RequestLoggingMiddleware)

# Tenant context reset
app.add_middleware(TenantMiddleware)

# Exception handler — outermost middleware, catches unhandled exceptions
app.add_middleware(ExceptionHandlerMiddleware)

# ---------------------------------------------------------------------------
# Feature routers
# ---------------------------------------------------------------------------
app.include_router(auth_router, prefix="/api/v1")
app.include_router(companies_router, prefix="/api/v1")
app.include_router(users_router, prefix="/api/v1")
app.include_router(sync_router, prefix="/api/v1")
app.include_router(scheduling_router, prefix="/api/v1")
app.include_router(jobs_router, prefix="/api/v1")
# Phase 17: CRM client list and detail
app.include_router(crm_router, prefix="/api/v1")
# Phase 6: file upload endpoint for job note attachments
app.include_router(files_router, prefix="/api/v1")
# Phase 7: FCM push notification token registration
app.include_router(notifications_router, prefix="/api/v1")
# Phase 19: project data model — projects, trade catalog, trade scopes, tasks
app.include_router(projects_router, prefix="/api/v1")
# Phase 21: AI intake and interview SSE endpoints
app.include_router(ai_router, prefix="/api/v1")
# Phase 23: real-time chat (WebSocket + REST endpoints)
app.include_router(chat_router, prefix="/api/v1")
# Phase 24: GC inspection workflow — task inspection, site walk flags, punch list items
app.include_router(inspection_router, prefix="/api/v1")
# Phase 25: per-trade billing — billing milestones CRUD under trade scopes
app.include_router(billing_milestones_router, prefix="/api/v1")
# Phase 26: AI daily checklists and GC monitoring dashboard
app.include_router(checklists_router, prefix="/api/v1")
app.include_router(dashboard_router, prefix="/api/v1")
# Phase 8: business operations — quotes, invoices, and reporting
app.include_router(quotes_router, prefix="/api/v1")
app.include_router(invoices_router, prefix="/api/v1")
# Phase 25: trade-scope billing endpoints
app.include_router(scope_quote_router, prefix="/api/v1")
app.include_router(scope_invoice_router, prefix="/api/v1")
app.include_router(reports_router, prefix="/api/v1")
# Foreman role: project assignments and daily status updates
app.include_router(foreman_router, prefix="/api/v1")

# Serve uploaded files (job request photos, note attachments etc.)
# IMPORTANT: StaticFiles mounts MUST be added AFTER all router includes.
# main.py mounts uploads/ at /files so attachment remote_urls (/files/attachments/...) resolve.
app.mount("/uploads", StaticFiles(directory=str(_UPLOADS_DIR)), name="uploads")
# Phase 6: serve attachments at /files/ (uploads/ dir re-mapped to match remote_url prefix)
app.mount("/files", StaticFiles(directory=str(_UPLOADS_DIR)), name="files")
# Phase 23: serve chat attachments at /uploads/chat/
app.mount("/uploads/chat", StaticFiles(directory=str(_CHAT_UPLOADS_DIR)), name="chat-uploads")


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint — returns 200 when server is running."""
    return {"status": "ok", "service": "contractorhub-api"}
