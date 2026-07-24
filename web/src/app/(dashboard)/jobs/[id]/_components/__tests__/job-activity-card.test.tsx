import React from "react";
import { render, screen } from "@testing-library/react";
import { JobActivityCard } from "../job-activity-card";
import type { Job } from "@/types/api";

// status_history is heterogeneous: status transitions carry `status`, audit
// events carry `type` (and no `status`). The card must render both without
// crashing — previously an event entry passed `undefined` to StatusBadge.
function history(entries: unknown[]): Job["status_history"] {
  return entries as Job["status_history"];
}

describe("JobActivityCard", () => {
  test("renders empty state when there is no history", () => {
    render(<JobActivityCard statusHistory={history([])} />);
    expect(screen.getByText("No status history yet.")).toBeInTheDocument();
  });

  test("renders a status-transition entry as a status badge", () => {
    render(
      <JobActivityCard
        statusHistory={history([
          { status: "in_progress", timestamp: "2026-07-23T10:00:00Z" },
        ])}
      />
    );
    expect(screen.getByText("in progress")).toBeInTheDocument();
  });

  test("renders an event entry (no status field) without crashing", () => {
    // This is the regression: an event entry has `type`, not `status`.
    render(
      <JobActivityCard
        statusHistory={history([
          {
            type: "quote_created",
            user_id: "u1",
            timestamp: "2026-07-23T10:00:00Z",
          },
          { type: "quote_sent", user_id: null, timestamp: "2026-07-23T11:00:00Z" },
        ])}
      />
    );
    expect(screen.getByText("Quote created")).toBeInTheDocument();
    expect(screen.getByText("Quote sent")).toBeInTheDocument();
  });

  test("renders a delay event with its reason and new ETA", () => {
    render(
      <JobActivityCard
        statusHistory={history([
          {
            type: "delay",
            reason: "Weather",
            new_eta: "2026-07-30T09:00:00Z",
            timestamp: "2026-07-23T12:00:00Z",
          },
        ])}
      />
    );
    expect(screen.getByText("Delay reported")).toBeInTheDocument();
    expect(screen.getByText("Reason: Weather")).toBeInTheDocument();
    expect(screen.getByText(/New ETA:/)).toBeInTheDocument();
  });

  test("renders mixed status and event entries together", () => {
    render(
      <JobActivityCard
        statusHistory={history([
          { status: "quote", timestamp: "2026-07-23T09:00:00Z" },
          { type: "invoice_generated", timestamp: "2026-07-23T13:00:00Z" },
        ])}
      />
    );
    expect(screen.getByText("quote")).toBeInTheDocument();
    expect(screen.getByText("Invoice generated")).toBeInTheDocument();
  });
});
