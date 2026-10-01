/**
 * Configuring where a company's mail comes from.
 *
 * Quotes briefly went out through one server-wide account, so every company's
 * mail was addressed from the operator's mailbox. The form's job is to make the
 * two tiers legible — an address the server uses as reply-to, or the company's
 * own mailbox — and to never show a password it cannot have.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

const mockCan = jest.fn();
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: mockCan, permissions: new Set(), isLoading: false }),
}));

const mockUpdate = jest.fn();
const mockTest = jest.fn();
const mockClear = jest.fn();
const mockUseCompany = jest.fn();
jest.mock("@/lib/api/contracts", () => ({
  useCompany: (...args: unknown[]) => mockUseCompany(...args),
  useUpdateCompany: () => ({ mutate: mockUpdate, isPending: false }),
  useTestCompanyEmail: () => ({ mutate: mockTest, isPending: false }),
  useClearCompanySmtp: () => ({ mutate: mockClear, isPending: false }),
}));

jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

import { CompanyEmailForm } from "../company-email-form";
import type { Company } from "@/types/api";

const COMPANY: Company = {
  id: "c-1",
  name: "Acme Trades",
  address: null,
  phone: null,
  trade_types: null,
  logo_url: null,
  business_number: null,
  license_number: null,
  email_from_name: null,
  email_from_address: null,
  smtp_host: null,
  smtp_port: null,
  smtp_use_tls: true,
  smtp_user: null,
  smtp_configured: false,
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

function renderForm(company: Partial<Company> = {}) {
  mockUseCompany.mockReturnValue({
    data: { ...COMPANY, ...company },
    isLoading: false,
  });
  return render(<CompanyEmailForm companyId="c-1" />, { wrapper });
}

beforeEach(() => {
  jest.clearAllMocks();
  mockCan.mockReturnValue(true);
});

it("is hidden from anyone without the settings permission", () => {
  mockCan.mockReturnValue(false);
  renderForm();

  expect(screen.queryByText("Sending email")).not.toBeInTheDocument();
});

it("saves the sender without requiring a mailbox", async () => {
  renderForm();

  fireEvent.change(screen.getByLabelText("Reply-to address"), {
    target: { value: "quotes@acme.com" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

  await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
  const payload = mockUpdate.mock.calls[0][0];
  expect(payload.email_from_address).toBe("quotes@acme.com");
  expect(payload).not.toHaveProperty("smtp_host");
});

it("will not save half a mailbox", () => {
  // The columns are constrained to travel together, so a partial save would
  // only come back as a database rejection.
  renderForm();

  fireEvent.change(screen.getByLabelText("SMTP server"), {
    target: { value: "smtp.gmail.com" },
  });

  expect(screen.getByRole("button", { name: "Save email settings" })).toBeDisabled();
  expect(
    screen.getByText("A mailbox needs a server, a username and a password.")
  ).toBeInTheDocument();
});

it("sends the password once a whole mailbox is filled in", async () => {
  renderForm();

  fireEvent.change(screen.getByLabelText("SMTP server"), {
    target: { value: "smtp.gmail.com" },
  });
  fireEvent.change(screen.getByLabelText("Username"), {
    target: { value: "steve@acme.com" },
  });
  fireEvent.change(screen.getByLabelText("Password"), {
    target: { value: "abcd efgh ijkl mnop" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

  await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
  const payload = mockUpdate.mock.calls[0][0];
  expect(payload.smtp_host).toBe("smtp.gmail.com");
  expect(payload.smtp_password).toBe("abcd efgh ijkl mnop");
});

it("never prefills the password, and leaves it alone when blank", async () => {
  // The server does not return it, so there is nothing to prefill — and a blank
  // field has to mean "keep what is stored", not "clear it".
  renderForm({ smtp_configured: true, smtp_host: "smtp.gmail.com", smtp_user: "s@acme.com" });

  expect(screen.getByLabelText("Replace password")).toHaveValue("");

  fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

  await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
  expect(mockUpdate.mock.calls[0][0]).not.toHaveProperty("smtp_password");
});

it("offers to stop using the mailbox only once one is configured", () => {
  renderForm();
  expect(
    screen.queryByRole("button", { name: "Stop using my mailbox" })
  ).not.toBeInTheDocument();

  renderForm({ smtp_configured: true });
  expect(
    screen.getByRole("button", { name: "Stop using my mailbox" })
  ).toBeInTheDocument();
});

it("explains that Gmail needs an app password", () => {
  // The deployed failure was a 535 from handing Gmail an account password.
  renderForm();

  expect(screen.getByText(/app password/)).toBeInTheDocument();
});

it("reports a delivered test with the address it reached", async () => {
  renderForm();
  mockTest.mockImplementation((_arg, options) =>
    options.onSuccess({
      delivered: true,
      transport: "company-smtp",
      recipient: "admin@acme.com",
      detail: "Sent via this company's own mailbox.",
    })
  );

  fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

  await waitFor(() =>
    expect(screen.getByText("Test sent to admin@acme.com")).toBeInTheDocument()
  );
  expect(
    screen.getByText("Sent via this company's own mailbox.")
  ).toBeInTheDocument();
});

it("shows a refusal in full rather than as a generic failure", async () => {
  // The provider's own words are the answer to "why did nothing arrive".
  renderForm();
  mockTest.mockImplementation((_arg, options) =>
    options.onSuccess({
      delivered: false,
      transport: "company-smtp",
      recipient: "admin@acme.com",
      detail: "SMTPAuthenticationError: (535, '5.7.8 Username and Password not accepted.')",
    })
  );

  fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

  await waitFor(() =>
    expect(screen.getByText("Nothing was sent")).toBeInTheDocument()
  );
  expect(screen.getByText(/5\.7\.8/)).toBeInTheDocument();
});
