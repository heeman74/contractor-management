"""A generated document must fit the page it is printed on.

The quote and invoice templates sized their content block at 210mm — the FULL
width of A4 — with no @page rule, so WeasyPrint's default page margin pushed
that block off the right edge. The subtotal column and the total were cut in
half in every quote PDF produced.

Declaring the margin on @page rather than as padding on a block also matters for
documents that run past one page: padding on a block that spans two pages insets
only the first, so page two would start hard against the paper edge.

Rendering is stubbed here the way the other PDF tests stub it — the HTML is the
artefact worth asserting on, and WeasyPrint needs system libraries that are not
present in every environment this suite runs in.
"""

import re

import pytest
from httpx import AsyncClient

from tests.quote_client_helpers import ensure_client

QUOTES_URL = "/api/v1/quotes/"


@pytest.fixture
def captured_html(monkeypatch) -> dict:
    """Capture the HTML handed to the renderer instead of producing a PDF."""
    from app.features.pdf.service import PdfService

    captured: dict = {}

    def _capture(html: str) -> bytes:
        captured["html"] = html
        return b"%PDF-1.4 stub"

    monkeypatch.setattr(PdfService, "_html_to_pdf", staticmethod(_capture))
    return captured


async def _quote_with_a_long_description(client: AsyncClient) -> str:
    resp = await client.post(
        QUOTES_URL,
        json={
            "title": "Bathroom renovation",
            "client_id": await ensure_client(client),
            "line_items": [
                {
                    "item_type": "labor",
                    "description": (
                        "Demo of existing tiled shower: tile removal, backer board, "
                        "fixtures, and plumbing trim. Occupied site with tight access."
                    ),
                    "quantity": "16.000",
                    "unit": "hours",
                    "unit_price": "65.00",
                    "sort_order": 0,
                }
            ],
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_quote_pdf_declares_page_margins(tenant_a_client: AsyncClient, captured_html: dict):
    quote_id = await _quote_with_a_long_description(tenant_a_client)

    resp = await tenant_a_client.get(f"{QUOTES_URL}{quote_id}/pdf")
    assert resp.status_code == 200, resp.text

    html = captured_html["html"]
    page_rule = re.search(r"@page\s*\{([^}]*)\}", html)
    assert page_rule is not None, "no @page rule — the document has no declared margin"

    body = page_rule.group(1)
    margin = re.search(r"margin:\s*([^;]+);", body)
    assert margin is not None, "@page declares no margin"
    assert margin.group(1).strip() not in {"0", "0mm", "0pt"}, (
        "a zero page margin prints to the paper edge"
    )


@pytest.mark.asyncio
async def test_quote_content_is_not_the_full_paper_width(
    tenant_a_client: AsyncClient, captured_html: dict
):
    """210mm IS A4. A block that wide cannot also sit inside a margin."""
    quote_id = await _quote_with_a_long_description(tenant_a_client)
    await tenant_a_client.get(f"{QUOTES_URL}{quote_id}/pdf")

    page_block = re.search(r"\.page\s*\{([^}]*)\}", captured_html["html"])
    assert page_block is not None, ".page rule missing"

    width = re.search(r"width:\s*([^;]+);", page_block.group(1))
    if width is not None:
        assert width.group(1).strip() != "210mm", (
            "the content block is the full width of the paper, so any page "
            "margin pushes it off the right edge"
        )
