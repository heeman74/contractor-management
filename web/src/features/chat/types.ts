/**
 * TypeScript types for Phase 23 Real-Time Chat.
 *
 * These types mirror the backend Pydantic schemas in
 * backend/app/features/chat/schemas.py exactly.
 */

// ── Enumerations ─────────────────────────────────────────────────────────────

export type ThreadType = "scope" | "project_wide";
export type AttachmentType = "photo" | "pdf" | "annotated_photo";
export type MessageStatus = "pending" | "sent" | "read" | "failed";

// ── Domain objects ────────────────────────────────────────────────────────────

export interface ChatThread {
  id: string;
  project_id: string;
  thread_type: ThreadType;
  trade_scope_id: string | null;
  name: string;
  created_at: string;
  last_message?: ChatMessage | null;
  unread_count: number;
  member_count: number;
}

export interface ChatMessage {
  id: string;
  thread_id: string;
  sender_id: string;
  sender_name: string;
  content: string | null;
  seq: number;
  attachment_url: string | null;
  attachment_type: AttachmentType | null;
  annotation_data: string | null;
  mentions: string[]; // user IDs
  mention_all: boolean;
  created_at: string;
}

export interface ChatReadReceipt {
  user_id: string;
  user_name: string;
  last_read_seq: number;
  read_at: string;
}

// ── Request / send payloads ───────────────────────────────────────────────────

export interface SendMessagePayload {
  id: string; // client-generated UUID for deduplication
  content?: string;
  attachment_url?: string;
  attachment_type?: AttachmentType;
  annotation_data?: string;
  mentions?: string[];
  mention_all?: boolean;
}

// ── WebSocket event types ─────────────────────────────────────────────────────

/**
 * Incoming WebSocket events dispatched from the backend.
 *
 * Union discriminated by `type`.
 */
export type WsEvent =
  | { type: "message"; message: ChatMessage }
  | { type: "typing"; user_id: string; user_name: string }
  | { type: "read_receipt"; user_id: string; last_read_seq: number }
  | { type: "pong" };

/**
 * Outgoing WebSocket events sent by the client.
 */
export type WsOutEvent =
  | { type: "message" } & SendMessagePayload
  | { type: "typing" }
  | { type: "read"; seq: number }
  | { type: "ping" };
