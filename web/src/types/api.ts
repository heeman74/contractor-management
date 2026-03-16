// Auth
export interface LoginRequest {
  email: string;
  password: string;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  user_id: string;
  company_id: string;
  roles: string[];
}

export interface AuthUser {
  user_id: string;
  company_id: string;
  roles: string[];
}

// Error
export interface ApiErrorResponse {
  detail: string;
}

// Jobs (stub for future phases)
export interface Job {
  id: string;
  title: string;
  status: string;
}

// Add more as needed in future phases
