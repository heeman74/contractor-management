from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.tenant import TenantMiddleware
from app.features.companies.router import router as companies_router
from app.features.users.router import router as users_router

app = FastAPI(
    title="ContractorHub API",
    description="Multi-tenant contractor management platform",
    version="0.1.0",
)

# CORS middleware — configure origins in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Tenant middleware — must be added after CORS
# Reads X-Company-Id header and sets ContextVar for RLS injection
app.add_middleware(TenantMiddleware)

# Feature routers
app.include_router(companies_router, prefix="/api/v1")
app.include_router(users_router, prefix="/api/v1")


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint — returns 200 when server is running."""
    return {"status": "ok", "service": "contractorhub-api"}
