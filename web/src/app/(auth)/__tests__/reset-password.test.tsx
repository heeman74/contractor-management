import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import ResetPasswordPage from "../reset-password/page";

function setToken(token: string | null) {
  const url = token === null ? "/reset-password" : `/reset-password?token=${token}`;
  window.history.pushState({}, "", url);
}

describe("ResetPasswordPage", () => {
  afterEach(() => {
    delete (global as { fetch?: unknown }).fetch;
  });

  test("shows a request-new-link message when the token is missing", () => {
    setToken(null);
    render(<ResetPasswordPage />);
    expect(screen.getByText(/missing or invalid/i)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /request a new link/i })).toBeInTheDocument();
  });

  test("blocks submit and warns when the passwords do not match", () => {
    setToken("tok-123");
    const fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;

    render(<ResetPasswordPage />);
    fireEvent.change(screen.getByLabelText(/^new password/i), {
      target: { value: "GoodPass123!" },
    });
    fireEvent.change(screen.getByLabelText(/confirm new password/i), {
      target: { value: "Mismatch9!" },
    });
    fireEvent.click(screen.getByRole("button", { name: /reset password/i }));

    expect(screen.getByText(/do not match/i)).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("posts the token + new password and confirms success on 204", async () => {
    setToken("tok-123");
    const fetchMock = jest.fn().mockResolvedValue({ status: 204 } as Response);
    global.fetch = fetchMock as unknown as typeof fetch;

    render(<ResetPasswordPage />);
    fireEvent.change(screen.getByLabelText(/^new password/i), {
      target: { value: "GoodPass123!" },
    });
    fireEvent.change(screen.getByLabelText(/confirm new password/i), {
      target: { value: "GoodPass123!" },
    });
    fireEvent.click(screen.getByRole("button", { name: /reset password/i }));

    expect(await screen.findByText(/your password has been reset/i)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/auth/reset-password",
      expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ token: "tok-123", new_password: "GoodPass123!" }),
      })
    );
  });
});
