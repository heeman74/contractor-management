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
const mockClearSmtp = jest.fn();
const mockUseCompany = jest.fn();
const mockUseEmailStatus = jest.fn();
const mockClearApi = jest.fn();
jest.mock("@/lib/api/contracts", () => ({
  useCompany: (...args: unknown[]) => mockUseCompany(...args),
  useClearCompanyEmailApi: () => ({ mutate: mockClearApi, isPending: false }),
  useCompanyEmailStatus: (...args: unknown[]) => mockUseEmailStatus(...args),
  useUpdateCompany: () => ({ mutate: mockUpdate, isPending: false }),
  useTestCompanyEmail: () => ({ mutate: mockTest, isPending: false }),
  useClearCompanySmtp: () => ({ mutate: mockClearSmtp, isPending: false }),
}));

jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

import { CompanyEmailForm } from "../company-email-form";
import type { Company, EmailStatus } from "@/types/api";

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
  email_api_provider: null,
  email_api_configured: false,
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

/** A server that has its own mail account, so the mailbox is genuinely optional. */
const STATUS_WITH_RELAY: EmailStatus = {
  mailbox_configured: false,
  api_configured: false,
  relay_available: true,
  can_send: true,
  transport: "relay",
  sender: "Acme Trades <ops@relay.test>",
  reply_to: "quotes@acme.com",
};

function renderForm(
  company: Partial<Company> = {},
  status: Partial<EmailStatus> | null = {}
) {
  mockUseCompany.mockReturnValue({
    data: { ...COMPANY, ...company },
    isLoading: false,
  });
  mockUseEmailStatus.mockReturnValue({
    data: status === null ? undefined : { ...STATUS_WITH_RELAY, ...status },
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

/**
 * One method carries the mail, and the screen says which.
 *
 * Both used to be fillable at once, with the server quietly preferring the
 * provider — so the settings could not be read to find out what would actually
 * happen.
 */
describe("choosing how mail is sent", () => {
  const chooseMethod = (name: RegExp) =>
    fireEvent.click(screen.getByRole("radio", { name }));

  it("starts on the server's account when nothing is configured", () => {
    renderForm();

    expect(screen.getByRole("radio", { name: /server's mail account/ })).toBeChecked();
    // The other methods' fields stay out of the way until chosen.
    expect(screen.queryByLabelText("Provider")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("SMTP server")).not.toBeInTheDocument();
  });

  it("starts on the provider when one is configured", () => {
    renderForm({ email_api_provider: "resend", email_api_configured: true });

    expect(screen.getByRole("radio", { name: /email provider/ })).toBeChecked();
    expect(screen.getByLabelText("Provider")).toHaveValue("resend");
    expect(screen.queryByLabelText("SMTP server")).not.toBeInTheDocument();
  });

  it("starts on the mailbox when only that is configured", () => {
    renderForm({ smtp_configured: true, smtp_host: "smtp.gmail.com" });

    expect(screen.getByRole("radio", { name: /own mailbox/ })).toBeChecked();
    expect(screen.getByLabelText("SMTP server")).toHaveValue("smtp.gmail.com");
    expect(screen.queryByLabelText("Provider")).not.toBeInTheDocument();
  });

  it("prefers the provider when both are somehow stored, as the server does", () => {
    renderForm({
      email_api_provider: "resend",
      email_api_configured: true,
      smtp_configured: true,
      smtp_host: "smtp.gmail.com",
    });

    expect(screen.getByRole("radio", { name: /email provider/ })).toBeChecked();
  });

  it("shows only the chosen method's fields", () => {
    renderForm();

    chooseMethod(/email provider/);
    expect(screen.getByLabelText("Provider")).toBeInTheDocument();
    expect(screen.queryByLabelText("SMTP server")).not.toBeInTheDocument();

    chooseMethod(/own mailbox/);
    expect(screen.getByLabelText("SMTP server")).toBeInTheDocument();
    expect(screen.queryByLabelText("Provider")).not.toBeInTheDocument();
  });

  it("does not offer the server's account when the server has none", () => {
    renderForm({}, { relay_available: false, can_send: false });

    expect(screen.getByRole("radio", { name: /server's mail account/ })).toBeDisabled();
  });
});

describe("saving a choice", () => {
  beforeEach(() => mockUpdate.mockImplementation((_p, o) => o.onSuccess()));

  it("sends only the chosen method's settings", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Sending address"), {
      target: { value: "quotes@acme.com" },
    });
    fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));
    fireEvent.change(screen.getByLabelText("Provider"), {
      target: { value: "resend" },
    });
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "re_secret" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

    await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
    const payload = mockUpdate.mock.calls[0][0];
    expect(payload.email_api_provider).toBe("resend");
    expect(payload.email_api_key).toBe("re_secret");
    expect(payload).not.toHaveProperty("smtp_host");
  });

  it("removes the mailbox when switching to a provider", async () => {
    // Otherwise both are stored and an invisible preference order decides.
    renderForm({
      smtp_configured: true,
      smtp_host: "smtp.gmail.com",
      smtp_user: "s@acme.com",
      email_from_address: "quotes@acme.com",
    });

    fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));
    fireEvent.change(screen.getByLabelText("Provider"), {
      target: { value: "resend" },
    });
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "re_secret" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

    await waitFor(() => expect(mockClearSmtp).toHaveBeenCalled());
  });

  it("removes the provider when switching to a mailbox", async () => {
    renderForm({
      email_api_provider: "resend",
      email_api_configured: true,
      email_from_address: "quotes@acme.com",
    });

    fireEvent.click(screen.getByRole("radio", { name: /own mailbox/ }));
    fireEvent.change(screen.getByLabelText("SMTP server"), {
      target: { value: "smtp.gmail.com" },
    });
    fireEvent.change(screen.getByLabelText("Username"), {
      target: { value: "s@acme.com" },
    });
    fireEvent.change(screen.getByLabelText("Password"), {
      target: { value: "app pass" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

    await waitFor(() => expect(mockClearApi).toHaveBeenCalled());
  });

  it("removes both when going back to the server's account", async () => {
    renderForm({
      email_api_provider: "resend",
      email_api_configured: true,
      smtp_configured: true,
      smtp_host: "smtp.gmail.com",
    });

    fireEvent.click(screen.getByRole("radio", { name: /server's mail account/ }));
    fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

    await waitFor(() => expect(mockClearSmtp).toHaveBeenCalled());
  });

  it("will not save a provider with no key", () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Sending address"), {
      target: { value: "quotes@acme.com" },
    });
    fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));

    expect(screen.getByRole("button", { name: "Save email settings" })).toBeDisabled();
    expect(
      screen.getByText("A provider needs to be chosen, with its API key.")
    ).toBeInTheDocument();
  });

  it("will not save half a mailbox", () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Sending address"), {
      target: { value: "quotes@acme.com" },
    });
    fireEvent.click(screen.getByRole("radio", { name: /own mailbox/ }));
    fireEvent.change(screen.getByLabelText("SMTP server"), {
      target: { value: "smtp.gmail.com" },
    });

    expect(screen.getByRole("button", { name: "Save email settings" })).toBeDisabled();
    expect(
      screen.getByText("A mailbox needs a server, a username and a password.")
    ).toBeInTheDocument();
  });

  it("will not send through a provider with no address to send from", () => {
    // A provider refuses a message with an empty From, and the refusal is
    // about the malformed address rather than the empty field behind it.
    renderForm();

    fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));
    fireEvent.change(screen.getByLabelText("Provider"), {
      target: { value: "resend" },
    });
    fireEvent.change(screen.getByLabelText("API key"), {
      target: { value: "re_secret" },
    });

    expect(screen.getByRole("button", { name: "Save email settings" })).toBeDisabled();
    expect(screen.getByText(/A sending address is needed/)).toBeInTheDocument();
  });

  it("never prefills a stored credential, and leaves it alone when blank", async () => {
    renderForm({
      email_api_provider: "resend",
      email_api_configured: true,
      email_from_address: "quotes@acme.com",
    });

    expect(screen.getByLabelText("Replace API key")).toHaveValue("");

    fireEvent.click(screen.getByRole("button", { name: "Save email settings" }));

    await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
    expect(mockUpdate.mock.calls[0][0]).not.toHaveProperty("email_api_key");
  });

  it("keeps the port editable on a saved mailbox", () => {
    renderForm({
      smtp_configured: true,
      smtp_host: "smtp.gmail.com",
      smtp_port: 587,
      smtp_user: "s@acme.com",
    });

    const port = screen.getByLabelText("Port");
    expect(port).not.toBeDisabled();
    fireEvent.change(port, { target: { value: "465" } });

    expect(port).toHaveValue("465");
  });

  it("ignores anything that is not a digit in the port", () => {
    renderForm({ smtp_configured: true, smtp_host: "smtp.gmail.com", smtp_user: "s@a.com" });

    fireEvent.change(screen.getByLabelText("Port"), { target: { value: "4a6b5" } });

    expect(screen.getByLabelText("Port")).toHaveValue("465");
  });
});

describe("the test send", () => {
  it("saves first when something has been changed", async () => {
    renderForm({
      smtp_configured: true,
      smtp_host: "smtp.gmail.com",
      smtp_port: 587,
      smtp_user: "s@acme.com",
      email_from_address: "quotes@acme.com",
    });
    mockUpdate.mockImplementation((_p, o) => o.onSuccess());

    fireEvent.change(screen.getByLabelText("Port"), { target: { value: "465" } });
    fireEvent.click(screen.getByRole("button", { name: /Save and send a test/ }));

    await waitFor(() => expect(mockUpdate).toHaveBeenCalled());
    expect(mockUpdate.mock.calls[0][0].smtp_port).toBe(465);
    await waitFor(() => expect(mockTest).toHaveBeenCalled());
  });

  it("tests directly when nothing has been changed", async () => {
    renderForm({ email_api_configured: true, email_api_provider: "resend" });

    fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

    await waitFor(() => expect(mockTest).toHaveBeenCalled());
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it("reports a refusal in full rather than as a generic failure", async () => {
    renderForm();
    mockTest.mockImplementation((_arg, options) =>
      options.onSuccess({
        delivered: false,
        transport: "company-smtp",
        recipient: "admin@acme.com",
        detail:
          "SMTPAuthenticationError: (535, '5.7.8 Username and Password not accepted.')",
      })
    );

    fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

    await waitFor(() =>
      expect(
        screen.getByText("Nothing was sent to admin@acme.com")
      ).toBeInTheDocument()
    );
    expect(screen.getByText(/5\.7\.8/)).toBeInTheDocument();
  });

  it("does not claim a message arrived, only that it was accepted", async () => {
    renderForm();
    mockTest.mockImplementation((_arg, options) =>
      options.onSuccess({
        delivered: true,
        transport: "company-api",
        recipient: "admin@acme.com",
        detail: "Accepted for delivery via this company's email provider.",
      })
    );

    fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

    await waitFor(() =>
      expect(
        screen.getByText(/Handed to the mail server, addressed to admin@acme.com/)
      ).toBeInTheDocument()
    );
  });
});

it("offers a way to test a provider before DNS is set up", () => {
  renderForm();
  fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));

  expect(screen.getByText("onboarding@resend.dev")).toBeInTheDocument();
});

it("explains that the provider's key goes in the password field", () => {
  renderForm();
  fireEvent.click(screen.getByRole("radio", { name: /own mailbox/ }));

  expect(screen.getByText(/no separate key field/)).toBeInTheDocument();
});


it("explains why the recipient is restricted to two known addresses", () => {
  // A free-text field here would be a way to send mail as the company to
  // anyone; a trial sender's own-account-only rule is why there are two rather
  // than one.
  renderForm();

  expect(screen.getByText(/never an address typed in/)).toBeInTheDocument();
});

/**
 * A provider's trial sender only delivers to the address its own account uses.
 * That is almost never the signed-in user's, so a test that can only go to the
 * caller cannot check a trial sender at all — which is where several rounds of
 * identical 403s came from.
 */
describe("where the test is sent", () => {
  it("goes to the caller by default", async () => {
    renderForm({ email_from_address: "owner@acme.com" });

    fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

    await waitFor(() => expect(mockTest).toHaveBeenCalledWith("me", expect.anything()));
  });

  it("can be sent to the reply-to address instead", async () => {
    renderForm({ email_from_address: "owner@acme.com" });

    fireEvent.change(screen.getByLabelText("Send the test to"), {
      target: { value: "sender" },
    });
    fireEvent.click(screen.getByRole("button", { name: /Send a test to myself/ }));

    await waitFor(() =>
      expect(mockTest).toHaveBeenCalledWith("sender", expect.anything())
    );
  });

  it("names the reply-to address in the choice", () => {
    renderForm({ email_from_address: "owner@acme.com" });

    expect(screen.getByRole("option", { name: /owner@acme.com/ })).toBeInTheDocument();
  });

  it("cannot choose the reply-to address when there is none", () => {
    renderForm({ email_from_address: null });

    expect(screen.getByRole("option", { name: /none set/ })).toBeDisabled();
  });

  it("offers no way to type an address", () => {
    // The restriction that keeps this from being a way to send mail as the
    // company to anyone.
    renderForm({ email_from_address: "owner@acme.com" });

    const choice = screen.getByLabelText("Send the test to");
    expect(choice.tagName).toBe("SELECT");
    expect(
      Array.from(choice.querySelectorAll("option")).map((o) => o.getAttribute("value"))
    ).toEqual(["me", "sender"]);
  });
});


/**
 * The From a client sees is this field — it was labelled "reply-to", which is
 * what it becomes on only one of the three methods, so the From read as though
 * it were fixed somewhere out of reach.
 */
describe("what the sending address is for", () => {
  it("is a reply-to when the server's account sends", () => {
    renderForm();

    expect(screen.getByText(/where client replies go/)).toBeInTheDocument();
  });

  it("is the From, and must be a verified domain, with a provider", () => {
    renderForm();
    fireEvent.click(screen.getByRole("radio", { name: /email provider/ }));

    expect(
      screen.getByText(/From address your clients see.*verified with your provider/)
    ).toBeInTheDocument();
  });

  it("is the From, and must match the mailbox, over SMTP", () => {
    renderForm();
    fireEvent.click(screen.getByRole("radio", { name: /own mailbox/ }));

    expect(
      screen.getByText(/From address your clients see.*match the mailbox/)
    ).toBeInTheDocument();
  });
});
