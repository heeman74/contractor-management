"""PDF generation service using WeasyPrint and Jinja2 templates.

PdfService renders Jinja2 HTML templates with quote/invoice context and
converts them to PDF bytes using WeasyPrint, running in a thread pool
executor to avoid blocking the async event loop.

WeasyPrint requires system libraries (libpango, libcairo) — the service
raises a clear RuntimeError at call time if these are unavailable rather
than crashing at import time.

Usage:
    pdf_service = PdfService()
    pdf_bytes = await pdf_service.generate_quote_pdf(quote, company)
    pdf_bytes = await pdf_service.generate_invoice_pdf(invoice, company)
"""

import asyncio
import logging
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

logger = logging.getLogger(__name__)

# Path to the Jinja2 templates directory (sibling of this file)
_TEMPLATES_DIR = Path(__file__).parent / "templates"


class PdfService:
    """Stateless PDF generation service for quotes and invoices.

    Instantiate once at application startup (or on demand — no DB dependency).
    Thread-safe: the WeasyPrint HTML conversion is run in a thread pool executor.
    """

    def __init__(self) -> None:
        self._env = Environment(
            loader=FileSystemLoader(str(_TEMPLATES_DIR)),
            autoescape=select_autoescape(["html"]),
        )

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------

    def _render_html(self, template_name: str, context: dict) -> str:
        """Render a Jinja2 template with the given context."""
        template = self._env.get_template(template_name)
        return template.render(**context)

    @staticmethod
    def _html_to_pdf(html: str) -> bytes:
        """Convert an HTML string to PDF bytes via WeasyPrint.

        Runs synchronously — callers must wrap in run_in_executor.
        Raises RuntimeError if WeasyPrint system libraries are not installed.
        """
        try:
            from weasyprint import HTML  # type: ignore[import-not-found]
        except ImportError as exc:
            msg = (
                "WeasyPrint could not be imported. "
                "Install system dependencies (libpango, libcairo) and re-install WeasyPrint. "
                "See: https://doc.courtbouillon.org/weasyprint/stable/first_steps.html"
            )
            raise RuntimeError(msg) from exc

        try:
            return HTML(string=html).write_pdf()
        except Exception as exc:
            logger.exception("WeasyPrint PDF generation failed")
            raise RuntimeError(f"PDF generation failed: {exc}") from exc

    @staticmethod
    def _compute_totals(
        line_items: list,
        tax_rate: Decimal,
        discount_type: str | None,
        discount_value: Decimal,
    ) -> tuple[Decimal, Decimal, Decimal, Decimal]:
        """Compute subtotal, discount_amount, tax_amount, total from line items.

        Returns: (subtotal, discount_amount, tax_amount, total)
        """
        subtotal = sum(
            (Decimal(str(item.quantity)) * Decimal(str(item.unit_price)) for item in line_items),
            Decimal("0"),
        )

        if discount_type == "percent":
            discount_amount = (subtotal * Decimal(str(discount_value)) / Decimal("100")).quantize(
                Decimal("0.01")
            )
        elif discount_type == "fixed":
            discount_amount = min(Decimal(str(discount_value)), subtotal)
        else:
            discount_amount = Decimal("0")

        taxable = subtotal - discount_amount
        tax_amount = (taxable * Decimal(str(tax_rate)) / Decimal("100")).quantize(Decimal("0.01"))
        total = taxable + tax_amount

        return subtotal, discount_amount, tax_amount, total

    # -------------------------------------------------------------------------
    # Public async API
    # -------------------------------------------------------------------------

    async def generate_quote_pdf(self, quote: object, company: object) -> bytes:
        """Generate a PDF for a quote.

        Args:
            quote:   Quote ORM instance — quote.line_items must be eagerly loaded.
            company: Company ORM instance — provides branding (name, address, phone).

        Returns:
            PDF bytes suitable for streaming as application/pdf response.
        """
        line_items = getattr(quote, "line_items", [])
        subtotal, discount_amount, tax_amount, total = self._compute_totals(
            line_items=line_items,
            tax_rate=Decimal(str(getattr(quote, "tax_rate", 0))),
            discount_type=getattr(quote, "discount_type", None),
            discount_value=Decimal(str(getattr(quote, "discount_value", 0))),
        )

        # Attempt to resolve client info from quote's job
        client_name: str | None = None
        client_address: str | None = None
        job = getattr(quote, "_job_context", None)  # may be pre-resolved by caller
        if job is None:
            # Caller can pre-set _job_context; without it, client info is omitted gracefully
            pass

        context = {
            "quote": quote,
            "company": company,
            "line_items": line_items,
            "client_name": client_name,
            "client_address": client_address,
            "subtotal": subtotal,
            "discount_amount": discount_amount,
            "tax_amount": tax_amount,
            "total": total,
            "generated_at": datetime.now(UTC).strftime("%d %B %Y %H:%M UTC"),
        }

        html = self._render_html("quote.html", context)
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._html_to_pdf, html)

    async def generate_invoice_pdf(self, invoice: object, company: object) -> bytes:
        """Generate a PDF for an invoice.

        Args:
            invoice: Invoice ORM instance — invoice.line_items must be eagerly loaded.
            company: Company ORM instance — provides branding (name, address, phone).

        Returns:
            PDF bytes suitable for streaming as application/pdf response.
        """
        line_items = getattr(invoice, "line_items", [])
        subtotal, discount_amount, tax_amount, total = self._compute_totals(
            line_items=line_items,
            tax_rate=Decimal(str(getattr(invoice, "tax_rate", 0))),
            discount_type=getattr(invoice, "discount_type", None),
            discount_value=Decimal(str(getattr(invoice, "discount_value", 0))),
        )

        # Check if overdue: unpaid invoice past its due date
        due_date = getattr(invoice, "due_date", None)
        status = getattr(invoice, "status", "unpaid")
        is_overdue = (
            due_date is not None and status != "paid" and due_date < datetime.now(UTC).date()
        )

        client_name: str | None = None
        client_address: str | None = None

        context = {
            "invoice": invoice,
            "company": company,
            "line_items": line_items,
            "client_name": client_name,
            "client_address": client_address,
            "subtotal": subtotal,
            "discount_amount": discount_amount,
            "tax_amount": tax_amount,
            "total": total,
            "is_overdue": is_overdue,
            "generated_at": datetime.now(UTC).strftime("%d %B %Y %H:%M UTC"),
        }

        html = self._render_html("invoice.html", context)
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(None, self._html_to_pdf, html)


# Module-level singleton — no DB dependency, safe to instantiate at import time
pdf_service = PdfService()
