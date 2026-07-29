"""ProfitabilityService — the nightly AI profitability analysis (FINAI-01/02).

Three halves live here. The read half fetches and gates; it decides nothing about
margin, because detection is deterministic and lives entirely in
`profitability_math` (D-02), so no threshold, band rule or signal comparison is
restated here. The publish half calls Claude once per candidate and lets nothing
reach the database until `validate_grounding` accepts every figure the model wrote
(D-05, SC3): a finding still citing an unmatched figure after its single retry is
dropped and logged. The alerting half resolves what stopped qualifying, claims
each finding's alert exactly once, and pushes to the live finance.view holder set.

Two orderings in `scan_candidates` are load-bearing:

- The D-01 eligibility gate runs BEFORE any trend replay, which is what keeps the
  scan's statement count O(eligible) rather than O(all projects).
- Every figure the payload carries is read from one batched company-wide read
  (`PortfolioService.all_project_figures`), never from a per-project rollup call
  inside the loop (CLAUDE.md's no-query-in-a-loop rule at company scale).

No run-log table exists in this codebase and no success criterion needs one:
structured logging IS the run log, one line per skip plus one summary per company.

No method here commits — on the scheduler path only `_run_for_all_companies` does.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from app.core.ai_grounding import collect_allowed_values, validate_grounding
from app.core.ai_utils import (
    ClaudeJsonResponse,
    call_claude_json_strict,
    gather_with_concurrency,
)
from app.core.base_service import TenantScopedService
from app.core.logging_config import get_logger
from app.features.dashboard.alert_types import AI_PROFITABILITY_ALERT_TYPE
from app.features.dashboard.models import DashboardAlert
from app.features.dashboard.repository import AlertRepository
from app.features.finance.budget_math import percent_used
from app.features.finance.labor_derivation import ZERO_MONEY
from app.features.finance.margin_math import RevenueAnchor, anchor_revenues
from app.features.finance.portfolio_math import AnchoredBudget, ProjectFinancialFigures
from app.features.finance.portfolio_service import (
    PortfolioInputs,
    PortfolioService,
    ProjectCostBlocks,
    project_cost_blocks,
)
from app.features.finance.profitability_math import (
    SEVERITY_BAND_CRITICAL,
    SEVERITY_BAND_WARNING,
    CandidateSignal,
    DetectionInputs,
    QuoteGapInputs,
    SkipReason,
    candidate_for,
    latest_quote_per_anchor,
    skip_reason_for,
)
from app.features.finance.profitability_models import (
    MAX_ALERT_SUMMARY_LENGTH,
    MAX_CORRECTIVE_ACTION_LENGTH,
    MAX_NARRATIVE_LENGTH,
    AIProfitabilityFinding,
)
from app.features.finance.profitability_repository import FindingUpsert, ProfitabilityRepository
from app.features.finance.prompts.profitability_system import (
    GROUNDING_RETRY_TEMPLATE,
    PROFITABILITY_SYSTEM_PROMPT,
)
from app.features.finance.schemas import CategoryTotal
from app.features.finance.service import contributing_anchor_cost
from app.features.finance.trend_math import TrendBucket

logger = get_logger(__name__)

# Rendered at the call site, not handed to the logger as positional args: this app
# binds structlog to the stdlib bridge, which defers %-formatting to the handler —
# so the values never reach structlog.testing.capture_logs and the run log would be
# unassertable.
SKIP_LOG_TEMPLATE = "ai_profitability: skipped project=%s reason=%s"
SCAN_SUMMARY_LOG_TEMPLATE = "ai_profitability: company=%s analyzed=%d candidates=%d skipped=%d"
TOKEN_USAGE_LOG_TEMPLATE = "ai_profitability: tokens project=%s input=%s output=%s"
DISMISSAL_LOG_TEMPLATE = "ai_profitability: dismissed project=%s reason=%s"
EMPTY_DRAFT_LOG_TEMPLATE = "ai_profitability: dropped textless finding project=%s"
UNGROUNDED_DROP_LOG_TEMPLATE = "ai_profitability: dropped ungrounded finding project=%s figures=%s"
OVER_LENGTH_DROP_LOG_TEMPLATE = "ai_profitability: dropped over-length finding project=%s"
CAP_DROP_LOG_TEMPLATE = "ai_profitability: nightly cap reached project=%s cap=%d"

GROUNDING_RETRY_LIMIT = 1
"""D-05: one VALIDATION retry, and only one.

There is no transport retry on this path — the exponential-backoff envelope is
streaming-only (ai/service.py), so a transient API error surfaces as a raised
candidate that gather_with_concurrency isolates.
"""

PROFITABILITY_MAX_OUTPUT_TOKENS = 1024
"""D-10 per-project ceiling. max_tokens caps OUTPUT only; the input side is bounded
by the aggregates-only payload rule, not by this number."""

MAX_FINDINGS_PER_COMPANY_PER_NIGHT = 10
"""D-10 nightly cap on published findings per company.

Counted in memory over tonight's publishes, after validation — a dropped finding
never spends a slot, and no open-row count is read from the database because the
cap is about what this run alerts, not about history.
"""

LABOR_BASIS_UNBURDENED = "unburdened"
"""D-06: v4.0 labor cost is wage-only, so the basis travels with the payload and
the finding can never present an unburdened figure as a fully loaded one."""

TREND_PAYLOAD_BUCKETS = 2

AI_FINDING_PREFIX = "AI finding — "
SUGGESTED_ACTION_PREFIX = "Suggested action: "
"""The two locked UI-SPEC frame strings.

They are the only byte-assertable part of an alert whose body is AI-written, and
the only place the panel can declare the text's provenance — the finding card's
disclosure line cannot follow the prose into the alert channel.
"""

PUSH_TITLE_BY_BAND: dict[str, str] = {
    SEVERITY_BAND_WARNING: "Margin warning",
    SEVERITY_BAND_CRITICAL: "Margin critical",
}
"""One name per band. The chip label, the push title and the alert severity all
read from here, because the same condition must never carry two names."""

_PROFITABILITY_PUSH_TYPE = "ai_profitability_finding"
_FINANCE_VIEW_PERMISSION = "finance.view"

_PROFITABILITY_PUSH_TASKS: set[asyncio.Task[None]] = set()
"""Module-level registry keeping fire-and-forget push tasks alive until they
finish — asyncio holds only weak references to running tasks."""

type SkippedProject = tuple[uuid.UUID, SkipReason]
type PayloadRow = dict[str, object]


@dataclass(frozen=True)
class ProfitabilityCandidate:
    """One project that reached the AI: its candidate signal and the payload the
    finding will be grounded against.

    `revenue_basis` and `labor_included` are the two honesty columns every finding
    row carries, so the UI can caption an estimate-backed or wage-only figure
    without re-deriving either from the payload.
    """

    candidate: CandidateSignal
    project_name: str
    revenue_basis: str
    labor_included: bool
    payload: dict[str, object]

    @property
    def project_id(self) -> uuid.UUID:
        """The project this candidate speaks for — the detection signal owns the id."""
        return self.candidate.project_id


@dataclass(frozen=True)
class FindingDraft:
    """A validated, publishable finding before it touches the database."""

    narrative: str
    corrective_action: str
    alert_summary: str


@dataclass(frozen=True)
class PublishedFinding:
    """One persisted finding, resolved in the request session so the alerting step
    never has to re-read the ORM.

    `severity_band` carries the DB column's name (not `band`) so the alert payload
    and the row can never be spelled differently.
    """

    finding_id: uuid.UUID
    project_id: uuid.UUID
    fingerprint: str
    severity_band: str
    alert_summary: str
    corrective_action: str


@dataclass(frozen=True)
class PublishResult:
    """Tonight's publish outcome for one company.

    `qualifying_fingerprints` is EVERY candidate's fingerprint — including the ones
    whose Claude call raised, whose draft failed the length contract, and the ones
    the nightly cap dropped. It is the D-06 keep-set: built from `published`
    instead, a transient API failure would resolve a still-true finding, and the
    next successful night would insert a fresh unalerted row and alert a condition
    that never cleared.
    """

    published: list[PublishedFinding]
    qualifying_fingerprints: list[str]


@dataclass(frozen=True)
class FiredFinding:
    """One finding that just alerted — the hand-off to FCM dispatch.

    Resolved in the request session so the background push task receives
    primitives only: the session that produced these values is closed by the time
    the task runs.
    """

    alert_id: uuid.UUID
    finding_id: uuid.UUID
    company_id: uuid.UUID
    project_id: uuid.UUID
    severity: str
    title: str
    body: str


@dataclass(frozen=True)
class _PublishContext:
    """The two run-level values every persisted finding needs."""

    company_id: uuid.UUID
    target_date: date


@dataclass(frozen=True)
class PayloadInputs:
    """Everything one project's payload is assembled from — all already fetched."""

    figures: ProjectFinancialFigures
    candidate: CandidateSignal
    blocks: ProjectCostBlocks
    buckets: Sequence[TrendBucket]


class ProfitabilityService(TenantScopedService[AIProfitabilityFinding]):
    """Nightly AI profitability analysis (FINAI-01/02).

    Detection is deterministic and lives in profitability_math; this service
    fetches, gates, assembles the payload, calls Claude, validates, persists,
    resolves and alerts.
    """

    repository_class = ProfitabilityRepository
    repository: ProfitabilityRepository

    async def analyze_company(self, *, company_id: uuid.UUID, target_date: date) -> None:
        """One company's whole night: publish tonight's findings, then alert (FINAI-02).

        Required signature: the nightly scheduler invokes
        method(company_id=..., target_date=...) with RLS already scoped to the
        company. Never commits — the caller's transaction owns the run, so a
        rollback un-claims every alert with it.

        Resolve-then-claim ordering is load-bearing. The band lives inside the
        fingerprint, so a worsening band is a NEW fingerprint — and the prior
        band's row must resolve in the SAME run, or one condition leaves two open
        findings behind (D-06).
        """
        result = await self.publish_findings(company_id, target_date)
        # The keep-set is every fingerprint that still QUALIFIES tonight, never
        # what published. A candidate is dropped from the publish list when its
        # Claude call raised, when its draft failed the length contract, and when
        # the nightly cap hit — and none of those mean the erosion cleared.
        # Resolving such a row would let the next successful night insert a fresh
        # unalerted row, claim it, and fire a SECOND alert for a condition that
        # never cleared (D-06, RESEARCH Pitfall 6).
        await self.repository.resolve_absent_fingerprints(result.qualifying_fingerprints)
        fired = await self._fire_findings(result.published, company_id)
        if fired:
            self._schedule_profitability_pushes(fired, await self._recipients_for(company_id))

    async def _fire_findings(
        self, published: Sequence[PublishedFinding], company_id: uuid.UUID
    ) -> list[FiredFinding]:
        """Alert every finding that has not alerted yet, in the order they persisted."""
        fired: list[FiredFinding] = []
        for finding in published:
            alerted = await self._fire_finding(finding, company_id)
            if alerted is not None:
                fired.append(alerted)
        return fired

    async def _fire_finding(
        self, published: PublishedFinding, company_id: uuid.UUID
    ) -> FiredFinding | None:
        """Claim this finding's alert and write it; None when it already alerted.

        Claim BEFORE writing the alert (34-03): the read-then-write version
        double-fires under concurrent runs. Nothing has to be resolved ahead of the
        claim here — PublishedFinding already carries its project anchor, read in
        this session off the row that was just persisted — so no claim can be burnt
        on a vanished anchor.
        """
        if await self.repository.claim_alert(published.finding_id) is None:
            return None
        alert = await AlertRepository(self.db).create(_build_alert(published, company_id))
        await self.repository.update(published.finding_id, {"dashboard_alert_id": alert.id})
        return FiredFinding(
            alert_id=alert.id,
            finding_id=published.finding_id,
            company_id=company_id,
            project_id=published.project_id,
            severity=published.severity_band,
            title=PUSH_TITLE_BY_BAND[published.severity_band],
            body=alert.impact_text,  # UI-SPEC: the push body is byte-identical to impact_text
        )

    async def _recipients_for(self, company_id: uuid.UUID) -> list[uuid.UUID]:
        """finance.view holders per the LIVE permission matrix, resolved in the
        current session (RLS + test visibility) before any background task is
        scheduled (D-07).

        Read from the matrix, never from a hard-coded set of role names: FINSEC-02
        lets a company move finance visibility onto any role, and the push has to
        follow that with no code change.
        """
        from app.features.rbac.repository import RbacRepository

        return await RbacRepository(self.db).user_ids_with_permission(
            company_id, _FINANCE_VIEW_PERMISSION
        )

    @staticmethod
    def _schedule_profitability_pushes(
        fired: list[FiredFinding], recipient_ids: list[uuid.UUID]
    ) -> None:
        """Fire-and-forget one FCM push per newly alerted finding (checklists pattern)."""
        for finding in fired:
            task = asyncio.create_task(
                ProfitabilityService._send_profitability_push_safe(
                    company_id=finding.company_id,
                    recipient_ids=recipient_ids,
                    title=finding.title,
                    body=finding.body,
                    data=_push_data(finding),
                )
            )
            _PROFITABILITY_PUSH_TASKS.add(task)
            task.add_done_callback(_PROFITABILITY_PUSH_TASKS.discard)

    @staticmethod
    async def _send_profitability_push_safe(
        company_id: uuid.UUID,
        recipient_ids: list[uuid.UUID],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> None:
        """Send one finding push in its OWN session — the request session is closed
        by the time this task runs (RESEARCH Pitfall 3). Never raises."""
        try:
            from app.core.database import async_session_factory
            from app.core.tenant import set_current_tenant_id
            from app.features.notifications.service import NotificationService

            set_current_tenant_id(company_id)
            async with async_session_factory() as db:
                await NotificationService(db).send_profitability_finding_notification(
                    recipient_ids=recipient_ids, title=title, body=body, data=data
                )
                await db.commit()
        except Exception:
            logger.exception("ai profitability push failed for company %s — continuing", company_id)

    async def scan_candidates(self, company_id: uuid.UUID) -> list[ProfitabilityCandidate]:
        """Every project in this company the AI should write a finding about tonight.

        Deterministic and side-effect free apart from logging: nothing is persisted
        and no Claude call is made here.
        """
        portfolio = PortfolioService(self.db)
        figures, inputs = await portfolio.all_project_figures()
        eligible, skipped = self._partition_by_eligibility(figures)
        self._log_skips(skipped)
        candidates = await self._candidates_for(eligible, inputs, portfolio)
        logger.info(
            SCAN_SUMMARY_LOG_TEMPLATE % (company_id, len(eligible), len(candidates), len(skipped))
        )
        return candidates

    @staticmethod
    def _partition_by_eligibility(
        figures: Sequence[ProjectFinancialFigures],
    ) -> tuple[list[ProjectFinancialFigures], list[SkippedProject]]:
        """Split D-01's verdict: what the AI may analyze, and what it may not, with reasons."""
        eligible: list[ProjectFinancialFigures] = []
        skipped: list[SkippedProject] = []
        for project in figures:
            reason = skip_reason_for(project)
            if reason is None:
                eligible.append(project)
            else:
                skipped.append((project.project_id, reason))
        return eligible, skipped

    @staticmethod
    def _log_skips(skipped: Sequence[SkippedProject]) -> None:
        """Name every excluded project and its reason — a skip is never silent."""
        for project_id, reason in skipped:
            logger.info(SKIP_LOG_TEMPLATE % (project_id, reason.value))

    async def _candidates_for(
        self,
        eligible: Sequence[ProjectFinancialFigures],
        inputs: PortfolioInputs,
        portfolio: PortfolioService,
    ) -> list[ProfitabilityCandidate]:
        """Run detection over the eligible projects only, keeping those that fired."""
        candidates: list[ProfitabilityCandidate] = []
        for figures in eligible:
            candidate = await self._candidate_for_project(figures, inputs, portfolio)
            if candidate is not None:
                candidates.append(candidate)
        return candidates

    async def _candidate_for_project(
        self,
        figures: ProjectFinancialFigures,
        inputs: PortfolioInputs,
        portfolio: PortfolioService,
    ) -> ProfitabilityCandidate | None:
        """One eligible project's candidate, or None when no D-03 signal fired.

        The trend replay is the only per-project read on this path. It is bounded
        (the same profile as the shipped project rollup) and, crucially, it runs
        only for projects the eligibility gate already cleared.
        """
        buckets = await portfolio.unsliced_trend_buckets(figures.project_id)
        blocks = project_cost_blocks(figures.project_id, inputs)
        candidate = candidate_for(
            DetectionInputs(
                figures=figures,
                buckets=buckets,
                quote_gap_inputs=self._quote_gap_inputs(figures, blocks, inputs),
            )
        )
        if candidate is None:
            return None
        return _to_profitability_candidate(
            PayloadInputs(figures=figures, candidate=candidate, blocks=blocks, buckets=buckets)
        )

    @staticmethod
    def _quote_gap_inputs(
        figures: ProjectFinancialFigures, blocks: ProjectCostBlocks, inputs: PortfolioInputs
    ) -> QuoteGapInputs:
        """The three D-03 signal-3 maps, all built from already-fetched rows.

        The anchor-cost map is a dict comprehension over the batched cost rows,
        composing the SHIPPED per-anchor cost predicate — not a query per anchor.
        """
        project_id = figures.project_id
        quote_rows = inputs.quotes.get(project_id, [])
        resolved = anchor_revenues(inputs.invoices.get(project_id, []), quote_rows)
        latest_quotes = latest_quote_per_anchor(quote_rows)
        anchors: set[RevenueAnchor] = resolved.keys() | latest_quotes.keys()
        return QuoteGapInputs(
            resolved=resolved,
            latest_quotes=latest_quotes,
            anchor_costs={
                anchor: contributing_anchor_cost(anchor, blocks.context) for anchor in anchors
            },
        )

    async def publish_findings(self, company_id: uuid.UUID, target_date: date) -> PublishResult:
        """Draft, validate, cap and persist every candidate's finding.

        Per-candidate calls under gather_with_concurrency: the D-10 per-project
        token ceiling stays meaningful, one bad candidate cannot poison the rest,
        and a failed call returns None instead of aborting the company's run.
        """
        candidates = await self.scan_candidates(company_id)
        drafts = await gather_with_concurrency(candidates, self._draft_for)
        published = await self._persist_publishable(
            candidates, drafts, _PublishContext(company_id=company_id, target_date=target_date)
        )
        return PublishResult(
            published=published,
            qualifying_fingerprints=[candidate.candidate.fingerprint for candidate in candidates],
        )

    async def _draft_for(self, candidate: ProfitabilityCandidate) -> FindingDraft | None:
        """One candidate's grounded finding, or None when it is dismissed or ungrounded.

        Validate-and-block with exactly one retry (D-05). A finding still citing a
        figure the payload does not contain on the second attempt is DROPPED and
        logged: never published, never clipped to fit, never partially saved.
        """
        allowed = collect_allowed_values(candidate.payload)
        messages = [_payload_turn(candidate.payload)]
        ungrounded: tuple[str, ...] = ()
        for _attempt in range(GROUNDING_RETRY_LIMIT + 1):
            response = await call_claude_json_strict(
                PROFITABILITY_SYSTEM_PROMPT, messages, max_tokens=PROFITABILITY_MAX_OUTPUT_TOKENS
            )
            _log_token_usage(candidate, response)
            if not response.data.get("confirmed"):
                _log_dismissal(candidate, response.data)
                return None
            draft = _to_draft(response.data)
            if draft is None:
                logger.warning(EMPTY_DRAFT_LOG_TEMPLATE % (candidate.project_id,))
                return None
            ungrounded = _ungrounded_literals(draft, allowed)
            if not ungrounded:
                return draft
            messages = [*messages, *_retry_turns(response.raw_text, ungrounded)]
        logger.warning(UNGROUNDED_DROP_LOG_TEMPLATE % (candidate.project_id, ", ".join(ungrounded)))
        return None

    async def _persist_publishable(
        self,
        candidates: Sequence[ProfitabilityCandidate],
        drafts: Sequence[FindingDraft | None],
        context: _PublishContext,
    ) -> list[PublishedFinding]:
        """Persist the drafts that clear the length contract, up to the nightly cap.

        The cap is checked AFTER both the drafting and the length verdict, so a
        dropped finding never spends one of tonight's slots (RESEARCH Pitfall 6).
        """
        published: list[PublishedFinding] = []
        for candidate, draft in zip(candidates, drafts, strict=True):
            if draft is None:
                continue
            if not _within_length_contract(draft):
                logger.warning(OVER_LENGTH_DROP_LOG_TEMPLATE % (candidate.project_id,))
                continue
            if len(published) >= MAX_FINDINGS_PER_COMPANY_PER_NIGHT:
                logger.info(
                    CAP_DROP_LOG_TEMPLATE
                    % (candidate.project_id, MAX_FINDINGS_PER_COMPANY_PER_NIGHT)
                )
                continue
            published.append(await self._persist(candidate, draft, context))
        return published

    async def _persist(
        self, candidate: ProfitabilityCandidate, draft: FindingDraft, context: _PublishContext
    ) -> PublishedFinding:
        """Upsert one validated finding and resolve what the alerting step will read."""
        finding = await self.repository.upsert_finding(_to_upsert(candidate, draft, context))
        return PublishedFinding(
            finding_id=finding.id,
            project_id=finding.project_id,
            fingerprint=finding.fingerprint,
            severity_band=finding.severity_band,
            alert_summary=finding.alert_summary,
            corrective_action=finding.corrective_action,
        )


def _payload_turn(payload: Mapping[str, object]) -> dict[str, str]:
    """The candidate's payload as the opening user turn.

    default=str renders Decimals as exact strings for the model to read; the
    validator still compares against the original Decimal objects, so no figure
    changes representation on the way to the API.
    """
    return {"role": "user", "content": json.dumps(payload, default=str)}


def _retry_turns(raw_text: str, ungrounded: tuple[str, ...]) -> list[dict[str, str]]:
    """The two turns that continue the conversation into its one retry: the model's
    own reply, then the literals it is not allowed to use."""
    return [
        {"role": "assistant", "content": raw_text},
        {
            "role": "user",
            "content": GROUNDING_RETRY_TEMPLATE.format(unmatched=", ".join(ungrounded)),
        },
    ]


def _to_draft(data: Mapping[str, object]) -> FindingDraft | None:
    """The three AI strings, or None when the model confirmed a finding without writing one.

    The prompt reserves empty strings for a dismissal, so a confirmed reply with
    empty text is malformed — publishing it would ship a blank card and a blank alert.
    """
    draft = FindingDraft(
        narrative=_ai_string(data, "narrative"),
        corrective_action=_ai_string(data, "corrective_action"),
        alert_summary=_ai_string(data, "alert_summary"),
    )
    if not (draft.narrative and draft.corrective_action and draft.alert_summary):
        return None
    return draft


def _ai_string(data: Mapping[str, object], field: str) -> str:
    """One AI text field, read defensively so a null can never reach a NOT NULL column."""
    value = data.get(field)
    return value if isinstance(value, str) else ""


def _ungrounded_literals(draft: FindingDraft, allowed: frozenset[Decimal]) -> tuple[str, ...]:
    """Every figure the draft cites that the payload does not contain, across ALL
    three AI strings — validating only the narrative would let a fabricated figure
    reach the dashboard alert and the push body.

    Deduplicated in first-seen order so the retry turn names each literal once.
    """
    verdicts = (
        validate_grounding(text, allowed)
        for text in (draft.narrative, draft.corrective_action, draft.alert_summary)
    )
    return tuple(dict.fromkeys(literal for verdict in verdicts for literal in verdict.unmatched))


def _log_token_usage(candidate: ProfitabilityCandidate, response: ClaudeJsonResponse) -> None:
    """The run log's cost line — one per Claude turn, the D-05 retry included."""
    logger.info(
        TOKEN_USAGE_LOG_TEMPLATE
        % (candidate.project_id, response.input_tokens, response.output_tokens)
    )


def _log_dismissal(candidate: ProfitabilityCandidate, data: Mapping[str, object]) -> None:
    """An AI dismissal is a normal outcome (D-02), so it is logged with its reason."""
    logger.info(DISMISSAL_LOG_TEMPLATE % (candidate.project_id, data.get("dismissal_reason")))


def _within_length_contract(draft: FindingDraft) -> bool:
    """The D-09/UI-SPEC bounds, checked against the same constants the DB enforces.

    Over-length text is rejected whole rather than shortened to fit: clipping a
    grounded sentence can drop the very figure that justifies it.
    """
    return (
        len(draft.narrative) <= MAX_NARRATIVE_LENGTH
        and len(draft.corrective_action) <= MAX_CORRECTIVE_ACTION_LENGTH
        and len(draft.alert_summary) <= MAX_ALERT_SUMMARY_LENGTH
    )


def _push_data(fired: FiredFinding) -> dict[str, str]:
    """FCM data payload for one alerted finding — every value a string (FCM constraint).

    finding_id travels alongside alert_id so a future mobile findings screen can
    deep-link to the audit trail without a second push contract.
    """
    return {
        "type": _PROFITABILITY_PUSH_TYPE,
        "alert_type": AI_PROFITABILITY_ALERT_TYPE,
        "alert_id": str(fired.alert_id),
        "finding_id": str(fired.finding_id),
        "project_id": str(fired.project_id),
        "severity": fired.severity,
    }


def _build_alert(published: PublishedFinding, company_id: uuid.UUID) -> DashboardAlert:
    """One published finding as its DashboardAlert row, inside the locked frames.

    `severity` is the band itself with no mapping table in between: the band name IS
    the severity value (UI-SPEC), so the two cannot drift. days_behind,
    affected_scope_ids and both rescheduling columns stay empty, and that is exactly
    what lets AlertPanel render this alert type with no schedule line and no
    Accept/Dismiss controls — no component change required.
    """
    return DashboardAlert(
        company_id=company_id,
        project_id=published.project_id,
        trade_scope_id=None,
        severity=published.severity_band,
        alert_type=AI_PROFITABILITY_ALERT_TYPE,
        days_behind=None,
        impact_text=AI_FINDING_PREFIX + published.alert_summary,
        remediation_text=SUGGESTED_ACTION_PREFIX + published.corrective_action,
        affected_scope_ids=[],
        is_read=False,
        rescheduling_payload=None,
        rescheduling_accepted=None,
    )


def _to_upsert(
    candidate: ProfitabilityCandidate, draft: FindingDraft, context: _PublishContext
) -> FindingUpsert:
    """One night's row for this candidate: the AI text, the honesty columns, the audit payload."""
    signal = candidate.candidate
    return FindingUpsert(
        company_id=context.company_id,
        project_id=signal.project_id,
        signal=signal.signal,
        severity_band=signal.band,
        fingerprint=signal.fingerprint,
        narrative=draft.narrative,
        corrective_action=draft.corrective_action,
        alert_summary=draft.alert_summary,
        revenue_basis=candidate.revenue_basis,
        labor_included=candidate.labor_included,
        payload=_jsonb_payload(candidate.payload),
        analyzed_on=context.target_date,
    )


def _jsonb_payload(payload: Mapping[str, object]) -> dict:
    """The payload as JSONB-safe data, Decimals rendered as exact strings.

    The SC3 audit trail must stay re-readable, so every figure the finding was
    validated against is stored verbatim rather than as a lossy float.
    """
    return json.loads(json.dumps(payload, default=str))


def _to_profitability_candidate(inputs: PayloadInputs) -> ProfitabilityCandidate:
    """Wrap one fired candidate with the finding metadata and payload its row carries."""
    labor_cost = _labor_cost(inputs.blocks)
    return ProfitabilityCandidate(
        candidate=inputs.candidate,
        project_name=inputs.figures.name,
        revenue_basis=inputs.figures.margin.revenue_basis,
        labor_included=labor_cost > ZERO_MONEY,
        payload=_build_payload(inputs),
    )


def _build_payload(inputs: PayloadInputs) -> dict[str, object]:
    """The complete, CLOSED value set the finding may cite.

    Aggregates only — never raw cost rows (the PITFALLS performance note). Every
    derived figure the prompt permits is a NAMED field here, because the
    alternative is a validator that searches for derivable arithmetic: unbounded,
    slow, and a hallucination-laundering channel. Decimals stay Decimal so
    collect_allowed_values sees them and payload STRINGS can never become citable
    numbers.

    The honesty counters that ride on the shipped labor and margin blocks — the
    uncosted-time second count and the incomplete-reason list — are deliberately
    left out: D-01 guarantees both are empty for an analyzed project, so either one
    would only ship a citable zero waiting to be fabricated against.
    """
    return {
        **_cost_block(inputs.figures, _labor_cost(inputs.blocks)),
        **_context_block(inputs.figures, inputs.blocks, inputs.buckets),
        **_signal_block(inputs.candidate),
    }


def _cost_block(figures: ProjectFinancialFigures, labor_cost: Decimal) -> dict[str, object]:
    """The headline money block, copied verbatim off the shipped figures."""
    margin = figures.margin
    return {
        "project_name": figures.name,
        "project_status": figures.status,
        "cost": figures.cost,
        "revenue": margin.revenue,
        "revenue_basis": margin.revenue_basis,
        "quoted_revenue_share": figures.quoted_revenue,
        "margin": margin.margin,
        "margin_percent": margin.margin_percent,
        "labor_basis": LABOR_BASIS_UNBURDENED,
        "labor_cost": labor_cost,
    }


def _context_block(
    figures: ProjectFinancialFigures,
    blocks: ProjectCostBlocks,
    buckets: Sequence[TrendBucket],
) -> dict[str, object]:
    """Where the money went, what was budgeted for it, and where the margin is heading."""
    return {
        "categories": _category_rows(blocks.breakdown.categories),
        "budgets": _budget_rows(figures.budgets),
        "trend": _trend_rows(buckets),
    }


def _signal_block(candidate: CandidateSignal) -> dict[str, object]:
    """One named field per citable delta; an absent signal carries None, never a 0."""
    gap = candidate.quote_gap
    return {
        "signal": candidate.signal,
        "severity_band": candidate.band,
        "negative_margin_dollars": candidate.negative_margin_dollars,
        "margin_decline_points": candidate.margin_decline_points,
        "quote_gap_points": None if gap is None else gap.points,
        "billed_margin_percent": None if gap is None else gap.billed_margin_percent,
        "quote_implied_margin_percent": None if gap is None else gap.quote_implied_margin_percent,
        "over_quote_dollars": None if gap is None else gap.over_quote_dollars,
    }


def _category_rows(categories: Sequence[CategoryTotal]) -> list[PayloadRow]:
    """One aggregate per cost category — never the entries behind it."""
    return [{"name": category.category_name, "cost": category.total} for category in categories]


def _budget_rows(budgets: Sequence[AnchoredBudget]) -> list[PayloadRow]:
    """Each budget anchor with its usage precomputed, so the AI derives no percent."""
    return [
        {
            "label": budget.label,
            "spent": budget.spent,
            "total": budget.total,
            "percent_used": percent_used(budget.spent, budget.total),
            "remaining": budget.total - budget.spent,
        }
        for budget in budgets
    ]


def _trend_rows(buckets: Sequence[TrendBucket]) -> list[PayloadRow]:
    """The last cumulative months, the same unsliced buckets detection compared."""
    return [
        {
            "month": bucket.month,
            "cost": bucket.cost,
            "margin_percent": bucket.margin.margin_percent,
        }
        for bucket in buckets[-TREND_PAYLOAD_BUCKETS:]
    ]


def _labor_cost(blocks: ProjectCostBlocks) -> Decimal:
    """The project's derived labor total, legacy labor-category entries folded in."""
    labor = blocks.breakdown.labor
    return ZERO_MONEY if labor is None else labor.total
