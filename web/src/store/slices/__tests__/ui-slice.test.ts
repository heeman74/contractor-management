import uiReducer, {
  toggleSidebar,
  setSidebarCollapsed,
  setPageTitle,
  initSidebar,
} from "../ui-slice";

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: jest.fn((key: string) => store[key] ?? null),
    setItem: jest.fn((key: string, value: string) => {
      store[key] = value;
    }),
    clear: () => {
      store = {};
    },
  };
})();

Object.defineProperty(window, "localStorage", {
  value: localStorageMock,
});

afterEach(() => {
  localStorageMock.clear();
  jest.clearAllMocks();
});

describe("ui-slice", () => {
  const initialState = {
    sidebarCollapsed: false,
    pageTitle: null as string | null,
  };

  test("has correct initial state", () => {
    const state = uiReducer(undefined, { type: "@@INIT" });
    expect(state.sidebarCollapsed).toBe(false);
    expect(state.pageTitle).toBeNull();
  });

  test("toggleSidebar flips the collapsed state", () => {
    let state = uiReducer(initialState, toggleSidebar());
    expect(state.sidebarCollapsed).toBe(true);

    state = uiReducer(state, toggleSidebar());
    expect(state.sidebarCollapsed).toBe(false);
  });

  test("toggleSidebar persists to localStorage", () => {
    uiReducer(initialState, toggleSidebar());
    expect(localStorageMock.setItem).toHaveBeenCalledWith(
      "sidebarCollapsed",
      "true"
    );
  });

  test("setSidebarCollapsed sets explicit value", () => {
    const state = uiReducer(initialState, setSidebarCollapsed(true));
    expect(state.sidebarCollapsed).toBe(true);
  });

  test("setSidebarCollapsed persists to localStorage", () => {
    uiReducer(initialState, setSidebarCollapsed(true));
    expect(localStorageMock.setItem).toHaveBeenCalledWith(
      "sidebarCollapsed",
      "true"
    );
  });

  test("setPageTitle updates the page title", () => {
    const state = uiReducer(initialState, setPageTitle("Dashboard"));
    expect(state.pageTitle).toBe("Dashboard");
  });

  test("setPageTitle can be set to null", () => {
    const withTitle = { ...initialState, pageTitle: "Dashboard" };
    const state = uiReducer(withTitle, setPageTitle(null));
    expect(state.pageTitle).toBeNull();
  });

  test("initSidebar reads from localStorage", () => {
    localStorageMock.getItem.mockReturnValueOnce("true");
    const state = uiReducer(initialState, initSidebar());
    expect(state.sidebarCollapsed).toBe(true);
  });

  test("initSidebar defaults to false when localStorage is empty", () => {
    localStorageMock.getItem.mockReturnValueOnce(null as unknown as string);
    const state = uiReducer(initialState, initSidebar());
    expect(state.sidebarCollapsed).toBe(false);
  });
});
