/**
 * Tests for KpiCard component.
 *
 * next/link and lucide-react icons are mocked to avoid pulling in
 * heavy framework internals in unit tests.
 */

import React from "react";
import { render, screen } from "@testing-library/react";
import { KpiCard } from "../kpi-card";

// Mock next/link to a simple anchor
jest.mock("next/link", () => {
  return function MockLink({
    href,
    children,
    ...rest
  }: {
    href: string;
    children: React.ReactNode;
    className?: string;
  }) {
    return (
      <a href={href} {...rest}>
        {children}
      </a>
    );
  };
});

// Stub icon component
function StubIcon(props: React.SVGProps<SVGSVGElement>) {
  return <svg data-testid="stub-icon" {...props} />;
}

describe("KpiCard", () => {
  test("renders title and value", () => {
    render(
      <KpiCard title="Active Jobs" value={42} icon={StubIcon as never} href="/jobs" />
    );
    expect(screen.getByText("Active Jobs")).toBeInTheDocument();
    expect(screen.getByText("42")).toBeInTheDocument();
  });

  test("renders string value", () => {
    render(
      <KpiCard title="Revenue" value="$12,500" icon={StubIcon as never} href="/reports" />
    );
    expect(screen.getByText("$12,500")).toBeInTheDocument();
  });

  test("renders link with correct href", () => {
    render(
      <KpiCard title="Clients" value={15} icon={StubIcon as never} href="/clients" />
    );
    const link = screen.getByRole("link");
    expect(link).toHaveAttribute("href", "/clients");
  });

  test("renders skeleton when loading", () => {
    const { container } = render(
      <KpiCard title="Jobs" value={0} icon={StubIcon as never} href="/jobs" loading />
    );
    // When loading, should NOT render the title text or value
    expect(screen.queryByText("Jobs")).not.toBeInTheDocument();
    expect(screen.queryByText("0")).not.toBeInTheDocument();
    // Should have skeleton elements (pulse animation divs)
    const skeletons = container.querySelectorAll("[data-slot='skeleton']");
    expect(skeletons.length).toBeGreaterThan(0);
  });

  test("renders icon", () => {
    render(
      <KpiCard title="Test" value={1} icon={StubIcon as never} href="/test" />
    );
    expect(screen.getByTestId("stub-icon")).toBeInTheDocument();
  });
});
