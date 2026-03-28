/**
 * Integration test: verify the Redux store boots with all slices.
 */

import { makeStore } from "@/store/index";
import { setAuthUser, clearAuth } from "../auth-slice";
import { toggleSidebar, setPageTitle } from "../ui-slice";
import { toggleFilterToolbar } from "../schedule-slice";

describe("Redux store integration", () => {
  test("makeStore creates a store with all slices", () => {
    const store = makeStore();
    const state = store.getState();

    expect(state).toHaveProperty("auth");
    expect(state).toHaveProperty("ui");
    expect(state).toHaveProperty("schedule");
  });

  test("dispatching auth actions updates state", () => {
    const store = makeStore();

    store.dispatch(
      setAuthUser({
        displayName: "Test User",
        companyName: "Test Co",
        roles: ["admin"],
      })
    );

    const { auth } = store.getState();
    expect(auth.isAuthenticated).toBe(true);
    expect(auth.displayName).toBe("Test User");

    store.dispatch(clearAuth());
    expect(store.getState().auth.isAuthenticated).toBe(false);
  });

  test("dispatching UI actions updates state", () => {
    const store = makeStore();

    store.dispatch(toggleSidebar());
    expect(store.getState().ui.sidebarCollapsed).toBe(true);

    store.dispatch(setPageTitle("Dashboard"));
    expect(store.getState().ui.pageTitle).toBe("Dashboard");
  });

  test("dispatching schedule actions updates state", () => {
    const store = makeStore();

    store.dispatch(toggleFilterToolbar());
    expect(store.getState().schedule.filterToolbarCollapsed).toBe(false);
  });

  test("slices are independent — dispatching to one does not affect others", () => {
    const store = makeStore();
    const initialAuth = store.getState().auth;

    store.dispatch(toggleSidebar());

    // Auth state should be unchanged
    expect(store.getState().auth).toEqual(initialAuth);
  });
});
