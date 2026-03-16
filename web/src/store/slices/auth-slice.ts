import { createSlice, PayloadAction } from "@reduxjs/toolkit";

// Display metadata ONLY — tokens are in httpOnly cookies, never in Redux
interface AuthState {
  displayName: string | null;
  companyName: string | null;
  roles: string[];
  isAuthenticated: boolean;
}

interface SetAuthUserPayload {
  displayName: string | null;
  companyName: string | null;
  roles: string[];
}

const initialState: AuthState = {
  displayName: null,
  companyName: null,
  roles: [],
  isAuthenticated: false,
};

const authSlice = createSlice({
  name: "auth",
  initialState,
  reducers: {
    setAuthUser(state, action: PayloadAction<SetAuthUserPayload>) {
      state.displayName = action.payload.displayName;
      state.companyName = action.payload.companyName;
      state.roles = action.payload.roles;
      state.isAuthenticated = true;
    },
    clearAuth(state) {
      state.displayName = null;
      state.companyName = null;
      state.roles = [];
      state.isAuthenticated = false;
    },
  },
});

export const { setAuthUser, clearAuth } = authSlice.actions;
export default authSlice.reducer;
