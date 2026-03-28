import authReducer, { setAuthUser, clearAuth } from "../auth-slice";

describe("auth-slice", () => {
  const initialState = {
    displayName: null,
    companyName: null,
    roles: [] as string[],
    isAuthenticated: false,
  };

  test("has correct initial state", () => {
    const state = authReducer(undefined, { type: "@@INIT" });
    expect(state).toEqual(initialState);
  });

  test("setAuthUser sets user data and marks authenticated", () => {
    const payload = {
      displayName: "John Doe",
      companyName: "Acme Corp",
      roles: ["admin", "contractor"],
    };
    const state = authReducer(initialState, setAuthUser(payload));

    expect(state.displayName).toBe("John Doe");
    expect(state.companyName).toBe("Acme Corp");
    expect(state.roles).toEqual(["admin", "contractor"]);
    expect(state.isAuthenticated).toBe(true);
  });

  test("setAuthUser handles null displayName and companyName", () => {
    const payload = {
      displayName: null,
      companyName: null,
      roles: ["client"],
    };
    const state = authReducer(initialState, setAuthUser(payload));

    expect(state.displayName).toBeNull();
    expect(state.companyName).toBeNull();
    expect(state.isAuthenticated).toBe(true);
  });

  test("clearAuth resets to initial state", () => {
    const authenticatedState = {
      displayName: "John",
      companyName: "Acme",
      roles: ["admin"],
      isAuthenticated: true,
    };
    const state = authReducer(authenticatedState, clearAuth());

    expect(state).toEqual(initialState);
  });

  test("clearAuth is idempotent on already-cleared state", () => {
    const state = authReducer(initialState, clearAuth());
    expect(state).toEqual(initialState);
  });
});
