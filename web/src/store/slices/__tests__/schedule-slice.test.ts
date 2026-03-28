import scheduleReducer, { toggleFilterToolbar } from "../schedule-slice";

describe("schedule-slice", () => {
  test("has correct initial state", () => {
    const state = scheduleReducer(undefined, { type: "@@INIT" });
    expect(state.filterToolbarCollapsed).toBe(true);
  });

  test("toggleFilterToolbar flips the collapsed state", () => {
    let state = scheduleReducer(undefined, { type: "@@INIT" });
    expect(state.filterToolbarCollapsed).toBe(true);

    state = scheduleReducer(state, toggleFilterToolbar());
    expect(state.filterToolbarCollapsed).toBe(false);

    state = scheduleReducer(state, toggleFilterToolbar());
    expect(state.filterToolbarCollapsed).toBe(true);
  });
});
