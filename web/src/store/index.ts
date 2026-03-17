import { configureStore } from "@reduxjs/toolkit";
import uiReducer from "./slices/ui-slice";
import authReducer from "./slices/auth-slice";
import scheduleReducer from "./slices/schedule-slice";

export const makeStore = () =>
  configureStore({ reducer: { ui: uiReducer, auth: authReducer, schedule: scheduleReducer } });

export type AppStore = ReturnType<typeof makeStore>;
export type RootState = ReturnType<AppStore["getState"]>;
export type AppDispatch = AppStore["dispatch"];
