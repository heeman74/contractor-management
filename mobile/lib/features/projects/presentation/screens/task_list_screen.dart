// Task list is integrated directly into TradeScopeDetailScreen per plan
// (plan 19-04 note: "if trade_scope_detail handles tasks directly, this can be merged").
//
// This file re-exports TradeScopeDetailScreen as an alias so any future callers
// can import task_list_screen.dart without breaking if the two are later split.

export 'trade_scope_detail_screen.dart' show TradeScopeDetailScreen;
