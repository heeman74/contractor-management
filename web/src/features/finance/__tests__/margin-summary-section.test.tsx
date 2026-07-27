import React from "react";
import { render, screen } from "@testing-library/react";
import {
  MarginSummarySection,
  formatMarginDollars,
  formatMarginPercent,
} from "../components/MarginSummarySection";
import type { MarginSummary } from "../types";

const INVOICED_MARGIN: MarginSummary = {
  revenue: "20000.00",
  revenueBasis: "invoiced",
  margin: "4200.00",
  marginPercent: "21.0",
  incomplete: false,
  incompleteReasons: [],
};

function marginWith(overrides: Partial<MarginSummary> = {}): MarginSummary {
  return { ...INVOICED_MARGIN, ...overrides };
}

describe("MarginSummarySection", () => {
  test("renders nothing when margin is null", () => {
    const { container } = render(<MarginSummarySection margin={null} />);
    expect(container.firstChild).toBeNull();
  });

  test("renders nothing when margin is undefined", () => {
    const { container } = render(<MarginSummarySection margin={undefined} />);
    expect(container.firstChild).toBeNull();
  });

  test("basis none renders only the neutral no-revenue note", () => {
    render(
      <MarginSummarySection
        margin={marginWith({
          revenue: null,
          revenueBasis: "none",
          margin: null,
          marginPercent: null,
        })}
      />
    );

    expect(screen.getByTestId("margin-no-revenue")).toHaveTextContent(
      "No revenue recorded — margin will appear once an invoice or approved quote exists."
    );
    expect(screen.queryByTestId("margin-revenue")).not.toBeInTheDocument();
    expect(screen.queryByTestId("margin-figure")).not.toBeInTheDocument();
  });

  test("invoiced margin shows revenue and figure with no caption and no chip", () => {
    render(<MarginSummarySection margin={marginWith()} />);

    expect(screen.getByTestId("margin-revenue")).toHaveTextContent("$20000.00");
    expect(screen.getByTestId("margin-figure")).toHaveTextContent("$4200.00 · 21%");
    expect(screen.queryByTestId("margin-basis-caption")).not.toBeInTheDocument();
    expect(screen.queryByTestId("margin-incomplete-chip")).not.toBeInTheDocument();
    expect(screen.queryByTestId("margin-incomplete-caption")).not.toBeInTheDocument();
  });

  test("quoted basis adds the quote caption", () => {
    render(<MarginSummarySection margin={marginWith({ revenueBasis: "quoted" })} />);

    expect(screen.getByTestId("margin-basis-caption")).toHaveTextContent(
      "Based on approved quote — not yet invoiced."
    );
  });

  test("mixed basis adds the mixed caption", () => {
    render(<MarginSummarySection margin={marginWith({ revenueBasis: "mixed" })} />);

    expect(screen.getByTestId("margin-basis-caption")).toHaveTextContent(
      "Includes approved quote amounts not yet invoiced."
    );
  });

  test("incomplete flag shows the chip and caption while keeping the figure", () => {
    render(
      <MarginSummarySection
        margin={marginWith({ incomplete: true, incompleteReasons: ["no_cost_data"] })}
      />
    );

    expect(screen.getByTestId("margin-incomplete-chip")).toHaveTextContent(
      "Incomplete cost data"
    );
    expect(screen.getByTestId("margin-incomplete-caption")).toHaveTextContent(
      "Margin may overstate profit — some costs are missing or unrated."
    );
    expect(screen.getByTestId("margin-figure")).toHaveTextContent("$4200.00 · 21%");
  });

  test("negative margin renders signed dollars in the destructive color", () => {
    render(
      <MarginSummarySection
        margin={marginWith({ margin: "-350.00", marginPercent: "-8.3" })}
      />
    );

    const figure = screen.getByTestId("margin-figure");
    expect(figure).toHaveTextContent("-$350.00 · -8.3%");
    expect(figure).toHaveClass("text-destructive");
  });

  test("positive margin does not carry the destructive color", () => {
    render(<MarginSummarySection margin={marginWith()} />);

    expect(screen.getByTestId("margin-figure")).not.toHaveClass("text-destructive");
  });

  test("null percent renders dollars alone with no separator", () => {
    render(<MarginSummarySection margin={marginWith({ marginPercent: null })} />);

    expect(screen.getByTestId("margin-figure").textContent).toBe("$4200.00");
  });

  test("labels Revenue and Margin always render when basis is not none", () => {
    render(<MarginSummarySection margin={marginWith({ revenueBasis: "quoted" })} />);

    expect(screen.getByText("Revenue")).toBeInTheDocument();
    expect(screen.getByText("Margin")).toBeInTheDocument();
  });
});

describe("formatMarginPercent", () => {
  test.each([
    ["21.0", "21"],
    ["8.3", "8.3"],
    ["-8.3", "-8.3"],
    ["100.0", "100"],
    ["0.0", "0"],
  ])("formats %s as %s", (input, expected) => {
    expect(formatMarginPercent(input)).toBe(expected);
  });
});

describe("formatMarginDollars", () => {
  test.each([
    ["4200.00", "$4200.00"],
    ["-350.00", "-$350.00"],
    ["0.00", "$0.00"],
  ])("formats %s as %s", (input, expected) => {
    expect(formatMarginDollars(input)).toBe(expected);
  });
});
