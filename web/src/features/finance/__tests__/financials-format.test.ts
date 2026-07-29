import {
  BUDGET_TIER_FILL,
  BULLET_ROW_HEIGHT,
  CHART_HEIGHT,
  LABEL_TRUNCATE_LENGTH,
  MAX_PIE_SLICES,
  OTHER_CATEGORY_NAME,
  PERCENT_AXIS_CLAMP,
  PERCENT_AXIS_FLOOR,
} from "@/components/shared/chart-theme";
import {
  axisMaxDomain,
  budgetTierFill,
  bulletChartHeight,
  clampPercentForAxis,
  formatAxisThousands,
  formatMonthLabel,
  rollUpCategories,
  truncateLabel,
} from "../financials-format";

describe("formatMonthLabel", () => {
  it("renders a YYYY-MM bucket as an abbreviated month and two-digit year", () => {
    expect(formatMonthLabel("2026-03")).toBe("Mar 26");
  });

  it("keeps January and December on the right side of the year boundary", () => {
    // A Date-based formatter shifts a date-only string across timezones (32-03).
    expect(formatMonthLabel("2026-01")).toBe("Jan 26");
    expect(formatMonthLabel("2025-12")).toBe("Dec 25");
  });
});

describe("formatAxisThousands", () => {
  it("renders thousands with the dollar symbol", () => {
    expect(formatAxisThousands(12000)).toBe("$12k");
  });

  it("puts the sign before the symbol for negative money", () => {
    expect(formatAxisThousands(-4000)).toBe("-$4k");
  });
});

describe("truncateLabel", () => {
  it("caps a long name at the truncation length with an ellipsis", () => {
    const truncated = truncateLabel("A very long project name here");
    expect(truncated).toBe("A very long project n…");
    expect(truncated).toHaveLength(LABEL_TRUNCATE_LENGTH);
  });

  it("returns a name at exactly the truncation length unchanged", () => {
    const exact = "Riverside Fitout 22ch".padEnd(LABEL_TRUNCATE_LENGTH, "x");
    expect(exact).toHaveLength(LABEL_TRUNCATE_LENGTH);
    expect(truncateLabel(exact)).toBe(exact);
  });
});

describe("clampPercentForAxis", () => {
  it("passes an in-range percent through as a number", () => {
    expect(clampPercentForAxis("82.0")).toBe(82);
  });

  it("clamps an extreme overrun to the axis clamp", () => {
    expect(clampPercentForAxis("340.0")).toBe(PERCENT_AXIS_CLAMP);
  });
});

describe("axisMaxDomain", () => {
  it("keeps the budget reference line on screen via the floor", () => {
    expect(axisMaxDomain(42)).toBe(PERCENT_AXIS_FLOOR);
  });

  it("rounds up to the next ten between the floor and the clamp", () => {
    expect(axisMaxDomain(143.2)).toBe(150);
  });

  it("never stretches past the clamp", () => {
    expect(axisMaxDomain(340)).toBe(PERCENT_AXIS_CLAMP);
  });
});

describe("budgetTierFill", () => {
  it("returns the over fill once spend passes the budget", () => {
    expect(budgetTierFill({ percentUsed: "112.0", remaining: "-1200.00" })).toBe(
      BUDGET_TIER_FILL.over
    );
  });

  it("returns the warning fill inside the warning band", () => {
    expect(budgetTierFill({ percentUsed: "82.0", remaining: "1800.00" })).toBe(
      BUDGET_TIER_FILL.warning
    );
  });

  it("does not paint a budget spent to exactly 100% amber", () => {
    expect(budgetTierFill({ percentUsed: "100.0", remaining: "0.00" })).toBe(
      BUDGET_TIER_FILL.normal
    );
  });

  it("returns the normal fill below the warning band", () => {
    expect(budgetTierFill({ percentUsed: "42.0", remaining: "5800.00" })).toBe(
      BUDGET_TIER_FILL.normal
    );
  });
});

describe("rollUpCategories", () => {
  const sevenCategories = [
    { name: "Labor", amount: 700 },
    { name: "Materials", amount: 600 },
    { name: "Subcontractor", amount: 500 },
    { name: "Permits", amount: 400 },
    { name: "Equipment", amount: 300 },
    { name: "Rentals", amount: 200 },
    { name: "Disposal", amount: 100 },
  ];

  it("sorts descending and rolls nothing up while inside the slice cap", () => {
    const slices = rollUpCategories(sevenCategories.slice(0, 4));

    expect(slices.map((slice) => slice.name)).toEqual([
      "Labor",
      "Materials",
      "Subcontractor",
      "Permits",
    ]);
    expect(slices.every((slice) => slice.rolledUpNames.length === 0)).toBe(true);
  });

  it("rolls every category past the cap into Other and records their names", () => {
    const slices = rollUpCategories(sevenCategories);

    expect(slices).toHaveLength(MAX_PIE_SLICES);
    const other = slices[slices.length - 1];
    expect(other.name).toBe(OTHER_CATEGORY_NAME);
    expect(other.amount).toBe(300);
    expect(other.rolledUpNames).toEqual(["Rentals", "Disposal"]);
  });

  it("adds the rolled-up money to an existing Other slice and still sorts it last", () => {
    const slices = rollUpCategories([
      ...sevenCategories,
      { name: OTHER_CATEGORY_NAME, amount: 50 },
    ]);

    expect(slices).toHaveLength(MAX_PIE_SLICES);
    const other = slices[slices.length - 1];
    expect(other.name).toBe(OTHER_CATEGORY_NAME);
    expect(other.amount).toBe(350);
    expect(other.rolledUpNames).toEqual(["Rentals", "Disposal"]);
  });
});

describe("bulletChartHeight", () => {
  it("falls back to the standard chart height for a short list", () => {
    expect(bulletChartHeight(3)).toBe(CHART_HEIGHT);
  });

  it("grows without an upper bound so rows are never compressed", () => {
    const fortyRows = bulletChartHeight(40);
    const twentyFiveRows = bulletChartHeight(25);

    expect(fortyRows).toBeGreaterThan(twentyFiveRows);
    expect(fortyRows - twentyFiveRows).toBe(15 * BULLET_ROW_HEIGHT);
  });
});
