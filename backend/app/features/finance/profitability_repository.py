"""ProfitabilityRepository — persistence for AI profitability findings.

The nightly analysis writes every finding through this repository. It owns three
lifecycle guarantees that analysis depends on:

- The nightly re-run is an idempotent UPSERT on the OPEN (company_id, fingerprint)
  pair, so a still-true problem restates its text instead of piling up rows.
- Alerting is claim-first: one atomic UPDATE decides whether this caller is the
  one that gets to publish the alert. A restatement never re-arms it.
- A problem that stops being true is RESOLVED, and a resolved problem that recurs
  inserts a fresh, unalerted row (D-06) — which is also how a worsening severity
  band re-fires, since the band is part of the fingerprint.

No method commits: on the scheduler path only _run_for_all_companies commits
(CLAUDE.md).

Decision IDs (D-nn) used below resolve in
.planning/phases/36-ai-profitability-analysis/36-CONTEXT.md.
"""

from __future__ import annotations

import uuid
from collections.abc import Collection
from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.core.base_repository import TenantScopedRepository
from app.features.finance.profitability_models import AIProfitabilityFinding

# Matches the ux_ai_profitability_findings_open partial unique index predicate.
# PostgreSQL only infers that index as the ON CONFLICT arbiter when the
# predicate is spelled identically.
_OPEN_ROW_INDEX_PREDICATE = text("deleted_at IS NULL AND resolved_at IS NULL")

_OPEN_ROW_CRITERIA = (
    AIProfitabilityFinding.deleted_at.is_(None),
    AIProfitabilityFinding.resolved_at.is_(None),
)


@dataclass(frozen=True)
class FindingUpsert:
    """One night's finding for a single (company, fingerprint) pair.

    A single argument instead of twelve (CLAUDE.md: 3 args max). analyzed_on is
    the night the analysis ran — it seeds found_on on an insert and advances
    last_confirmed_on on a restatement.
    """

    company_id: uuid.UUID
    project_id: uuid.UUID
    signal: str
    severity_band: str
    fingerprint: str
    narrative: str
    corrective_action: str
    alert_summary: str
    revenue_basis: str
    labor_included: bool
    payload: dict
    analyzed_on: date


class ProfitabilityRepository(TenantScopedRepository[AIProfitabilityFinding]):
    """Findings persistence: idempotent nightly upsert, claim-first alerting,
    resolve-then-reinsert lifecycle (D-06)."""

    model = AIProfitabilityFinding

    async def upsert_finding(self, values: FindingUpsert) -> AIProfitabilityFinding:
        """Insert a finding, or restate the open one carrying the same fingerprint.

        alerted_at and found_on are DELIBERATELY absent from the update set: a
        silent nightly restatement must never re-arm the alert or rewrite the
        date the problem was first discovered.
        """
        statement = (
            pg_insert(AIProfitabilityFinding)
            .values(
                company_id=values.company_id,
                project_id=values.project_id,
                signal=values.signal,
                severity_band=values.severity_band,
                fingerprint=values.fingerprint,
                narrative=values.narrative,
                corrective_action=values.corrective_action,
                alert_summary=values.alert_summary,
                revenue_basis=values.revenue_basis,
                labor_included=values.labor_included,
                payload=values.payload,
                found_on=values.analyzed_on,
                last_confirmed_on=values.analyzed_on,
            )
            .on_conflict_do_update(
                index_elements=["company_id", "fingerprint"],
                index_where=_OPEN_ROW_INDEX_PREDICATE,
                set_={
                    "narrative": values.narrative,
                    "corrective_action": values.corrective_action,
                    "alert_summary": values.alert_summary,
                    "payload": values.payload,
                    "revenue_basis": values.revenue_basis,
                    "labor_included": values.labor_included,
                    "last_confirmed_on": values.analyzed_on,
                },
            )
            .returning(AIProfitabilityFinding)
        )
        result = await self.db.execute(statement)
        await self.db.flush()
        return result.scalars().first()  # type: ignore[return-value]

    async def claim_alert(self, finding_id: uuid.UUID) -> uuid.UUID | None:
        """Atomically claim the right to publish this finding's alert.

        An ``UPDATE ... WHERE alerted_at IS NULL`` returning the id is the entire
        exactly-once mechanism: no locks, no unique index, no unique-violation
        catching. Returns None when the alert was already claimed — the caller
        must then NOT create an alert.
        """
        statement = (
            update(AIProfitabilityFinding)
            .where(
                AIProfitabilityFinding.id == finding_id,
                AIProfitabilityFinding.alerted_at.is_(None),
            )
            .values(alerted_at=func.now())
            .returning(AIProfitabilityFinding.id)
            .execution_options(synchronize_session=False)
        )
        result = await self.db.execute(statement)
        claimed_id = result.scalar_one_or_none()
        if claimed_id is not None:
            await self._expire_alerted_at(finding_id)
        return claimed_id

    async def _expire_alerted_at(self, finding_id: uuid.UUID) -> None:
        """Expire the in-session row's alerted_at after the claim, so a later
        reader in this session cannot serve the stale pre-claim NULL."""
        finding = await self.db.get(AIProfitabilityFinding, finding_id)
        if finding is not None:
            self.db.expire(finding, ["alerted_at"])

    async def resolve_absent_fingerprints(self, keep: Collection[str]) -> int:
        """Resolve every open finding whose fingerprint is not in the keep-set.

        One statement; RLS scopes it to the current tenant. This is what makes a
        worsening band re-fire: the prior band's fingerprint is absent from
        tonight's keep-set, so its row resolves in the same run and the new
        band's fingerprint inserts fresh with alerted_at NULL.

        Returns how many findings were resolved.
        """
        statement = update(AIProfitabilityFinding).where(*_OPEN_ROW_CRITERIA)
        if keep:
            statement = statement.where(AIProfitabilityFinding.fingerprint.notin_(keep))
        statement = statement.values(resolved_at=func.now()).execution_options(
            synchronize_session=False
        )
        result = await self.db.execute(statement)
        await self.db.flush()
        return result.rowcount

    async def latest_open_for_project(self, project_id: uuid.UUID) -> AIProfitabilityFinding | None:
        """The newest unresolved, non-deleted finding for a project, or None."""
        statement = (
            select(AIProfitabilityFinding)
            .where(AIProfitabilityFinding.project_id == project_id, *_OPEN_ROW_CRITERIA)
            .order_by(AIProfitabilityFinding.created_at.desc())
            .limit(1)
        )
        result = await self.db.execute(statement)
        return result.scalars().first()
