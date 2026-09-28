import React from "react";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

// base-ui Dialog doesn't render under jsdom — pass-through wrappers.
jest.mock("@/components/ui/dialog", () => ({
  Dialog: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogTitle: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogDescription: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

const apiPost = jest.fn();
jest.mock("@/lib/api-client", () => ({
  apiPost: (...args: unknown[]) => apiPost(...args),
  ApiError: class ApiError extends Error {
    detail: string;
    constructor(detail: string) {
      super(detail);
      this.detail = detail;
    }
  },
}));

import { ChangePasswordDialog } from "../change-password-dialog";

function renderDialog() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ChangePasswordDialog open onOpenChange={jest.fn()} />
    </QueryClientProvider>
  );
}

function fill(label: RegExp, value: string) {
  fireEvent.change(screen.getByLabelText(label), { target: { value } });
}

describe("ChangePasswordDialog", () => {
  beforeEach(() => {
    apiPost.mockReset();
    apiPost.mockResolvedValue(undefined);
  });

  test("posts current + new password when the form is valid", async () => {
    renderDialog();
    fill(/current password/i, "OldPass123!");
    fill(/^new password/i, "NewPass456!");
    fill(/confirm new password/i, "NewPass456!");

    fireEvent.click(screen.getByRole("button", { name: /change password/i }));

    await waitFor(() =>
      expect(apiPost).toHaveBeenCalledWith("/api/v1/auth/change-password", {
        current_password: "OldPass123!",
        new_password: "NewPass456!",
      })
    );
  });

  test("blocks submit and shows an error when confirmation doesn't match", async () => {
    renderDialog();
    fill(/current password/i, "OldPass123!");
    fill(/^new password/i, "NewPass456!");
    fill(/confirm new password/i, "Different9!");

    fireEvent.click(screen.getByRole("button", { name: /change password/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/do not match/i);
    expect(apiPost).not.toHaveBeenCalled();
  });

  test("blocks submit when the new password is too short", async () => {
    renderDialog();
    fill(/current password/i, "OldPass123!");
    fill(/^new password/i, "short");
    fill(/confirm new password/i, "short");

    fireEvent.click(screen.getByRole("button", { name: /change password/i }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/at least 8/i);
    expect(apiPost).not.toHaveBeenCalled();
  });
});
