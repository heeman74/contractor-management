// Delegation to the feature-first implementation in features/jobs/presentation/.
// The router imports this file; the real screen widget lives in the jobs feature
// directory following the project's feature-first structure (CLAUDE.md).
//
// This re-export keeps the router import path stable while co-locating the
// request review implementation with the jobs domain that owns the data.
export '../../../../features/jobs/presentation/screens/request_review_screen.dart';
