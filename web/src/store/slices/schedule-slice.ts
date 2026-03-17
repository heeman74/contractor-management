import { createSlice } from "@reduxjs/toolkit";

interface ScheduleUiState {
  filterToolbarCollapsed: boolean;
}

const initialState: ScheduleUiState = {
  filterToolbarCollapsed: true,
};

const scheduleSlice = createSlice({
  name: "schedule",
  initialState,
  reducers: {
    toggleFilterToolbar(state) {
      state.filterToolbarCollapsed = !state.filterToolbarCollapsed;
    },
  },
});

export const { toggleFilterToolbar } = scheduleSlice.actions;

export default scheduleSlice.reducer;
