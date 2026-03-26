"""APScheduler setup with FastAPI lifespan integration.

Two cron jobs:
1. run_morning_checklists — 06:00 UTC daily, generates AI daily checklists per contractor
2. run_alert_detection — every hour 07:00–19:00 UTC, detects schedule slips and generates alerts

Both jobs iterate over all active companies, creating their own DB sessions per company.
Errors per company are logged and execution continues to the next company.

The `lifespan` async context manager is wired into FastAPI(lifespan=lifespan) in main.py.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import FastAPI
from sqlalchemy import select

logger = logging.getLogger(__name__)

# Module-level scheduler instance — shared across the application
scheduler = AsyncIOScheduler(timezone="UTC")


async def run_morning_checklists() -> None:
    """Cron job: generate AI daily checklists for all contractors across all companies.

    Called at 06:00 UTC daily. For each company, queries active projects and generates
    per-contractor checklists via ChecklistService. Fires FCM push after generation.

    Each company runs in its own DB session with tenant context set.
    Errors per company are caught and logged — execution continues to next company.

    SCALE-4: Companies are processed with bounded concurrency via asyncio.Semaphore(5).
    """
    from app.core.database import async_session_factory
    from app.core.tenant import set_current_tenant_id
    from app.features.checklists.service import ChecklistService
    from app.features.companies.models import Company

    # BUG-6: Use UTC date instead of server-local date.today()
    today = datetime.now(timezone.utc).date()
    logger.info("run_morning_checklists: starting for date %s", today)

    # Fetch all companies in a separate session (no RLS for admin-level iteration)
    async with async_session_factory() as admin_session:
        try:
            result = await admin_session.execute(
                select(Company).where(Company.deleted_at.is_(None))
            )
            companies = list(result.scalars().all())
        except Exception:
            logger.exception("run_morning_checklists: failed to fetch companies")
            return

    # SCALE-4: Bounded concurrency for company processing
    semaphore = asyncio.Semaphore(5)

    async def _process_company(company):  # type: ignore[no-untyped-def]
        async with semaphore:
            async with async_session_factory() as db:
                try:
                    set_current_tenant_id(company.id)
                    svc = ChecklistService(db)
                    await svc.generate_daily_checklists(
                        company_id=company.id, target_date=today
                    )
                    # BP-5: db.commit() is called here because these sessions are created
                    # directly by the scheduler (not managed by FastAPI's get_db dependency),
                    # so there is no auto-commit middleware. We must commit explicitly.
                    await db.commit()
                    logger.info(
                        "run_morning_checklists: completed for company %s", company.id
                    )
                except Exception:
                    await db.rollback()
                    logger.exception(
                        "run_morning_checklists: failed for company %s — continuing",
                        company.id,
                    )

    await asyncio.gather(*[_process_company(c) for c in companies])


async def run_alert_detection() -> None:
    """Cron job: detect schedule slips and generate AI alerts for all companies.

    Called every hour from 07:00 to 19:00 UTC. For each company, queries active projects
    and generates DashboardAlert records for any trade scopes that are behind schedule.

    Each company runs in its own DB session with tenant context set.
    Errors per company are caught and logged — execution continues to next company.

    SCALE-4: Companies are processed with bounded concurrency via asyncio.Semaphore(5).
    """
    from app.core.database import async_session_factory
    from app.core.tenant import set_current_tenant_id
    from app.features.companies.models import Company
    from app.features.dashboard.service import DashboardService

    # BUG-6: Use UTC date instead of server-local date.today()
    today = datetime.now(timezone.utc).date()
    logger.info("run_alert_detection: starting for date %s", today)

    async with async_session_factory() as admin_session:
        try:
            result = await admin_session.execute(
                select(Company).where(Company.deleted_at.is_(None))
            )
            companies = list(result.scalars().all())
        except Exception:
            logger.exception("run_alert_detection: failed to fetch companies")
            return

    # SCALE-4: Bounded concurrency for company processing
    semaphore = asyncio.Semaphore(5)

    async def _process_company(company):  # type: ignore[no-untyped-def]
        async with semaphore:
            async with async_session_factory() as db:
                try:
                    set_current_tenant_id(company.id)
                    svc = DashboardService(db)
                    await svc.detect_schedule_slips(
                        company_id=company.id, target_date=today
                    )
                    # BP-5: db.commit() is called here because these sessions are created
                    # directly by the scheduler (not managed by FastAPI's get_db dependency),
                    # so there is no auto-commit middleware. We must commit explicitly.
                    await db.commit()
                    logger.info(
                        "run_alert_detection: completed for company %s", company.id
                    )
                except Exception:
                    await db.rollback()
                    logger.exception(
                        "run_alert_detection: failed for company %s — continuing",
                        company.id,
                    )

    await asyncio.gather(*[_process_company(c) for c in companies])


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan context manager — starts and stops APScheduler.

    Wired into FastAPI(lifespan=lifespan) in main.py.
    Starts the scheduler on app startup, shuts it down on shutdown (wait=False
    avoids blocking the process for in-flight job runs during graceful shutdown).
    """
    # Register morning checklist job: 06:00 UTC daily
    scheduler.add_job(
        run_morning_checklists,
        trigger=CronTrigger(hour=6, minute=0),
        id="morning_checklists",
        replace_existing=True,
        misfire_grace_time=3600,  # Allow up to 1 hour late if server was down
    )

    # Register alert detection job: every hour from 07:00 to 19:00 UTC
    scheduler.add_job(
        run_alert_detection,
        trigger=CronTrigger(hour="7-19", minute=0),
        id="alert_detection",
        replace_existing=True,
        misfire_grace_time=600,  # Allow up to 10 minutes late
    )

    scheduler.start()
    logger.info("APScheduler started with %d jobs", len(scheduler.get_jobs()))

    try:
        yield
    finally:
        scheduler.shutdown(wait=False)
        logger.info("APScheduler shut down")
