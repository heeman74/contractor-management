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
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import FastAPI
from sqlalchemy import select

from app.core.ai_utils import AI_CONCURRENCY_LIMIT
from app.core.logging_config import get_logger

logger = get_logger(__name__)

# Module-level scheduler instance — shared across the application
scheduler = AsyncIOScheduler(timezone="UTC")

# Scheduler configuration constants
MORNING_CHECKLIST_HOUR_UTC = 6
ALERT_DETECTION_HOURS_UTC = "7-19"
CHECKLIST_MISFIRE_GRACE_SECONDS = 3600
ALERT_MISFIRE_GRACE_SECONDS = 600


async def _run_for_all_companies(
    job_name: str,
    service_class: type,
    method_name: str,
    target_date: object,
) -> None:
    """Shared pattern: run a service method for every active company.

    Fetches all non-deleted companies, then processes each with bounded concurrency.
    Each company gets its own DB session with tenant context set. Errors per company
    are caught and logged — execution continues to the next company.

    Commit is called explicitly because these sessions are created directly by the
    scheduler, not managed by FastAPI's get_db dependency.
    """
    from app.core.database import async_session_factory
    from app.core.tenant import set_current_tenant_id
    from app.features.companies.models import Company

    logger.info("%s: starting for date %s", job_name, target_date)

    async with async_session_factory() as admin_session:
        try:
            result = await admin_session.execute(
                select(Company).where(Company.deleted_at.is_(None))
            )
            companies = list(result.scalars().all())
        except Exception:
            logger.exception("%s: failed to fetch companies", job_name)
            return

    semaphore = asyncio.Semaphore(AI_CONCURRENCY_LIMIT)

    async def _process_company(company):  # type: ignore[no-untyped-def]
        async with semaphore:
            async with async_session_factory() as db:
                try:
                    set_current_tenant_id(company.id)
                    svc = service_class(db)
                    await getattr(svc, method_name)(company_id=company.id, target_date=target_date)
                    await db.commit()
                    logger.info("%s: completed for company %s", job_name, company.id)
                except Exception:
                    await db.rollback()
                    logger.exception(
                        "%s: failed for company %s — continuing",
                        job_name,
                        company.id,
                    )

    await asyncio.gather(*[_process_company(c) for c in companies])


async def run_morning_checklists() -> None:
    """Cron job: generate AI daily checklists for all contractors across all companies.

    Called at 06:00 UTC daily. Delegates to _run_for_all_companies.
    """
    from app.features.checklists.service import ChecklistService

    today = datetime.now(timezone.utc).date()
    await _run_for_all_companies(
        job_name="run_morning_checklists",
        service_class=ChecklistService,
        method_name="generate_daily_checklists",
        target_date=today,
    )


async def run_alert_detection() -> None:
    """Cron job: detect schedule slips and generate AI alerts for all companies.

    Called every hour from 07:00 to 19:00 UTC. Delegates to _run_for_all_companies.
    """
    from app.features.dashboard.service import DashboardService

    today = datetime.now(timezone.utc).date()
    await _run_for_all_companies(
        job_name="run_alert_detection",
        service_class=DashboardService,
        method_name="detect_schedule_slips",
        target_date=today,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI lifespan context manager — starts and stops APScheduler.

    Wired into FastAPI(lifespan=lifespan) in main.py.
    Starts the scheduler on app startup, shuts it down on shutdown (wait=False
    avoids blocking the process for in-flight job runs during graceful shutdown).
    """
    scheduler.add_job(
        run_morning_checklists,
        trigger=CronTrigger(hour=MORNING_CHECKLIST_HOUR_UTC, minute=0),
        id="morning_checklists",
        replace_existing=True,
        misfire_grace_time=CHECKLIST_MISFIRE_GRACE_SECONDS,
    )

    scheduler.add_job(
        run_alert_detection,
        trigger=CronTrigger(hour=ALERT_DETECTION_HOURS_UTC, minute=0),
        id="alert_detection",
        replace_existing=True,
        misfire_grace_time=ALERT_MISFIRE_GRACE_SECONDS,
    )

    scheduler.start()
    logger.info("APScheduler started with %d jobs", len(scheduler.get_jobs()))

    try:
        yield
    finally:
        scheduler.shutdown(wait=False)
        logger.info("APScheduler shut down")
