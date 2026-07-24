export interface StatusHistoryEntry {
  status: string;
  changed_at: string;
  changed_by: string;
}

export interface MaterialItem {
  name: string;
  quantity: number;
  unit: string;
}

export interface ProjectResponse {
  id: string;
  company_id: string;
  name: string;
  description: string | null;
  address: string | null;
  client_id: string | null;
  target_start_date: string | null;
  target_end_date: string | null;
  status: string;
  status_history: StatusHistoryEntry[];
  version: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  trade_scopes?: TradeScopeResponse[];
}

export interface ProjectAssignmentResponse {
  id: string;
  company_id: string;
  project_id: string;
  user_id: string;
  role: string;
  assigned_at: string;
  user_name: string;
  project_name: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface TradeCatalogResponse {
  id: string;
  company_id: string;
  name: string;
  color: string;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface TradeScopeResponse {
  id: string;
  company_id: string;
  project_id: string;
  trade_catalog_id: string | null;
  trade_name: string;
  trade_color: string;
  contractor_id: string | null;
  status: string;
  status_override: boolean;
  sort_order: number;
  version: number;
  created_at: string;
  updated_at: string;
  tasks?: TaskResponse[];
}

export interface TaskResponse {
  id: string;
  company_id: string;
  trade_scope_id: string;
  title: string;
  description: string | null;
  status: string;
  sort_order: number;
  priority: string;
  estimated_hours: number | null;
  estimated_cost: number | null;
  start_date: string | null;
  due_date: string | null;
  zone_id: string | null;
  photo_required: boolean;
  assigned_to: string | null;
  materials_needed: MaterialItem[];
  version: number;
  created_at: string;
  updated_at: string;
}

export interface ContractorMatch {
  id: string;
  name: string;
  email: string;
  has_specialty_match: boolean;
}

export interface ProjectCreate {
  name: string;
  description?: string;
  address?: string;
  client_id?: string;
  target_start_date?: string;
  target_end_date?: string;
}

export interface TradeScopeCreate {
  project_id: string;
  trade_catalog_id?: string;
  trade_name: string;
  trade_color?: string;
  contractor_id?: string;
}

export interface TaskCreate {
  trade_scope_id: string;
  title: string;
  description?: string;
  priority?: string;
  zone_id?: string;
  start_date?: string;
}

export interface TaskAttachmentResponse {
  id: string;
  company_id: string;
  task_id: string;
  attachment_type: string;
  remote_url: string | null;
  local_path: string | null;
  caption: string | null;
  sort_order: number;
  annotation_data: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}
