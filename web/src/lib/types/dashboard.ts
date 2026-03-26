// Dashboard monitoring types — GC cross-trade project monitoring

export interface TradeStatusBadge {
  trade_scope_id: string;
  trade_name: string;
  status: "on_track" | "at_risk" | "blocked";
  completion_pct: number;
  task_count: number;
  completed_count: number;
}

export interface ProjectStatusCard {
  project_id: string;
  project_name: string;
  status: string;
  overall_completion_pct: number;
  trade_statuses: TradeStatusBadge[];
  active_alert_count: number;
}

export interface TradeTaskDetail {
  task_id: string;
  title: string;
  status: string;
  assignee_name: string | null;
  start_date: string | null;
  due_date: string | null;
  dependency_status: string;
}

export interface ReschedulingSuggestion {
  task_id: string;
  new_start_date: string;
  new_due_date: string;
  reason: string;
}

export interface DashboardAlert {
  id: string;
  project_id: string;
  trade_scope_id: string | null;
  severity: "info" | "warning" | "critical";
  alert_type: string;
  days_behind: number | null;
  impact_text: string;
  remediation_text: string | null;
  affected_scope_ids: string[];
  is_read: boolean;
  rescheduling_payload: ReschedulingSuggestion[] | null;
  rescheduling_accepted: boolean | null;
  created_at: string;
}

export interface TradeTimelineScope {
  id: string;
  trade_name: string;
  start_date: string;
  end_date: string;
  progress: number;
}

export interface TradeTimelineDep {
  source_id: string;
  target_id: string;
  type: string;
}

export interface TradeTimelineData {
  scopes: TradeTimelineScope[];
  dependencies: TradeTimelineDep[];
}
