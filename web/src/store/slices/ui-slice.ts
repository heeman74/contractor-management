import { createSlice, PayloadAction } from "@reduxjs/toolkit";

interface UiState {
  sidebarCollapsed: boolean;
}

function getInitialSidebarState(): boolean {
  // On the server, default to false. On the client, read localStorage.
  if (typeof window === "undefined") return false;
  try {
    const stored = window.localStorage.getItem("sidebarCollapsed");
    return stored === "true";
  } catch {
    return false;
  }
}

const initialState: UiState = {
  sidebarCollapsed: false,
};

const uiSlice = createSlice({
  name: "ui",
  initialState,
  reducers: {
    initSidebar(state) {
      // Call this action on client mount to hydrate from localStorage
      state.sidebarCollapsed = getInitialSidebarState();
    },
    toggleSidebar(state) {
      state.sidebarCollapsed = !state.sidebarCollapsed;
      if (typeof window !== "undefined") {
        try {
          window.localStorage.setItem(
            "sidebarCollapsed",
            String(state.sidebarCollapsed)
          );
        } catch {
          // ignore storage errors
        }
      }
    },
    setSidebarCollapsed(state, action: PayloadAction<boolean>) {
      state.sidebarCollapsed = action.payload;
      if (typeof window !== "undefined") {
        try {
          window.localStorage.setItem(
            "sidebarCollapsed",
            String(action.payload)
          );
        } catch {
          // ignore storage errors
        }
      }
    },
  },
});

export const { initSidebar, toggleSidebar, setSidebarCollapsed } =
  uiSlice.actions;
export default uiSlice.reducer;
