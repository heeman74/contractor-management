import { test, expect, type Page, type Route } from "@playwright/test";

// E2E: AI quote planning — suggest, review, the send gate, and the two variance
// surfaces (FINAI-03/04/05, SC1-SC4, 37-UI-SPEC states 1-54). Follows the
// phase-35/36 recipe: mock /api/proxy, log in through the UI so Redux auth and
// permissions populate, then SPA-navigate.
//
// Every AI-authored sentence is read back off the fixture, never retyped — a
// fixture edit can not leave a stale sentence asserted somewhere else in this
// file. The frame strings the UI-SPEC byte-locks are declared once below.

const QUOTE_FINANCE_PERMISSIONS = [
  "quotes.view",
  "quotes.edit",
  "finance.view",
  "projects.view",
];
/** Quote management WITHOUT finance.view — the Trap 8 half. */
const QUOTE_ONLY_PERMISSIONS = ["quotes.view", "quotes.edit"];

const QUOTE_ID = "quote-ai-1";
const APPROVED_QUOTE_ID = "quote-ai-approved-1";
const JOB_ID = "job-ai-1";
const PROJECT_ID = "proj-ai-1";
const PROJECT_NAME = "Harbor View Rebuild";
const TRADE_NAME = "Roofing";
const CLIENT_NAME = "Dana Reyes";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

interface LineItemFixture {
  id: string;
  quote_id: string;
  item_type: string;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  sort_order: number;
  field: string | null;
  ai_origin: boolean;
  review_state: "unreviewed" | "accepted" | "edited";
  confidence_band: "high" | "medium" | "low" | null;
  basis: string | null;
  suggested_at: string | null;
}

function handBuiltLine(
  overrides: Partial<LineItemFixture> & { id: string; sort_order: number }
): LineItemFixture {
  return {
    quote_id: QUOTE_ID,
    item_type: "material",
    description: "Hand-entered line",
    quantity: "1",
    unit: "ea",
    unit_price: "100.00",
    field: null,
    ai_origin: false,
    review_state: "unreviewed",
    confidence_band: null,
    basis: null,
    suggested_at: null,
    ...overrides,
  };
}

/** The two lines the estimator typed before ever asking for a suggestion. They
 *  must survive every suggest and regenerate in this file untouched. */
const HAND_BUILT_LINES: LineItemFixture[] = [
  handBuiltLine({
    id: "line-hand-1",
    sort_order: 0,
    item_type: "labor",
    description: "Site protection and tear-off staging",
    quantity: "6",
    unit: "hr",
    unit_price: "82.00",
  }),
  handBuiltLine({
    id: "line-hand-2",
    sort_order: 1,
    description: "Dumpster rental",
    quantity: "1",
    unit: "ea",
    unit_price: "540.00",
  }),
];

/** One AI line per band, in the order the bands are asserted. Each basis is a
 *  full sentence citing only figures the payload would have carried. */
const AI_LINES: LineItemFixture[] = [
  {
    id: "line-ai-1",
    quote_id: QUOTE_ID,
    item_type: "labor",
    description: "Tear off and dispose of existing shingle roof",
    quantity: "28",
    unit: "sq",
    unit_price: "165.00",
    sort_order: 2,
    field: TRADE_NAME,
    ai_origin: true,
    review_state: "unreviewed",
    confidence_band: "high",
    basis:
      "Median of $165.00 per sq across 9 invoiced Roofing jobs, whose actual cost ran 11.0% under the quoted price.",
    suggested_at: "2026-07-31T10:00:00Z",
  },
  {
    id: "line-ai-2",
    quote_id: QUOTE_ID,
    item_type: "material",
    description: "Architectural shingles, 30-year",
    quantity: "30",
    unit: "sq",
    unit_price: "312.00",
    sort_order: 3,
    field: TRADE_NAME,
    ai_origin: true,
    review_state: "unreviewed",
    confidence_band: "medium",
    basis: "Median of $312.00 per sq across 5 invoiced Roofing jobs.",
    suggested_at: "2026-07-31T10:00:00Z",
  },
  {
    id: "line-ai-3",
    quote_id: QUOTE_ID,
    item_type: "material",
    description: "Ice and water shield underlayment",
    quantity: "12",
    unit: "roll",
    unit_price: "98.50",
    sort_order: 4,
    field: TRADE_NAME,
    ai_origin: true,
    review_state: "unreviewed",
    confidence_band: "low",
    basis: "Median of $98.50 per roll across 3 invoiced Roofing jobs.",
    suggested_at: "2026-07-31T10:00:00Z",
  },
];

const AI_LINE_COUNT = AI_LINES.length;

/** The bands in fixture order — the chip labels are read off the copy contract
 *  below, so this array only fixes which band each row carries. */
const AI_LINE_BANDS = AI_LINES.map((line) => line.confidence_band);

interface QuoteFixture {
  id: string;
  company_id: string;
  job_id: string | null;
  project_id: string | null;
  trade_scope_id: string | null;
  status: string;
  revision_number: number;
  tax_rate: string;
  discount_type: string | null;
  discount_value: string;
  expiry_date: string;
  sent_at: string | null;
  viewed_at: string | null;
  approved_at: string | null;
  declined_at: string | null;
  decline_reason: string | null;
  decline_detail: string | null;
  admin_notes: string | null;
  line_items: LineItemFixture[];
  subtotal: string;
  discount_amount: string;
  tax_amount: string;
  total: string;
  version: number;
  created_at: string;
  updated_at: string;
}

const DRAFT_QUOTE: QuoteFixture = {
  id: QUOTE_ID,
  company_id: "co-1",
  job_id: JOB_ID,
  project_id: null,
  trade_scope_id: null,
  status: "draft",
  revision_number: 1,
  tax_rate: "8",
  discount_type: null,
  discount_value: "0",
  expiry_date: "2026-09-15",
  sent_at: null,
  viewed_at: null,
  approved_at: null,
  declined_at: null,
  decline_reason: null,
  decline_detail: null,
  admin_notes: null,
  line_items: HAND_BUILT_LINES,
  subtotal: "1032.00",
  discount_amount: "0.00",
  tax_amount: "82.56",
  total: "1114.56",
  version: 1,
  created_at: "2026-07-30T09:00:00Z",
  updated_at: "2026-07-30T09:00:00Z",
};

/** The draft after a successful suggestion: hand-built lines first, then the
 *  three AI lines, every one of them unreviewed. */
const SUGGESTED_QUOTE: QuoteFixture = {
  ...DRAFT_QUOTE,
  line_items: [...HAND_BUILT_LINES, ...AI_LINES],
  version: 2,
};

/** The same quote once the estimator has accepted every suggested line — the
 *  only state from which a send is allowed. */
const REVIEWED_QUOTE: QuoteFixture = {
  ...SUGGESTED_QUOTE,
  line_items: [
    ...HAND_BUILT_LINES,
    ...AI_LINES.map((line) => ({ ...line, review_state: "accepted" as const })),
  ],
  version: 3,
};

const SENT_QUOTE: QuoteFixture = {
  ...REVIEWED_QUOTE,
  status: "sent",
  sent_at: "2026-07-31T11:00:00Z",
  version: 4,
};

const APPROVED_QUOTE: QuoteFixture = {
  ...REVIEWED_QUOTE,
  id: APPROVED_QUOTE_ID,
  status: "approved",
  project_id: PROJECT_ID,
  sent_at: "2026-07-20T09:00:00Z",
  viewed_at: "2026-07-20T14:00:00Z",
  approved_at: "2026-07-21T09:00:00Z",
};

const JOB = {
  id: JOB_ID,
  description: "Harbor View reroof",
  client_name: CLIENT_NAME,
  client_id: "client-1",
  status: "quote",
  company_id: "co-1",
};

/** Actual cost above the quoted price — the over-quoted branch, so the red rule
 *  and the "above" sentence are both exercised. */
const QUOTE_VARIANCE = {
  quoted: "18400.00",
  actual: "19780.00",
  variance: "1380.00",
  variance_percent: "7.5",
  labor_included: true,
  scope_anchored: false,
  trades: [
    {
      label: TRADE_NAME,
      quoted: "18400.00",
      actual: "19780.00",
      variance: "1380.00",
      variance_percent: "7.5",
    },
  ],
};

const PROJECT_QUOTE_VARIANCE = {
  scopes: [
    {
      label: TRADE_NAME,
      quoted: "18400.00",
      actual: "19780.00",
      variance: "1380.00",
      variance_percent: "7.5",
    },
    {
      label: "Framing",
      quoted: "24000.00",
      actual: "22150.00",
      variance: "-1850.00",
      variance_percent: "-7.7",
    },
  ],
  total: {
    label: "Project total",
    quoted: "42400.00",
    actual: "41930.00",
    variance: "-470.00",
    variance_percent: "-1.1",
  },
  labor_included: true,
  has_scope_anchored_rows: false,
};

const SUGGEST_SUCCESS = {
  refusal_reason: null,
  trade_name: TRADE_NAME,
  comparable_count: 9,
  required_count: 5,
  suggested_line_count: AI_LINE_COUNT,
};

/** The cold-start refusal: the counts the notice renders come from this body,
 *  never from a client constant — the threshold has one home, the backend. */
const SUGGEST_COLD_START = {
  refusal_reason: "insufficient_history",
  trade_name: TRADE_NAME,
  comparable_count: 2,
  required_count: 5,
  suggested_line_count: 0,
};

// The drill-down fixtures — only what /financials and /financials/[projectId]
// need to render, so Test 6 can reach the quote-variance card the way a user does.
const PROJECT_MARGIN = {
  revenue: "52000.00",
  revenue_basis: "mixed",
  margin: "6480.00",
  margin_percent: "12.4",
  incomplete: false,
  incomplete_reasons: [] as string[],
};

const PROJECT_COST = "45520.00";

const PROJECT_BUDGET = {
  budget_id: "budget-ai-1",
  total: "50000.00",
  spent: PROJECT_COST,
  remaining: "4480.00",
  percent_used: "91.0",
};

const COMPANY_FINANCIALS = {
  portfolio: {
    cost: PROJECT_COST,
    quoted_revenue: "42400.00",
    incomplete_project_count: 0,
    margin: PROJECT_MARGIN,
  },
  projects: [
    {
      project_id: PROJECT_ID,
      name: PROJECT_NAME,
      status: "active",
      cost: PROJECT_COST,
      margin: PROJECT_MARGIN,
      budget: PROJECT_BUDGET,
    },
  ],
  attention: [
    {
      project_id: PROJECT_ID,
      project_name: PROJECT_NAME,
      project_status: "active",
      tier: "warning",
      anchor_label: PROJECT_NAME,
      spent: "8200.00",
      budget_total: "10000.00",
      percent_used: "82.0",
    },
  ],
};

const PROJECT_FINANCIALS = {
  project_id: PROJECT_ID,
  name: PROJECT_NAME,
  status: "active",
  breakdown: {
    categories: [
      { category_id: "cat-materials", category_name: "Materials", total: "27600.00" },
    ],
    labor: {
      total: "8920.00",
      rated_seconds: 288000,
      unrated_seconds: 0,
      basis: "unburdened",
    },
    labor_tracked_at_job_level: false,
    grand_total: PROJECT_COST,
    margin: PROJECT_MARGIN,
    budget: PROJECT_BUDGET,
  },
  scopes: [
    {
      trade_scope_id: "scope-ai-1",
      trade_name: TRADE_NAME,
      spent: "8200.00",
      budget: {
        budget_id: "budget-ai-2",
        total: "10000.00",
        spent: "8200.00",
        remaining: "1800.00",
        percent_used: "82.0",
      },
    },
  ],
};

const MARGIN_TREND = {
  project_id: PROJECT_ID,
  window: "12m",
  buckets: [{ month: "2026-07", cost: PROJECT_COST, margin: PROJECT_MARGIN }],
};

// ---------------------------------------------------------------------------
// The copy contract — verbatim from 37-UI-SPEC. Frame strings only; the AI's
// own sentences are always read off the fixtures above.
// ---------------------------------------------------------------------------

const SUGGEST_LABEL = "Suggest line items";
const SUGGEST_AGAIN_LABEL = "Suggest again";
const SUGGEST_PENDING_LABEL = "Analyzing history...";
const BAND_CHIP_LABEL = {
  high: "Strong history",
  medium: "Limited history",
  low: "Thin history",
} as const;
const REVIEW_MARKER_UNREVIEWED = "Needs review";
const REVIEW_MARKER_ACCEPTED = "Accepted";
const UNREVIEWED_BANNER_HEADING_PLURAL = `${AI_LINE_COUNT} AI-suggested lines still need review`;
const UNREVIEWED_BANNER_BODY =
  "Accept each line as-is or edit it, then save the draft. A quote can't be sent while any suggested line is unreviewed.";
const SEND_BLOCKED_HEADING = "Review the AI-suggested line items before sending";
const SEND_BLOCKED_BODY = `${AI_LINE_COUNT} suggested lines haven't been accepted or edited yet. The check runs on the server, so a quote can't be sent from any screen until every suggestion is reviewed.`;
const AI_DISCLOSURE_NOTE =
  "AI-suggested from your own completed work — every figure is from your recorded history, never an AI estimate.";
/** D-13 in a sentence: the price comes from what was charged, and the cost leg
 *  is carried separately in each line's basis — never blended into the price. */
const PRICING_BASIS_CAPTION =
  "Suggested prices come from what you charged for comparable work — not from your recorded cost. The cost comparison is in each line's basis.";
const COLD_START_HEADING = `Not enough ${TRADE_NAME} history yet`;
const REGENERATE_DIALOG_TITLE = "Replace unreviewed suggestions?";
const REGENERATE_DIALOG_BODY = `${AI_LINE_COUNT} unreviewed suggestions will be replaced with fresh ones. Lines you've accepted or edited stay exactly as they are.`;
const QUOTE_VARIANCE_FIGURE = "$1,380.00 · 7.5%";
const QUOTE_VARIANCE_INTERPRETATION =
  "Actual cost ran $1,380.00 (7.5%) above this quote's pre-tax price.";
const PROJECT_VARIANCE_TITLE = "Quoted vs Actual by Trade";

/** A bulk control would let an estimator clear the review gate without reading a
 *  single line — the one affordance this phase may never grow. */
const BULK_APPROVE_PATTERN = /accept all|approve all|review all|accept everything/i;

// ---------------------------------------------------------------------------
// Route mocking
// ---------------------------------------------------------------------------

const PROXY_GLOB = "**/api/proxy**";
const PROXY_PATHNAME = "/api/proxy";
const SUGGEST_PATH_MARKER = "/suggest-line-items";
const QUOTE_VARIANCE_PATH_MARKER = "/variance";
const PROJECT_QUOTE_VARIANCE_MARKER = "/financials/quote-variance";
const PERMISSIONS_PATH_MARKER = "/me/permissions";

const NO_ELEMENTS = 0;
const NO_REQUESTS = 0;
const NOT_FOUND_STATUS = 404;
/** Long enough to observe the pending label, short enough not to pace the suite. */
const SUGGEST_LATENCY_MS = 400;

type QuotePhase = "draft" | "suggested" | "reviewed" | "sent";

interface QuoteMockOptions {
  permissions: string[];
  /** The refusal body the suggest route answers with; omit for the happy path. */
  suggestResponse?: typeof SUGGEST_SUCCESS | typeof SUGGEST_COLD_START;
  /** Start the editor with unreviewed suggestions already on the quote. */
  startSuggested?: boolean;
}

interface QuoteMockHandle {
  /** Every path the browser asked the proxy for, in request order. */
  requestedPaths: string[];
  suggestRequestCount: () => number;
}

/**
 * One proxy handler for every route these pages touch, over a small state
 * machine: the suggest call moves the quote from `draft` to `suggested`, the
 * PATCH moves it to `reviewed`, the send to `sent`. That is what makes the
 * refetch after each mutation return what a real backend would return, so the
 * review gate is exercised on data the server "owns" rather than on client state.
 *
 * Branches are ordered most-specific-first: the variance path extends the single
 * quote path, which extends the quote list path.
 */
async function mockQuoteRoutes(
  page: Page,
  options: QuoteMockOptions
): Promise<QuoteMockHandle> {
  const {
    permissions,
    suggestResponse = SUGGEST_SUCCESS,
    startSuggested = false,
  } = options;

  let phase: QuotePhase = startSuggested ? "suggested" : "draft";
  const requestedPaths: string[] = [];

  // Listens on the browser's own request stream rather than inside the route
  // handler, so a request is captured even if a future handler stops matching
  // it. Installed before any navigation.
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.pathname !== PROXY_PATHNAME) return;
    requestedPaths.push(url.searchParams.get("path") ?? "");
  });

  await page.context().addCookies([
    { name: "access_token", value: "mock-token", domain: "localhost", path: "/" },
  ]);

  await page.route("**/api/auth/login", async (route: Route) =>
    route.fulfill({
      json: {
        user_id: "u1",
        company_id: "co-1",
        email: "sarah@ace.com",
        display_name: "Sarah Mitchell",
        company_name: "Ace",
        roles: ["admin"],
      },
    })
  );

  function currentQuote(): QuoteFixture {
    if (phase === "sent") return SENT_QUOTE;
    if (phase === "reviewed") return REVIEWED_QUOTE;
    if (phase === "suggested") return SUGGESTED_QUOTE;
    return DRAFT_QUOTE;
  }

  await page.route(PROXY_GLOB, async (route: Route) => {
    const path = new URL(route.request().url()).searchParams.get("path") ?? "";
    const method = route.request().method();

    if (path.includes(SUGGEST_PATH_MARKER)) {
      if (suggestResponse.suggested_line_count > 0) phase = "suggested";
      await new Promise((resolve) => setTimeout(resolve, SUGGEST_LATENCY_MS));
      return route.fulfill({ json: suggestResponse });
    }
    if (path.endsWith("/send")) {
      phase = "sent";
      return route.fulfill({ json: SENT_QUOTE });
    }
    if (method === "PATCH" && /\/api\/v1\/quotes\/[^/]+$/.test(path)) {
      phase = "reviewed";
      return route.fulfill({ json: REVIEWED_QUOTE });
    }

    if (path.includes(PROJECT_QUOTE_VARIANCE_MARKER)) {
      return route.fulfill({ json: PROJECT_QUOTE_VARIANCE });
    }
    if (path.includes("/financials/trend")) {
      return route.fulfill({ json: MARGIN_TREND });
    }
    if (path.includes("/financials/finding")) {
      return route.fulfill({ json: null });
    }
    if (path.endsWith("/financials") && path.includes("/projects/")) {
      return route.fulfill({ json: PROJECT_FINANCIALS });
    }
    if (path === "/api/v1/financials/company") {
      return route.fulfill({ json: COMPANY_FINANCIALS });
    }

    if (path.endsWith(QUOTE_VARIANCE_PATH_MARKER) && path.includes("/quotes/")) {
      return route.fulfill({ json: QUOTE_VARIANCE });
    }
    if (path.includes("/quotes/templates")) {
      return route.fulfill({ json: [] });
    }
    if (path.includes(`/quotes/${APPROVED_QUOTE_ID}`)) {
      return route.fulfill({ json: APPROVED_QUOTE });
    }
    if (/\/api\/v1\/quotes\/[^/]+$/.test(path)) {
      return route.fulfill({ json: currentQuote() });
    }
    if (path.includes("/quotes")) {
      return route.fulfill({ json: [currentQuote(), APPROVED_QUOTE] });
    }

    if (path.includes("/invoices/for-job/")) {
      return route.fulfill({ status: NOT_FOUND_STATUS, json: { detail: "Not found" } });
    }
    // The quotes list joins its rows against the jobs list for the Job and
    // Client columns, so this must carry the real job rather than the empty
    // collection the shell fallback would return.
    if (path === "/api/v1/jobs/") {
      return route.fulfill({ json: [JOB] });
    }
    if (/\/api\/v1\/jobs\/[^/]+$/.test(path)) {
      return route.fulfill({ json: JOB });
    }
    if (path.includes(PERMISSIONS_PATH_MARKER)) {
      return route.fulfill({ json: { permissions } });
    }
    // Shell chatter (contracts, projects, alerts, counters). Every route above
    // answers with its real shape; this list fallback exists only for the
    // collection endpoints the shell polls, because an object-shaped route
    // answered with [] makes its query error and retry mid-test.
    return route.fulfill({ json: [] });
  });

  return {
    requestedPaths,
    suggestRequestCount: () =>
      requestedPaths.filter((path) => path.includes(SUGGEST_PATH_MARKER)).length,
  };
}

// ---------------------------------------------------------------------------
// Navigation — never a hard goto into a quote or a drill-down
// ---------------------------------------------------------------------------

/**
 * Redux `isAuthenticated` is set only by the login page (the 32-04 lesson), so a
 * hard navigation into any of these routes leaves `usePermissions` disabled and
 * every finance surface correctly denied — a test that would pass with the gate
 * deleted. Log in through the UI, then navigate the way a user does.
 */
async function loginThroughUi(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/email/i).fill("sarah@ace.com");
  await page.locator("#password").fill("password123");
  await page.getByRole("button", { name: /sign in|log in/i }).click();
  await page.waitForURL("http://localhost:3000/");
}

/** Both fixtures hang off the same job, so the row is picked by its status
 *  badge — the one column that tells the draft and the approved quote apart. */
async function openQuoteFromSidebar(
  page: Page,
  quoteId: string,
  statusLabel: "draft" | "approved"
) {
  await loginThroughUi(page);
  await page.getByRole("link", { name: "Quotes" }).click();
  await page.waitForURL(/\/quotes$/);

  const row = page
    .getByRole("row")
    .filter({ hasText: CLIENT_NAME })
    .filter({ has: page.getByText(new RegExp(`^${statusLabel}$`, "i")) });
  await row.click();
  await page.waitForURL(new RegExp(`/quotes/${quoteId}$`));
}

async function openEditorFromDetail(page: Page, quoteId: string) {
  await page.getByRole("button", { name: "Edit" }).click();
  await page.waitForURL(new RegExp(`/quotes/${quoteId}/edit$`));
}

function aiSubRows(page: Page) {
  return page.locator('[data-testid^="ai-line-sub-row-"]');
}

function acceptButtons(page: Page) {
  return page.locator('[data-testid^="accept-line-"]');
}

/** The field-array index each AI line renders under — the hand-built lines come
 *  first, so the AI rows are never 0-based. */
function aiRowIndex(position: number): number {
  return HAND_BUILT_LINES.length + position;
}

// ---------------------------------------------------------------------------
// Test 1 — SC1: suggest → review → blocked send → review-all → send
// ---------------------------------------------------------------------------

test("suggest, review each line, then send once nothing is unreviewed", async ({
  page,
}) => {
  const mock = await mockQuoteRoutes(page, {
    permissions: QUOTE_FINANCE_PERMISSIONS,
  });

  await openQuoteFromSidebar(page, QUOTE_ID, "draft");
  await openEditorFromDetail(page, QUOTE_ID);

  const trigger = page.getByTestId("suggest-line-items-trigger");
  await expect(trigger).toBeEnabled();
  await expect(trigger).toHaveText(SUGGEST_LABEL);
  await expect(page.getByTestId("suggest-trigger-reason")).toHaveCount(NO_ELEMENTS);

  await trigger.click();

  // The pending label replaces the trigger's own text and the control is
  // disabled while the mutation is in flight — a second click can not queue a
  // second generation over the first one's result.
  await expect(trigger).toHaveText(SUGGEST_PENDING_LABEL);
  await expect(trigger).toBeDisabled();

  await expect(aiSubRows(page)).toHaveCount(AI_LINE_COUNT);

  for (const [position, line] of AI_LINES.entries()) {
    const index = aiRowIndex(position);
    const band = AI_LINE_BANDS[position]!;
    await expect(page.getByTestId(`confidence-chip-${index}`)).toHaveText(
      BAND_CHIP_LABEL[band]
    );
    await expect(page.getByTestId(`line-basis-${index}`)).toHaveText(line.basis!);
    await expect(page.getByTestId(`review-marker-${index}`)).toHaveText(
      REVIEW_MARKER_UNREVIEWED
    );
  }

  const banner = page.getByTestId("unreviewed-banner");
  await expect(banner).toContainText(UNREVIEWED_BANNER_HEADING_PLURAL);
  await expect(banner).toContainText(UNREVIEWED_BANNER_BODY);

  // The caption stack: pricing basis, the unburdened-labor note (the fixture
  // carries an AI labor line), and the disclosure last.
  await expect(page.getByTestId("quote-pricing-basis-note")).toHaveText(
    PRICING_BASIS_CAPTION
  );
  await expect(page.getByTestId("quote-labor-note")).toBeVisible();
  await expectDisclosureIsTheLastCaption(page);

  // One Accept per line and no way to clear them all at once.
  await expect(acceptButtons(page)).toHaveCount(AI_LINE_COUNT);
  await expect(
    page.getByRole("button", { name: BULK_APPROVE_PATTERN })
  ).toHaveCount(NO_ELEMENTS);

  // The send gate, on the page that owns the send. Nothing was accepted yet.
  await page.getByRole("button", { name: "Discard Changes" }).click();
  await page.waitForURL(new RegExp(`/quotes/${QUOTE_ID}$`));

  const sendBlocked = page.getByTestId("send-blocked-alert");
  await expect(sendBlocked).toContainText(SEND_BLOCKED_HEADING);
  await expect(sendBlocked).toContainText(SEND_BLOCKED_BODY);

  const sendButton = page.getByRole("button", { name: "Send Quote" });
  await expect(sendButton).toBeDisabled();
  await expect(sendButton).toHaveAttribute("aria-describedby", "send-blocked-alert");
  await expect(page.locator("#send-blocked-alert")).toBeVisible();

  // Review every line the way the gate demands — one at a time.
  await openEditorFromDetail(page, QUOTE_ID);
  for (let position = 0; position < AI_LINE_COUNT; position += 1) {
    await page.getByTestId(`accept-line-${aiRowIndex(position)}`).click();
  }
  await expect(acceptButtons(page)).toHaveCount(NO_ELEMENTS);
  await expect(page.getByTestId(`review-marker-${aiRowIndex(0)}`)).toHaveText(
    REVIEW_MARKER_ACCEPTED
  );

  await page.getByRole("button", { name: "Save Draft" }).click();
  await page.waitForURL(new RegExp(`/quotes/${QUOTE_ID}$`));

  await expect(page.getByTestId("send-blocked-alert")).toHaveCount(NO_ELEMENTS);
  const unblockedSend = page.getByRole("button", { name: "Send Quote" });
  await expect(unblockedSend).toBeEnabled();
  await unblockedSend.click();

  await page.getByRole("button", { name: /^Send( Quote)?$/ }).last().click();

  // The quote is genuinely sent: its status badge flips and the send control it
  // was gating is gone — not merely some element somewhere reading "sent".
  await expect(page.getByText(/^sent$/i).first()).toBeVisible();
  await expect(page.getByRole("button", { name: "Send Quote" })).toHaveCount(
    NO_ELEMENTS
  );

  // The suggestion was generated exactly once across the whole flow: neither
  // navigation nor the save re-ran it.
  expect(mock.suggestRequestCount()).toBe(1);
});

/** The disclosure qualifies every caption above it, so nothing is ever appended
 *  below it. */
async function expectDisclosureIsTheLastCaption(page: Page) {
  const disclosure = page.getByTestId("quote-ai-disclosure");
  await expect(disclosure).toHaveText(AI_DISCLOSURE_NOTE);

  const hasCaptionBelowIt = await disclosure.evaluate(
    (node) => node.nextElementSibling !== null
  );
  expect(hasCaptionBelowIt).toBe(false);
}

// ---------------------------------------------------------------------------
// Test 2 — the cold-start refusal
// ---------------------------------------------------------------------------

test("a trade without enough history refuses in the estimator's own numbers", async ({
  page,
}) => {
  await mockQuoteRoutes(page, {
    permissions: QUOTE_FINANCE_PERMISSIONS,
    suggestResponse: SUGGEST_COLD_START,
  });

  await openQuoteFromSidebar(page, QUOTE_ID, "draft");
  await openEditorFromDetail(page, QUOTE_ID);

  const rowsBefore = await page.locator("tbody tr").count();
  await page.getByTestId("suggest-line-items-trigger").click();

  const notice = page.getByTestId("suggestion-notice");
  await expect(notice).toContainText(COLD_START_HEADING);
  // Both counts are rendered from the response, never from a client constant —
  // the threshold has exactly one home, and it is the backend's.
  await expect(notice).toContainText(String(SUGGEST_COLD_START.required_count));
  await expect(notice).toContainText(String(SUGGEST_COLD_START.comparable_count));

  await expect(aiSubRows(page)).toHaveCount(NO_ELEMENTS);
  await expect(page.getByTestId("unreviewed-banner")).toHaveCount(NO_ELEMENTS);
  expect(await page.locator("tbody tr").count()).toBe(rowsBefore);
});

// ---------------------------------------------------------------------------
// Test 3 — regenerating asks before it replaces
// ---------------------------------------------------------------------------

test("regenerating over unreviewed lines asks first and cancels cleanly", async ({
  page,
}) => {
  const mock = await mockQuoteRoutes(page, {
    permissions: QUOTE_FINANCE_PERMISSIONS,
    startSuggested: true,
  });

  await openQuoteFromSidebar(page, QUOTE_ID, "draft");
  await openEditorFromDetail(page, QUOTE_ID);

  const trigger = page.getByTestId("suggest-line-items-trigger");
  await expect(trigger).toHaveText(SUGGEST_AGAIN_LABEL);
  await trigger.click();

  const dialog = page.getByRole("dialog");
  await expect(dialog).toContainText(REGENERATE_DIALOG_TITLE);
  await expect(dialog).toContainText(REGENERATE_DIALOG_BODY);

  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(dialog).toHaveCount(NO_ELEMENTS);

  // Cancel means cancel: the confirmation is what runs the mutation, so a
  // dismissed dialog must leave the suggestion route untouched.
  expect(mock.suggestRequestCount()).toBe(NO_REQUESTS);
  await expect(aiSubRows(page)).toHaveCount(AI_LINE_COUNT);
});

// ─── The Trap 8 keystone. Read this before changing either assertion below. ───
//
// Both halves are load-bearing:
//
//   1. The card's absence. `FinanceGate` renders `fallback={null}` here, so a
//      viewer without finance.view sees no card AND no deny panel — a sidebar
//      card they may not be entitled to must never announce its own absence on
//      a page they otherwise own.
//   2. The zero request count on /quotes/*/variance. `FinanceGate` stops the
//      render; the hook's `enabled: can(FINANCE_VIEW_PERMISSION)` stops the
//      fetch.
//
// The gate short-circuits the mount, so the request half is only observable
// once the render half is already broken — which is what makes `enabled` a
// second independent lock rather than a restatement of the first. The proof
// that `enabled` holds on its own lives in the hook's jest test
// (quote-variance-gate.test.tsx), which renders the section outside the gate.
//
// Do NOT drop either half, and do NOT relax this into a permitted-user check.
test("a quotes-only user sees no variance card, no deny panel and issues zero variance requests", async ({
  page,
}) => {
  const mock = await mockQuoteRoutes(page, {
    permissions: QUOTE_ONLY_PERMISSIONS,
  });

  await openQuoteFromSidebar(page, APPROVED_QUOTE_ID, "approved");

  await expect(page.getByTestId("quote-variance")).toHaveCount(NO_ELEMENTS);
  await expect(page.getByTestId("financials-deny-panel")).toHaveCount(NO_ELEMENTS);

  // The rest of the sidebar still renders, so the two assertions above can not
  // be passing because the page failed to load.
  await expect(page.getByText("Financial Summary")).toBeVisible();
  await expect(page.getByRole("button", { name: "Download PDF" })).toBeVisible();

  const varianceRequests = mock.requestedPaths.filter(
    (path) => path.includes("/quotes/") && path.endsWith(QUOTE_VARIANCE_PATH_MARKER)
  );
  expect(varianceRequests).toHaveLength(NO_REQUESTS);
});

// ---------------------------------------------------------------------------
// Test 5 — the permitted quote-variance card
// ---------------------------------------------------------------------------

test("a finance holder sees quoted vs actual on the approved quote", async ({
  page,
}) => {
  const mock = await mockQuoteRoutes(page, {
    permissions: QUOTE_FINANCE_PERMISSIONS,
  });

  await openQuoteFromSidebar(page, APPROVED_QUOTE_ID, "approved");

  await expect(page.getByTestId("quote-variance")).toBeVisible();
  await expect(page.getByTestId("quote-variance-figure")).toHaveText(
    QUOTE_VARIANCE_FIGURE
  );
  await expect(page.getByTestId("quote-variance-interpretation")).toHaveText(
    QUOTE_VARIANCE_INTERPRETATION
  );

  // The mirror image of the denial keystone: a permitted user DOES fetch the
  // variance, so the zero counter in the test above means the gate held rather
  // than that the route stopped being requested at all.
  const varianceRequests = mock.requestedPaths.filter(
    (path) => path.includes("/quotes/") && path.endsWith(QUOTE_VARIANCE_PATH_MARKER)
  );
  expect(varianceRequests.length).toBeGreaterThan(NO_REQUESTS);
});

// ---------------------------------------------------------------------------
// Test 6 — the drill-down's per-trade table
// ---------------------------------------------------------------------------

test("the project drill-down renders quoted vs actual by trade with a total row", async ({
  page,
}) => {
  await mockQuoteRoutes(page, { permissions: QUOTE_FINANCE_PERMISSIONS });

  await loginThroughUi(page);
  await page.getByRole("link", { name: "Financials" }).click();
  await page.waitForURL(/\/financials$/);
  await page.getByTestId(`attention-row-${PROJECT_ID}`).click();
  await page.waitForURL(new RegExp(`/financials/${PROJECT_ID}$`));

  // The title belongs to the ChartCard wrapper; the testid marks the table it
  // wraps, so the two are asserted on their own elements.
  const chartCard = page.locator(`[aria-label="${PROJECT_VARIANCE_TITLE} chart"]`);
  await expect(chartCard).toBeVisible();
  await expect(chartCard).toContainText(PROJECT_VARIANCE_TITLE);

  const card = page.getByTestId("project-quote-variance");
  await expect(card).toBeVisible();

  for (const scope of PROJECT_QUOTE_VARIANCE.scopes) {
    await expect(card).toContainText(scope.label);
  }
  await expect(page.getByTestId("project-quote-variance-total")).toBeVisible();
});
