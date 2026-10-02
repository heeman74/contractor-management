/**
 * One click, one attempt.
 *
 * setIsSubmitting does not take effect until the next render, so a double-click
 * sent the request twice before the button disabled — visible as two POSTs per
 * attempt in the browser log. Each failed attempt counts against a per-account
 * budget, so two per click reaches a lockout in half the tries.
 */
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

const mockPush = jest.fn();
jest.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
  useSearchParams: () => new URLSearchParams(),
}));

const mockSubmitLogin = jest.fn();
jest.mock("@/features/auth/lib/submitLogin", () => ({
  submitLogin: (...args: unknown[]) => mockSubmitLogin(...args),
}));

const mockDispatch = jest.fn();
jest.mock("@/store/hooks", () => ({
  useAppDispatch: () => mockDispatch,
  useAppSelector: () => null,
}));

import LoginPage from "../login/page";

beforeEach(() => {
  jest.clearAllMocks();
});

it("sends one request even when the button is clicked twice", async () => {
  // Never resolves, so the first attempt is still in flight for the second click.
  mockSubmitLogin.mockImplementation(() => new Promise(() => {}));
  render(<LoginPage />);

  fireEvent.change(screen.getByLabelText(/email/i), {
    target: { value: "someone@example.com" },
  });
  fireEvent.change(document.getElementById("password") as HTMLInputElement, {
    target: { value: "TestPass123!" },
  });

  const submit = screen.getByRole("button", { name: /sign in/i });
  fireEvent.click(submit);
  fireEvent.click(submit);

  await waitFor(() => expect(mockSubmitLogin).toHaveBeenCalled());
  expect(mockSubmitLogin).toHaveBeenCalledTimes(1);
});
