import React from "react";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

// Trade options come from the shared catalog.
jest.mock("@/lib/api/projects", () => ({
  useTradeCatalog: () => ({
    data: [{ id: "tc-electrical", name: "Electrical", color: "#F59E0B" }],
  }),
}));

// base-ui Dialog/Select don't render under jsdom — replace with pass-throughs.
jest.mock("@/components/ui/dialog", () => ({
  Dialog: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogTitle: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogDescription: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock("@/components/ui/select", () => ({
  Select: ({
    value,
    onValueChange,
    children,
  }: {
    value: string;
    onValueChange: (v: string) => void;
    children: React.ReactNode;
  }) => (
    <select
      aria-label="Trade Type"
      value={value}
      onChange={(e) => onValueChange(e.target.value)}
    >
      <option value="" />
      {children}
    </select>
  ),
  SelectTrigger: () => null,
  SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
    <option value={value}>{children}</option>
  ),
}));

const apiPost = jest.fn();
jest.mock("@/lib/api-client", () => ({
  apiPost: (...args: unknown[]) => apiPost(...args),
}));

import { CreateContractorDialog } from "../create-contractor-dialog";

function renderDialog() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <CreateContractorDialog open onOpenChange={jest.fn()} />
    </QueryClientProvider>
  );
}

describe("CreateContractorDialog", () => {
  beforeEach(() => {
    apiPost.mockReset();
    // user create returns an id; role + specialty calls just resolve
    apiPost.mockImplementation((path: string) =>
      path === "/api/v1/users/"
        ? Promise.resolve({ id: "user-1", email: "c@a.com" })
        : Promise.resolve({})
    );
  });

  test("persists the chosen catalog trade as a specialty on submit", async () => {
    renderDialog();

    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: "c@a.com" },
    });
    fireEvent.change(screen.getByLabelText(/first name/i), {
      target: { value: "Casey" },
    });
    fireEvent.change(screen.getByLabelText(/last name/i), {
      target: { value: "Jones" },
    });
    fireEvent.change(screen.getByLabelText("Trade Type"), {
      target: { value: "tc-electrical" },
    });

    fireEvent.click(screen.getByRole("button", { name: /create contractor/i }));

    await waitFor(() =>
      expect(apiPost).toHaveBeenCalledWith("/api/v1/contractors/user-1/specialties", {
        trade_catalog_id: "tc-electrical",
      })
    );
  });

  test("skips the specialty call when no trade is selected", async () => {
    renderDialog();

    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: "c@a.com" },
    });
    fireEvent.change(screen.getByLabelText(/first name/i), {
      target: { value: "Casey" },
    });
    fireEvent.change(screen.getByLabelText(/last name/i), {
      target: { value: "Jones" },
    });

    fireEvent.click(screen.getByRole("button", { name: /create contractor/i }));

    await waitFor(() => expect(apiPost).toHaveBeenCalledWith("/api/v1/users/", expect.anything()));
    expect(apiPost).not.toHaveBeenCalledWith(
      expect.stringContaining("/specialties"),
      expect.anything()
    );
  });
});
