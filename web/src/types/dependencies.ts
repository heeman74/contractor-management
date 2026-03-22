export interface TaskDependencyResponse {
  id: string;
  predecessor_task_id: string;
  successor_task_id: string;
  dependency_type: "FS" | "SS" | "FF" | "SE";
  lag_days: number;
  company_id: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface TaskDependencyCreate {
  predecessor_task_id: string;
  dependency_type: "FS" | "SS" | "FF" | "SE";
  lag_days: number;
}

export interface ProjectZoneResponse {
  id: string;
  project_id: string;
  name: string;
  company_id: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface ProjectZoneCreate {
  name: string;
}

export interface ConflictRecord {
  task1_id: string;
  task1_title: string;
  task1_trade_name: string;
  task2_id: string;
  task2_title: string;
  task2_trade_name: string;
  zone_name: string;
  conflict_date: string;
}

export interface CycleErrorDetail {
  message: string;
  cycle: string[];
  cycle_ids: string[];
}
