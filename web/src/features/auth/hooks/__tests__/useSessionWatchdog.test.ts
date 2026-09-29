/**
 * Returning to a tab must not leave a dead session rendering live-looking data.
 *
 * The throttle matters as much as the check: focus fires on every alt-tab, and
 * an unthrottled watchdog would rotate the refresh token dozens of times a
 * minute — which the backend's family-reuse detection treats as theft and
 * answers by revoking the session.
 */
import { act, renderHook } from "@testing-library/react";

jest.mock("@/lib/api-client", () => ({ verifySession: jest.fn() }));

import { verifySession } from "@/lib/api-client";
import { useSessionWatchdog, VERIFY_THROTTLE_MS } from "../useSessionWatchdog";

const mockVerify = verifySession as jest.MockedFunction<typeof verifySession>;

function setVisibility(state: "visible" | "hidden") {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  });
}

beforeEach(() => {
  mockVerify.mockReset();
  mockVerify.mockResolvedValue(true);
  setVisibility("visible");
  jest.useFakeTimers();
  jest.setSystemTime(new Date("2026-09-29T12:00:00Z"));
});

afterEach(() => {
  jest.useRealTimers();
});

async function fireFocus() {
  await act(async () => {
    window.dispatchEvent(new Event("focus"));
  });
}

it("does not verify on mount — the page just loaded", () => {
  renderHook(() => useSessionWatchdog());
  expect(mockVerify).not.toHaveBeenCalled();
});

it("verifies when the tab regains focus after the throttle window", async () => {
  renderHook(() => useSessionWatchdog());

  jest.setSystemTime(new Date(Date.now() + VERIFY_THROTTLE_MS + 1000));
  await fireFocus();

  expect(mockVerify).toHaveBeenCalledTimes(1);
});

it("throttles rapid focus events into one check", async () => {
  renderHook(() => useSessionWatchdog());

  jest.setSystemTime(new Date(Date.now() + VERIFY_THROTTLE_MS + 1000));
  await fireFocus();
  await fireFocus();
  await fireFocus();

  expect(mockVerify).toHaveBeenCalledTimes(1);
});

it("skips the check while the tab is hidden", async () => {
  renderHook(() => useSessionWatchdog());
  setVisibility("hidden");

  jest.setSystemTime(new Date(Date.now() + VERIFY_THROTTLE_MS + 1000));
  await act(async () => {
    document.dispatchEvent(new Event("visibilitychange"));
  });

  expect(mockVerify).not.toHaveBeenCalled();
});

it("stops listening once unmounted", async () => {
  const { unmount } = renderHook(() => useSessionWatchdog());
  unmount();

  jest.setSystemTime(new Date(Date.now() + VERIFY_THROTTLE_MS + 1000));
  await fireFocus();

  expect(mockVerify).not.toHaveBeenCalled();
});
