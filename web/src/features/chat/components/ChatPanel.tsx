"use client";

import { useState } from "react";
import { ArrowLeft } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { apiGet } from "@/lib/api-client";
import { ChatThreadList } from "./ChatThreadList";
import { MessageList } from "./MessageList";
import { MessageInput } from "./MessageInput";
import { useChatWebSocket } from "../hooks/useChatWebSocket";
import type { ChatThread, SendMessagePayload } from "../types";

// ── Component ─────────────────────────────────────────────────────────────────

export interface ChatPanelProps {
  projectId: string;
  /** Current authenticated user ID. */
  currentUserId: string;
}

/**
 * Split-panel chat UI for the web project view.
 *
 * Layout:
 *   - Desktop (>= 768px): flex row — thread list (30%, min 280px) + message area (70%)
 *   - Mobile (< 768px): show thread list OR message view (not both)
 *
 * WebSocket connection state indicator: yellow dot in header when reconnecting.
 */
export function ChatPanel({ projectId, currentUserId }: ChatPanelProps) {
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null);
  const [showMobileMessages, setShowMobileMessages] = useState(false);

  // Fetch thread list
  const { data: threads = [], isLoading: threadsLoading } = useQuery<
    ChatThread[]
  >({
    queryKey: ["chat-threads", projectId],
    queryFn: () =>
      apiGet<ChatThread[]>(
        `/api/v1/chat/threads?project_id=${encodeURIComponent(projectId)}`
      ),
  });

  const selectedThread = threads.find((t) => t.id === selectedThreadId) ?? null;

  // WebSocket for connection state indicator
  const { connectionState, sendMessage, sendRead } = useChatWebSocket(
    selectedThreadId
  );

  function handleSelectThread(id: string) {
    setSelectedThreadId(id);
    setShowMobileMessages(true);
  }

  function handleSend(payload: SendMessagePayload) {
    sendMessage(payload);
  }

  return (
    <div className="flex h-full min-h-0 overflow-hidden rounded-lg border">
      {/* ── Thread list panel ── */}
      <div
        className={cn(
          "flex w-full flex-col border-r md:w-[30%] md:min-w-[280px]",
          showMobileMessages ? "hidden md:flex" : "flex"
        )}
      >
        {/* Panel header */}
        <div className="flex items-center justify-between border-b px-4 py-3">
          <h2 className="text-xl font-semibold">Messages</h2>
          {connectionState === "reconnecting" && (
            <span
              className="size-2 rounded-full bg-yellow-400"
              aria-label="Reconnecting..."
              title="Reconnecting..."
            />
          )}
        </div>

        {/* Thread list */}
        {threadsLoading ? (
          <div className="flex flex-1 items-center justify-center">
            <p className="text-sm text-muted-foreground">Loading...</p>
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto">
            <ChatThreadList
              threads={threads}
              selectedId={selectedThreadId}
              onSelect={handleSelectThread}
            />
          </div>
        )}
      </div>

      {/* ── Message area ── */}
      <div
        className={cn(
          "flex flex-1 flex-col",
          !showMobileMessages && !selectedThread ? "hidden md:flex" : "flex"
        )}
      >
        {selectedThread ? (
          <>
            {/* Thread header */}
            <div className="flex items-center gap-2 border-b px-4 py-3">
              {/* Mobile back button */}
              <Button
                variant="ghost"
                size="icon"
                className="md:hidden"
                onClick={() => setShowMobileMessages(false)}
                aria-label="Back to thread list"
              >
                <ArrowLeft className="size-4" />
              </Button>
              <div className="min-w-0 flex-1">
                <h3 className="truncate text-base font-semibold">
                  {selectedThread.name}
                </h3>
                {selectedThread.thread_type === "project_wide" && (
                  <p className="text-xs text-muted-foreground">
                    {selectedThread.member_count} members
                  </p>
                )}
              </div>
              {connectionState === "reconnecting" && (
                <span
                  className="size-2 rounded-full bg-yellow-400"
                  aria-label="Reconnecting..."
                />
              )}
            </div>

            {/* Messages */}
            <MessageList
              threadId={selectedThread.id}
              currentUserId={currentUserId}
              onRead={(seq) => sendRead(seq)}
            />

            {/* Input */}
            <MessageInput
              threadId={selectedThread.id}
              threadName={selectedThread.name}
              onSend={handleSend}
              onTyping={() => {
                /* sendTyping handled in MessageInput debounce via parent */
              }}
            />
          </>
        ) : (
          <div className="flex flex-1 items-center justify-center">
            <p className="text-sm text-muted-foreground">
              Select a conversation to start messaging
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
