import React from "react";
import { render, screen } from "@testing-library/react";
import { StatusBadge } from "../status-badge";

describe("StatusBadge", () => {
  test("renders the status text", () => {
    render(<StatusBadge status="active" />);
    expect(screen.getByText("active")).toBeInTheDocument();
  });

  test("replaces underscores with spaces in display text", () => {
    render(<StatusBadge status="in_progress" />);
    expect(screen.getByText("in progress")).toBeInTheDocument();
  });

  test("replaces hyphens with spaces in display text", () => {
    render(<StatusBadge status="in-progress" />);
    expect(screen.getByText("in progress")).toBeInTheDocument();
  });

  test("applies green classes for active status", () => {
    render(<StatusBadge status="active" />);
    const badge = screen.getByText("active");
    expect(badge.className).toContain("bg-green-100");
    expect(badge.className).toContain("text-green-800");
  });

  test("applies yellow classes for pending status", () => {
    render(<StatusBadge status="pending" />);
    const badge = screen.getByText("pending");
    expect(badge.className).toContain("bg-yellow-100");
    expect(badge.className).toContain("text-yellow-800");
  });

  test("applies red classes for overdue status", () => {
    render(<StatusBadge status="overdue" />);
    const badge = screen.getByText("overdue");
    expect(badge.className).toContain("bg-red-100");
    expect(badge.className).toContain("text-red-800");
  });

  test("applies gray fallback for unknown status", () => {
    render(<StatusBadge status="unknown_status" />);
    const badge = screen.getByText("unknown status");
    expect(badge.className).toContain("bg-gray-100");
    expect(badge.className).toContain("text-gray-700");
  });

  test("handles case-insensitive status lookup", () => {
    render(<StatusBadge status="ACTIVE" />);
    // The colorMap normalizes to lowercase
    const badge = screen.getByText("ACTIVE");
    expect(badge.className).toContain("bg-green-100");
  });

  test("renders with sm size", () => {
    render(<StatusBadge status="draft" size="sm" />);
    const badge = screen.getByText("draft");
    expect(badge.className).toContain("rounded-full");
  });

  test("renders with default md size", () => {
    render(<StatusBadge status="draft" />);
    const badge = screen.getByText("draft");
    expect(badge.className).toContain("rounded-full");
  });

  test("maps all green statuses correctly", () => {
    const greenStatuses = ["active", "paid", "approved", "complete", "completed"];
    for (const status of greenStatuses) {
      const { unmount } = render(<StatusBadge status={status} />);
      const badge = screen.getByText(status);
      expect(badge.className).toContain("bg-green-100");
      unmount();
    }
  });

  test("maps all red statuses correctly", () => {
    const redStatuses = ["overdue", "declined", "cancelled", "canceled"];
    for (const status of redStatuses) {
      const { unmount } = render(<StatusBadge status={status} />);
      const badge = screen.getByText(status);
      expect(badge.className).toContain("bg-red-100");
      unmount();
    }
  });
});
