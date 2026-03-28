"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { ChevronDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import { useChatMessages } from "../hooks/useChatMessages";
import { useChatWebSocket } from "../hooks/useChatWebSocket";
import { MessageBubble } from "./MessageBubble";
import type { ChatMessage, WsEvent } from "../types";

// ── Date separator helpers ────────────────────────────────────────────────────

function formatDateSeparator(isoString: string): string {
  const date = new Date(isoString);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);

  if (date.toDateString() === today.toDateString()) return "Today";
  if (date.toDateString() === yesterday.toDateString()) return "Yesterday";
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function isSameDay(a: string, b: string): boolean {
  return new Date(a).toDateString() === new Date(b).toDateString();
}

// ── Typing indicator ──────────────────────────────────────────────────────────

interface TypingState {
  userId: string;
  userName: string;
  expiresAt: number;
}

// ── Component ─────────────────────────────────────────────────────────────────

export interface MessageListProps {
  threadId: string;
  currentUserId: string;
  /** Called when the last visible message's seq changes (for read receipts). */
  onRead?: (seq: number) => void;
}

/**
 * Scrollable message list with:
 * - Infinite scroll (load older messages on scroll to top)
 * - Date separators between different-day messages
 * - Scroll-to-bottom FAB when scrolled up > 200px
 * - Typing indicator (auto-hides after 3s)
 * - Real-time WebSocket message append
 * - Read receipt emission via IntersectionObserver on bottom sentinel
 */
export function MessageList({
  threadId,
  currentUserId,
  onRead,
}: MessageListProps) {
  const { messages, fetchOlderMessages, hasMore, isLoading, appendMessage } =
    useChatMessages(threadId);

  const [typingUsers, setTypingUsers] = useState<TypingState[]>([]);
  const [showScrollDown, setShowScrollDown] = useState(false);

  const scrollRef = useRef<HTMLDivElement>(null);
  const bottomSentinelRef = useRef<HTMLDivElement>(null);
  const topSentinelRef = useRef<HTMLDivElement>(null);
  const isNearBottomRef = useRef(true);
  const typingCleanupRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ── WebSocket message handler ──────────────────────────────────────────────

  const handleWsMessage = useCallback(
    (event: WsEvent) => {
      if (event.type === "message") {
        appendMessage(event.message);
      } else if (event.type === "typing") {
        setTypingUsers((prev) => {
          const filtered = prev.filter((t) => t.userId !== event.user_id);
          return [
            ...filtered,
            {
              userId: event.user_id,
              userName: event.user_name,
              expiresAt: Date.now() + 3000,
            },
          ];
        });
      }
    },
    [appendMessage]
  );

  useChatWebSocket(threadId, { onMessage: handleWsMessage });

  // ── Typing indicator cleanup ───────────────────────────────────────────────

  useEffect(() => {
    typingCleanupRef.current = setInterval(() => {
      const now = Date.now();
      setTypingUsers((prev) => prev.filter((t) => t.expiresAt > now));
    }, 500);

    return () => {
      if (typingCleanupRef.current)
        clearInterval(typingCleanupRef.current);
    };
  }, []);

  // ── Auto-scroll to bottom on new messages ────────────────────────────────

  useEffect(() => {
    if (isNearBottomRef.current && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages.length]);

  // Initial scroll to bottom
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [threadId]);

  // ── Scroll position tracking ──────────────────────────────────────────────

  function handleScroll() {
    const el = scrollRef.current;
    if (!el) return;
    const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    isNearBottomRef.current = distFromBottom < 200;
    setShowScrollDown(distFromBottom > 200);
  }

  // ── IntersectionObserver: top sentinel → load older ──────────────────────

  useEffect(() => {
    const sentinel = topSentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting && hasMore && !isLoading) {
          fetchOlderMessages();
        }
      },
      { root: scrollRef.current, threshold: 0.1 }
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [hasMore, isLoading, fetchOlderMessages]);

  // ── IntersectionObserver: bottom sentinel → send read receipt ────────────

  useEffect(() => {
    const sentinel = bottomSentinelRef.current;
    if (!sentinel || !onRead) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting && messages.length > 0) {
          const lastSeq = messages[messages.length - 1]?.seq;
          if (lastSeq != null) onRead(lastSeq);
        }
      },
      { root: scrollRef.current, threshold: 0.5 }
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [messages, onRead]);

  // ── Render ────────────────────────────────────────────────────────────────

  // typingUsers is already cleaned up by the 500ms interval, so use directly
  const activeTyping = typingUsers;

  return (
    <div className="relative flex flex-1 flex-col overflow-hidden">
      <ScrollArea
        className="flex-1"
        role="log"
        aria-live="polite"
        aria-label="Messages"
      >
        <div
          ref={scrollRef}
          className="flex h-full flex-col overflow-y-auto"
          onScroll={handleScroll}
        >
          {/* Top sentinel — triggers older message load */}
          <div ref={topSentinelRef} className="h-px" />

          {/* Loading indicator */}
          {isLoading && (
            <p className="py-3 text-center text-xs text-muted-foreground">
              Loading messages...
            </p>
          )}

          {/* Load older button (accessible fallback) */}
          {hasMore && !isLoading && (
            <button
              type="button"
              className="mx-auto my-2 block text-xs text-primary underline-offset-2 hover:underline"
              onClick={fetchOlderMessages}
            >
              Load older messages
            </button>
          )}

          {/* Message list with date separators */}
          {renderMessages(messages, currentUserId)}

          {/* Typing indicator */}
          {activeTyping.length > 0 && (
            <TypingIndicator name={activeTyping[0]!.userName} />
          )}

          {/* Bottom sentinel — triggers read receipt */}
          <div ref={bottomSentinelRef} className="h-px" />
        </div>
      </ScrollArea>

      {/* Scroll-to-bottom FAB */}
      {showScrollDown && (
        <Button
          variant="secondary"
          size="icon"
          className={cn(
            "absolute bottom-4 right-4 z-10 size-8 rounded-full shadow-md"
          )}
          onClick={() => {
            if (scrollRef.current) {
              scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
            }
          }}
          aria-label="Scroll to latest messages"
        >
          <ChevronDown className="size-4" />
        </Button>
      )}
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function renderMessages(
  messages: ChatMessage[],
  currentUserId: string
): React.ReactNode {
  const elements: React.ReactNode[] = [];

  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i]!;
    const prev = messages[i - 1];

    // Date separator
    if (!prev || !isSameDay(prev.created_at, msg.created_at)) {
      elements.push(
        <div
          key={`sep-${msg.id}`}
          className="flex items-center gap-3 px-4 py-2"
        >
          <hr className="flex-1 border-border" />
          <span className="text-xs text-muted-foreground">
            {formatDateSeparator(msg.created_at)}
          </span>
          <hr className="flex-1 border-border" />
        </div>
      );
    }

    elements.push(
      <MessageBubble
        key={msg.id}
        message={msg}
        isOwn={msg.sender_id === currentUserId}
      />
    );
  }

  return elements;
}

function TypingIndicator({ name }: { name: string }) {
  return (
    <div
      className="flex items-center gap-2 px-4 py-1"
      aria-label={`${name} is typing`}
      aria-live="polite"
    >
      <div className="flex gap-1">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="size-2 animate-bounce rounded-full bg-muted-foreground"
            style={{ animationDelay: `${i * 150}ms` }}
          />
        ))}
      </div>
      <span className="text-xs text-muted-foreground">{name} is typing...</span>
    </div>
  );
}
