/**
 * A reloaded page must recover who it is signed in as.
 *
 * The regression this guards is not cosmetic. usePermissions gates its query on
 * auth.isAuthenticated, which a refresh reset to false — so every
 * permission-gated control disappeared, and the generic name in the topbar was
 * only the visible symptom.
 */
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Provider } from "react-redux";
import { configureStore } from "@reduxjs/toolkit";
import { renderHook, waitFor } from "@testing-library/react";

jest.mock("@/lib/api-client", () => ({ apiGet: jest.fn() }));

import { apiGet } from "@/lib/api-client";
import authReducer from "@/store/slices/auth-slice";
import { useSessionBootstrap } from "../useSessionBootstrap";

const mockApiGet = apiGet as jest.MockedFunction<typeof apiGet>;

const IDENTITY = {
  user_id: "u-1",
  company_id: "c-1",
  email: "ada@example.com",
  display_name: "Ada Lovelace",
  company_name: "Identity Co",
  roles: ["admin", "project_manager"],
};

function makeStore() {
  return configureStore({ reducer: { auth: authReducer } });
}

function wrapper(store: ReturnType<typeof makeStore>) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <Provider store={store}>
        <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
      </Provider>
    );
  };
}

beforeEach(() => {
  mockApiGet.mockReset();
});

it("restores identity and roles into the store after a reload", async () => {
  mockApiGet.mockResolvedValue(IDENTITY);
  const store = makeStore();

  renderHook(() => useSessionBootstrap(), { wrapper: wrapper(store) });

  await waitFor(() => {
    const auth = store.getState().auth;
    expect(auth.displayName).toBe("Ada Lovelace");
    expect(auth.companyName).toBe("Identity Co");
    expect(auth.roles).toEqual(["admin", "project_manager"]);
  });
});

it("sets isAuthenticated, which the permission gate depends on", async () => {
  mockApiGet.mockResolvedValue(IDENTITY);
  const store = makeStore();

  expect(store.getState().auth.isAuthenticated).toBe(false);
  renderHook(() => useSessionBootstrap(), { wrapper: wrapper(store) });

  await waitFor(() => {
    expect(store.getState().auth.isAuthenticated).toBe(true);
  });
});

it("fetches without waiting to be authenticated — that is what it restores", async () => {
  mockApiGet.mockResolvedValue(IDENTITY);
  const store = makeStore();

  renderHook(() => useSessionBootstrap(), { wrapper: wrapper(store) });

  await waitFor(() => {
    expect(mockApiGet).toHaveBeenCalledWith("/api/v1/auth/me");
  });
});

it("leaves the store untouched when identity cannot be read", async () => {
  mockApiGet.mockRejectedValue(new Error("401"));
  const store = makeStore();

  renderHook(() => useSessionBootstrap(), { wrapper: wrapper(store) });

  await waitFor(() => expect(mockApiGet).toHaveBeenCalled());
  const auth = store.getState().auth;
  expect(auth.isAuthenticated).toBe(false);
  expect(auth.displayName).toBeNull();
});
