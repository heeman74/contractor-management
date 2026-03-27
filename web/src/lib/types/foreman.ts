// Foreman role types — project assignments and daily status updates

export interface ProjectAssignment {
  id: string;
  company_id: string;
  project_id: string;
  user_id: string;
  role: string;
  assigned_at: string;
  project_name?: string;
  user_name?: string;
}

export interface ProjectStatusUpdate {
  id: string;
  company_id: string;
  project_id: string;
  author_id: string;
  author_name?: string;
  status_text: string;
  weather_conditions: string | null;
  workers_on_site: number | null;
  safety_incidents: number;
  blockers: string | null;
  photos: string[];
  report_date: string;
  created_at: string;
}

export interface CreateStatusUpdatePayload {
  project_id: string;
  status_text: string;
  weather_conditions?: string | null;
  workers_on_site?: number | null;
  safety_incidents?: number;
  blockers?: string | null;
}

export interface AssignForemanPayload {
  project_id: string;
  user_id: string;
}
