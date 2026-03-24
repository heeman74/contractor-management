"use client";

import { ChatThreadRow } from "./ChatThreadRow";
import type { ChatThread } from "../types";

// ── Component ─────────────────────────────────────────────────────────────────

export interface ChatThreadListProps {
  threads: ChatThread[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

/**
 * Sectioned thread list with "Trade Conversations" and "Project Group" sections.
 *
 * Sort order: unread first (desc by unread_count), then by last message
 * created_at desc within each section.
 */
export function ChatThreadList({
  threads,
  selectedId,
  onSelect,
}: ChatThreadListProps) {
  const scopeThreads = threads
    .filter((t) => t.thread_type === "scope")
    .sort(sortThreads);

  const projectWideThreads = threads
    .filter((t) => t.thread_type === "project_wide")
    .sort(sortThreads);

  if (threads.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center px-6 py-12 text-center">
        <p className="text-base font-semibold text-foreground">
          No conversations yet
        </p>
        <p className="mt-2 text-sm text-muted-foreground">
          Conversations are created automatically when a contractor is assigned
          to a trade scope.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col">
      {scopeThreads.length > 0 && (
        <section aria-label="Trade Conversations">
          <p className="mt-6 px-4 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Trade Conversations
          </p>
          {scopeThreads.map((thread) => (
            <ChatThreadRow
              key={thread.id}
              thread={thread}
              isSelected={thread.id === selectedId}
              onClick={() => onSelect(thread.id)}
            />
          ))}
        </section>
      )}

      {projectWideThreads.length > 0 && (
        <section aria-label="Project Group">
          <p className="mt-6 px-4 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Project Group
          </p>
          {projectWideThreads.map((thread) => (
            <ChatThreadRow
              key={thread.id}
              thread={thread}
              isSelected={thread.id === selectedId}
              onClick={() => onSelect(thread.id)}
            />
          ))}
        </section>
      )}
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function sortThreads(a: ChatThread, b: ChatThread): number {
  // Unread first
  if (b.unread_count !== a.unread_count) {
    return b.unread_count - a.unread_count;
  }
  // Then by last message desc
  const aTime = a.last_message?.created_at ?? a.created_at;
  const bTime = b.last_message?.created_at ?? b.created_at;
  return bTime.localeCompare(aTime);
}
