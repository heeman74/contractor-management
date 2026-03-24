"use client";

import { Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { ChatThread } from "../types";

// ── Chart color cycle for trade scope threads ────────────────────────────────

const TRADE_COLORS = [
  "bg-[hsl(var(--chart-1))]",
  "bg-[hsl(var(--chart-2))]",
  "bg-[hsl(var(--chart-3))]",
  "bg-[hsl(var(--chart-4))]",
  "bg-[hsl(var(--chart-5))]",
];

function getTradeColor(threadId: string): string {
  // Deterministic color based on thread ID character codes
  const sum = threadId
    .split("")
    .reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
  return TRADE_COLORS[sum % TRADE_COLORS.length];
}

// ── Relative timestamp ────────────────────────────────────────────────────────

function formatRelativeTime(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60_000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return "now";
  if (diffMins < 60) return `${diffMins}m`;
  if (diffHours < 24) return `${diffHours}h`;
  if (diffDays < 7) return `${diffDays}d`;

  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

// ── Component ─────────────────────────────────────────────────────────────────

export interface ChatThreadRowProps {
  thread: ChatThread;
  isSelected: boolean;
  onClick: () => void;
}

/**
 * A single thread row in the ChatThreadList.
 *
 * Layout: flex row with type indicator, name + preview, timestamp + badge.
 * Selected state: bg-muted background.
 */
export function ChatThreadRow({
  thread,
  isSelected,
  onClick,
}: ChatThreadRowProps) {
  const hasUnread = thread.unread_count > 0;
  const unreadLabel =
    thread.unread_count > 99 ? "99+" : String(thread.unread_count);

  const lastMessageText =
    thread.last_message?.content ??
    (thread.last_message ? "Shared an attachment" : "No messages yet");

  const timestamp = thread.last_message?.created_at ?? thread.created_at;

  return (
    <Button
      variant="ghost"
      className={cn(
        "flex h-auto w-full items-center gap-3 px-4 py-2 text-left",
        "min-h-14 rounded-none",
        isSelected && "bg-muted"
      )}
      onClick={onClick}
      aria-current={isSelected ? "true" : undefined}
    >
      {/* Thread type indicator */}
      {thread.thread_type === "scope" ? (
        <span
          className={cn(
            "size-3 shrink-0 rounded-full",
            getTradeColor(thread.id)
          )}
          aria-hidden="true"
        />
      ) : (
        <Users
          className="size-4 shrink-0 text-muted-foreground"
          aria-hidden="true"
        />
      )}

      {/* Name + preview */}
      <div className="min-w-0 flex-1">
        <p
          className={cn(
            "truncate text-base leading-tight",
            hasUnread ? "font-semibold" : "font-normal"
          )}
        >
          {thread.name}
        </p>
        <p className="truncate text-xs text-muted-foreground">
          {lastMessageText}
        </p>
      </div>

      {/* Timestamp + unread badge */}
      <div className="flex shrink-0 flex-col items-end gap-1">
        <span className="text-xs text-muted-foreground">
          {formatRelativeTime(timestamp)}
        </span>
        {hasUnread && (
          <Badge
            className={cn(
              "flex h-5 min-w-5 items-center justify-center rounded-full px-1",
              "bg-primary text-primary-foreground text-xs"
            )}
            aria-label={`${thread.unread_count} unread messages`}
          >
            {unreadLabel}
          </Badge>
        )}
      </div>
    </Button>
  );
}
