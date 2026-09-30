/**
 * Editing the company profile.
 *
 * Before this, nothing in the app could write these fields: registration
 * captures a name and the rest of the columns were never set — yet they are what
 * a client reads at the top of every quote, invoice and contract.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

const mockCan = jest.fn();
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: mockCan, permissions: new Set(), isLoading: false }),
}));

const mockMutate = jest.fn();
const mockUseCompany = jest.fn();
jest.mock("@/lib/api/contracts", () => ({
  useCompany: (...args: unknown[]) => mockUseCompany(...args),
  useUpdateCompany: () => ({ mutate: mockMutate, isPending: false }),
}));

jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

import { CompanyProfileForm } from "../company-profile-form";

const COMPANY = {
  id: "c-1",
  name: "Acme Trades",
  address: "12 Elm St",
  phone: "555-0101",
  trade_types: ["Plumbing", "Electrical"],
  logo_url: null,
  business_number: null,
  license_number: "CSLB-1",
  version: 1,
  created_at: "",
  updated_at: "",
  deleted_at: null,
};

function wrapper({ children }: { children: ReactNode }) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}

beforeEach(() => {
  mockCan.mockReset();
  mockMutate.mockReset();
  mockUseCompany.mockReset();
  mockCan.mockReturnValue(true);
  mockUseCompany.mockReturnValue({ data: COMPANY, isLoading: false });
});

it("renders nothing without company.settings.manage", () => {
  mockCan.mockImplementation((key: string) => key !== "company.settings.manage");
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });
  expect(screen.queryByLabelText("Company name")).toBeNull();
});

it("seeds every field from the loaded company", () => {
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });

  expect(screen.getByLabelText("Company name")).toHaveValue("Acme Trades");
  expect(screen.getByLabelText("Address")).toHaveValue("12 Elm St");
  expect(screen.getByLabelText("Phone")).toHaveValue("555-0101");
  // A list on the wire, a comma-separated field on screen.
  expect(screen.getByLabelText("Trades")).toHaveValue("Plumbing, Electrical");
});

it("saves the whole profile", async () => {
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });

  fireEvent.change(screen.getByLabelText("Address"), {
    target: { value: "99 Oak Ave" },
  });
  fireEvent.click(screen.getByRole("button", { name: /Save profile/ }));

  await waitFor(() => expect(mockMutate).toHaveBeenCalled());
  const payload = mockMutate.mock.calls[0][0];
  expect(payload.name).toBe("Acme Trades");
  expect(payload.address).toBe("99 Oak Ave");
  expect(payload.trade_types).toEqual(["Plumbing", "Electrical"]);
});

it("sends null rather than an empty string for a cleared field", async () => {
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });

  fireEvent.change(screen.getByLabelText("Phone"), { target: { value: "   " } });
  fireEvent.click(screen.getByRole("button", { name: /Save profile/ }));

  await waitFor(() => expect(mockMutate).toHaveBeenCalled());
  expect(mockMutate.mock.calls[0][0].phone).toBeNull();
});

it("drops blank entries from the trades list", async () => {
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });

  fireEvent.change(screen.getByLabelText("Trades"), {
    target: { value: "Plumbing, , Roofing ,, " },
  });
  fireEvent.click(screen.getByRole("button", { name: /Save profile/ }));

  await waitFor(() => expect(mockMutate).toHaveBeenCalled());
  expect(mockMutate.mock.calls[0][0].trade_types).toEqual(["Plumbing", "Roofing"]);
});

it("will not save an empty company name", () => {
  render(<CompanyProfileForm companyId="c-1" />, { wrapper });

  fireEvent.change(screen.getByLabelText("Company name"), {
    target: { value: "  " },
  });

  expect(screen.getByRole("button", { name: /Save profile/ })).toBeDisabled();
  expect(screen.getByRole("alert")).toHaveTextContent(/name is required/i);
  fireEvent.click(screen.getByRole("button", { name: /Save profile/ }));
  expect(mockMutate).not.toHaveBeenCalled();
});
