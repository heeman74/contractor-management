import React from "react";
import { render, screen, fireEvent } from "@testing-library/react";
import ForgotPasswordPage from "../forgot-password/page";

describe("ForgotPasswordPage", () => {
  afterEach(() => {
    delete (global as { fetch?: unknown }).fetch;
  });

  test("submits the email and shows the neutral confirmation", async () => {
    const fetchMock = jest.fn().mockResolvedValue({ ok: true } as Response);
    global.fetch = fetchMock as unknown as typeof fetch;

    render(<ForgotPasswordPage />);
    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: "user@example.com" },
    });
    fireEvent.click(screen.getByRole("button", { name: /send reset link/i }));

    expect(await screen.findByText(/a password-reset link is on its way/i)).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/auth/forgot-password",
      expect.objectContaining({ method: "POST" })
    );
  });

  test("shows an error when the request fails", async () => {
    global.fetch = jest.fn().mockResolvedValue({ ok: false } as Response) as unknown as typeof fetch;

    render(<ForgotPasswordPage />);
    fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: "user@example.com" },
    });
    fireEvent.click(screen.getByRole("button", { name: /send reset link/i }));

    expect(await screen.findByText(/something went wrong/i)).toBeInTheDocument();
  });
});
