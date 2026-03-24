"use client";

import { useCallback } from "react";
import {
  useInfiniteQuery,
  useQueryClient,
  type InfiniteData,
} from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import type { ChatMessage } from "../types";

// ── Types ─────────────────────────────────────────────────────────────────────

export interface UseChatMessagesReturn {
  /** All messages in chronological order (ASC by seq). */
  messages: ChatMessage[];
  /** Fetch older messages (load more up the scroll). */
  fetchOlderMessages: () => void;
  /** True if there are more older messages to load. */
  hasMore: boolean;
  /** True on initial load or when fetching a new page. */
  isLoading: boolean;
  /** Optimistically append a new message to the query cache. */
  appendMessage: (msg: ChatMessage) => void;
}

// ── Query fetcher ─────────────────────────────────────────────────────────────

async function fetchMessages(
  threadId: string,
  beforeSeq?: number
): Promise<ChatMessage[]> {
  const params = new URLSearchParams({ limit: "50" });
  if (beforeSeq != null) {
    params.set("before_seq", String(beforeSeq));
  }
  return apiGet<ChatMessage[]>(
    `/api/v1/chat/threads/${threadId}/messages?${params.toString()}`
  );
}

// ── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Cursor-based infinite query for chat message history.
 *
 * Pages are fetched in descending order (before_seq = oldest visible seq),
 * but returned to consumers in ascending order (ASC by seq) for rendering.
 *
 * On WebSocket reconnect, useChatWebSocket invalidates this query so any
 * messages missed during disconnection are fetched automatically.
 */
export function useChatMessages(
  threadId: string | null
): UseChatMessagesReturn {
  const queryClient = useQueryClient();

  const {
    data,
    fetchNextPage,
    hasNextPage,
    isLoading,
    isFetchingNextPage,
  } = useInfiniteQuery<
    ChatMessage[],
    Error,
    InfiniteData<ChatMessage[]>,
    [string, string | null],
    number | undefined
  >({
    queryKey: ["chat-messages", threadId],
    enabled: !!threadId,
    queryFn: async ({ pageParam }) => {
      if (!threadId) return [];
      return fetchMessages(threadId, pageParam);
    },
    initialPageParam: undefined,
    getNextPageParam: (lastPage) => {
      // lastPage is the page we just loaded (older messages).
      // If we got a full page (50), there are more; next cursor = lowest seq.
      if (lastPage.length === 50) {
        const lowestSeq = lastPage[0]?.seq;
        return lowestSeq;
      }
      return undefined;
    },
  });

  // Flatten pages in ascending order (chronological, newest at bottom).
  // pages[0] = most recent; pages[N] = oldest. Reverse pages, then each
  // page is already ASC from the API.
  const messages: ChatMessage[] = data
    ? data.pages
        .slice()
        .reverse()
        .flat()
        .sort((a, b) => a.seq - b.seq)
    : [];

  const fetchOlderMessages = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) {
      void fetchNextPage();
    }
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  /**
   * Optimistically append a new message received via WebSocket to the cache.
   *
   * We append to the first (most recent) page so it appears at the bottom
   * of the message list immediately without waiting for a re-fetch.
   */
  const appendMessage = useCallback(
    (msg: ChatMessage) => {
      if (!threadId) return;

      queryClient.setQueryData<InfiniteData<ChatMessage[]>>(
        ["chat-messages", threadId],
        (old) => {
          if (!old) {
            // No cache yet — seed with first page containing this message
            return {
              pages: [[msg]],
              pageParams: [undefined],
            };
          }

          // Dedup: skip if message already in cache
          const allIds = new Set(old.pages.flat().map((m) => m.id));
          if (allIds.has(msg.id)) return old;

          // Append to the first page (most recent)
          const [firstPage, ...rest] = old.pages;
          return {
            ...old,
            pages: [[...firstPage, msg], ...rest],
          };
        }
      );
    },
    [threadId, queryClient]
  );

  return {
    messages,
    fetchOlderMessages,
    hasMore: hasNextPage ?? false,
    isLoading: isLoading || isFetchingNextPage,
    appendMessage,
  };
}
