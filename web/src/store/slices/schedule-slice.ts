import { createSlice, PayloadAction } from "@reduxjs/toolkit";

interface ScheduleUiState {
  filterToolbarCollapsed: boolean;
  selectedBookingId: string | null;
  bookingPanelOpen: boolean;
  conflictModalOpen: boolean;
}

const initialState: ScheduleUiState = {
  filterToolbarCollapsed: true,
  selectedBookingId: null,
  bookingPanelOpen: false,
  conflictModalOpen: false,
};

const scheduleSlice = createSlice({
  name: "schedule",
  initialState,
  reducers: {
    toggleFilterToolbar(state) {
      state.filterToolbarCollapsed = !state.filterToolbarCollapsed;
    },
    openBookingPanel(state, action: PayloadAction<string>) {
      state.selectedBookingId = action.payload;
      state.bookingPanelOpen = true;
    },
    closeBookingPanel(state) {
      state.bookingPanelOpen = false;
      state.selectedBookingId = null;
    },
    openConflictModal(state) {
      state.conflictModalOpen = true;
    },
    closeConflictModal(state) {
      state.conflictModalOpen = false;
    },
  },
});

export const {
  toggleFilterToolbar,
  openBookingPanel,
  closeBookingPanel,
  openConflictModal,
  closeConflictModal,
} = scheduleSlice.actions;

export default scheduleSlice.reducer;
