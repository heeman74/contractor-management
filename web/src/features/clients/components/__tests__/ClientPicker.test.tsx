/**
 * Picking or adding the client a quote is for.
 *
 * This is where the send gate's requirement gets satisfied. The backend refuses
 * to send a quote with no client, so the picker existing at creation time is
 * what keeps that refusal from being the user's first hint.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

jest.mock("@/lib/api-client", () => ({ apiGet: jest.fn(), apiPost: jest.fn() }));

import { apiGet, apiPost } from "@/lib/api-client";
import { ClientPicker } from "../ClientPicker";

const mockGet = apiGet as jest.MockedFunction<typeof apiGet>;
const mockPost = apiPost as jest.MockedFunction<typeof apiPost>;

const EXISTING = [
  {
    id: "p-1",
    user_id: "u-1",
    first_name: "Nora",
    last_name: "Client",
    email: "nora@example.com",
    phone: null,
    tags: [],
    preferred_contractor_id: null,
    preferred_contractor_name: null,
    jobs_count: 2,
  },
];

function wrapper({ children }: { children: ReactNode }) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
}

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

it("selects an existing client and reports its id and label", async () => {
  mockGet.mockResolvedValue(EXISTING);
  const onChange = jest.fn();

  render(<ClientPicker value={null} onChange={onChange} />, { wrapper });

  const row = await screen.findByRole("button", { name: /Nora Client/ });
  fireEvent.click(row);

  expect(onChange).toHaveBeenCalledWith("u-1", "Nora Client");
});

it("falls back to the email when a client has no name", async () => {
  mockGet.mockResolvedValue([{ ...EXISTING[0], first_name: null, last_name: null }]);
  const onChange = jest.fn();

  render(<ClientPicker value={null} onChange={onChange} />, { wrapper });

  fireEvent.click(await screen.findByRole("button", { name: /nora@example.com/ }));

  expect(onChange).toHaveBeenCalledWith("u-1", "nora@example.com");
});

it("creates a client and selects it immediately", async () => {
  mockGet.mockResolvedValue([]);
  mockPost.mockResolvedValue({ ...EXISTING[0], user_id: "u-new", first_name: "Fresh" });
  const onChange = jest.fn();

  render(<ClientPicker value={null} onChange={onChange} />, { wrapper });

  fireEvent.click(await screen.findByRole("button", { name: /Add a new client/ }));
  fireEvent.change(screen.getByLabelText("Client email"), {
    target: { value: "fresh@example.com" },
  });
  fireEvent.click(screen.getByRole("button", { name: /Add client/ }));

  await waitFor(() => {
    expect(mockPost).toHaveBeenCalledWith("/api/v1/crm/clients", {
      email: "fresh@example.com",
      first_name: undefined,
      last_name: undefined,
    });
    expect(onChange).toHaveBeenCalledWith("u-new", "Fresh Client");
  });
});

it("says plainly that adding a client grants no login", async () => {
  mockGet.mockResolvedValue([]);
  render(<ClientPicker value={null} onChange={jest.fn()} />, { wrapper });

  fireEvent.click(await screen.findByRole("button", { name: /Add a new client/ }));

  expect(screen.getByText(/does not give them a login/i)).toBeInTheDocument();
});

it("surfaces a rejected create instead of silently failing", async () => {
  mockGet.mockResolvedValue([]);
  mockPost.mockRejectedValue({ detail: "That email address already belongs to another account." });

  render(<ClientPicker value={null} onChange={jest.fn()} />, { wrapper });

  fireEvent.click(await screen.findByRole("button", { name: /Add a new client/ }));
  fireEvent.change(screen.getByLabelText("Client email"), {
    target: { value: "taken@example.com" },
  });
  fireEvent.click(screen.getByRole("button", { name: /Add client/ }));

  expect(await screen.findByRole("alert")).toHaveTextContent(/another account/i);
});

it("cannot submit an empty email", async () => {
  mockGet.mockResolvedValue([]);
  render(<ClientPicker value={null} onChange={jest.fn()} />, { wrapper });

  fireEvent.click(await screen.findByRole("button", { name: /Add a new client/ }));

  expect(screen.getByRole("button", { name: /Add client/ })).toBeDisabled();
});
