/**
 * The Client column has to name the quote's own client.
 *
 * It read job.client_name alone. A project-level quote has no job — which is
 * every quote the AI interview creates, and every quote addressed through the
 * client picker — so the column showed a dash and the client looked unset even
 * though the quote could be sent.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";

jest.mock("next/navigation", () => ({ useRouter: () => ({ push: jest.fn() }) }));
// The row carries a delete button that reads permissions from Redux. This test
// is about the Client column, so the gate is stubbed rather than wired up.
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: () => false, permissions: new Set(), isLoading: false }),
}));

import { QuotesTable } from "../quotes-table";
import type { Job, Quote } from "@/types/api";

const BASE_QUOTE = {
  id: "q-1",
  quote_number: 1001,
  job_id: null,
  title: "Bathroom",
  status: "draft",
  total: "1500.00",
  created_at: "2026-01-15T10:00:00Z",
  revision_number: 1,
  tax_rate: "0",
  discount_type: null,
  discount_value: "0",
  line_items: [],
} as unknown as Quote;

function wrapper({ children }: { children: ReactNode }) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}

function renderTable(quote: Quote, jobsById: Map<string, Job> = new Map()) {
  return render(
    <QuotesTable
      quotes={[quote]}
      jobsById={jobsById}
      sortColumn="created_at"
      sortDirection="desc"
      onSortChange={jest.fn()}
    />,
    { wrapper }
  );
}

it("names the client a quote is addressed to, with no job involved", () => {
  renderTable({ ...BASE_QUOTE, client_name: "Nora Client" } as Quote);
  expect(screen.getByText("Nora Client")).toBeInTheDocument();
});

it("falls back to the job's client for quotes raised against a job", () => {
  const job = { id: "j-1", client_name: "Job Client" } as unknown as Job;
  renderTable(
    { ...BASE_QUOTE, job_id: "j-1" } as Quote,
    new Map([["j-1", job]])
  );
  expect(screen.getByText("Job Client")).toBeInTheDocument();
});

it("prefers the quote's own client over the job's", () => {
  const job = { id: "j-1", client_name: "Job Client" } as unknown as Job;
  renderTable(
    { ...BASE_QUOTE, job_id: "j-1", client_name: "Quote Client" } as Quote,
    new Map([["j-1", job]])
  );
  expect(screen.getByText("Quote Client")).toBeInTheDocument();
  expect(screen.queryByText("Job Client")).toBeNull();
});

it("shows a dash only when there is genuinely no client", () => {
  const { container } = renderTable(BASE_QUOTE);
  expect(container.textContent).toContain("—");
});
