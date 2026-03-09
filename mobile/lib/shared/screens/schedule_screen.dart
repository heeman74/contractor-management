// Re-exports the Phase 5 schedule screen implementation.
//
// The placeholder was replaced in Phase 5 (Plan 02) with the full admin
// dispatch calendar. The router imports from this path — this re-export
// keeps the router import path stable while the implementation lives in
// the feature-first structure (features/schedule/presentation/screens/).
export '../../features/schedule/presentation/screens/schedule_screen.dart'
    show ScheduleScreen;
