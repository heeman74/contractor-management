"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import type { SendMessagePayload, WsEvent } from "../types";

// ── Types ─────────────────────────────────────────────────────────────────────

export type ConnectionState = "connected" | "reconnecting" | "disconnected";

export interface UseChatWebSocketOptions {
  /** Called for every incoming WebSocket message event after JSON parse. */
  onMessage?: (event: WsEvent) => void;
}

export interface UseChatWebSocketReturn {
  /** Current connection state. */
  connectionState: ConnectionState;
  /** Send a chat message over the WebSocket. */
  sendMessage: (payload: SendMessagePayload) => void;
  /** Send a typing indicator (debounce externally). */
  sendTyping: () => void;
  /** Send a read receipt for the given sequence number. */
  sendRead: (seq: number) => void;
}

// ── Constants ─────────────────────────────────────────────────────────────────

/** Reconnect backoff delays in milliseconds: 1s → 2s → 4s → 8s → 16s → 32s → 64s */
const BACKOFF_DELAYS = [1000, 2000, 4000, 8000, 16000, 32000, 64000];

/** Heartbeat ping interval in milliseconds (30 seconds). */
const PING_INTERVAL_MS = 30_000;

/** Pong timeout — reconnect if no pong received within this window. */
const PONG_TIMEOUT_MS = 10_000;

// ── Helper: resolve WebSocket URL ────────────────────────────────────────────

/**
 * Build the WebSocket URL for a given thread.
 *
 * Tokens are stored in httpOnly cookies — the proxy strips them from JS.
 * For WebSocket connections we use a short-lived token obtained via
 * GET /api/auth/ws-token (returns a JSON { token: string }).
 *
 * Fallback: if the token endpoint fails, connection proceeds without token
 * and the server will close with 4401. The reconnect loop will retry.
 */
async function getWsToken(): Promise<string | null> {
  try {
    const resp = await fetch("/api/auth/ws-token");
    if (!resp.ok) return null;
    const data = (await resp.json()) as { token?: string };
    return typeof data.token === "string" ? data.token : null;
  } catch {
    return null;
  }
}

function buildWsUrl(threadId: string, token: string | null): string {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const apiHost =
    process.env.NEXT_PUBLIC_API_HOST ?? window.location.host;
  const base = `${protocol}//${apiHost}/api/v1/ws/chat/${threadId}`;
  return token ? `${base}?token=${encodeURIComponent(token)}` : base;
}

// ── Hook ─────────────────────────────────────────────────────────────────────

/**
 * WebSocket hook for a single chat thread.
 *
 * Uses `useRef` for the WebSocket instance (not useState) — keeps the ref
 * stable across re-renders and prevents unnecessary socket close/reopen.
 *
 * Reconnect strategy: exponential backoff capped at 64 seconds.
 * On reconnect: TanStack Query cache for the thread messages is invalidated
 * so the query re-fetches any messages missed during disconnection.
 */
export function useChatWebSocket(
  threadId: string | null,
  options: UseChatWebSocketOptions = {}
): UseChatWebSocketReturn {
  const queryClient = useQueryClient();

  // Stable ref to the latest onMessage callback (avoids stale closure)
  const onMessageRef = useRef(options.onMessage);
  useEffect(() => {
    onMessageRef.current = options.onMessage;
  });

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttemptRef = useRef(0);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pingTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pongTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const unmountedRef = useRef(false);

  const [connectionState, setConnectionState] =
    useState<ConnectionState>("disconnected");

  // ── Ping / pong heartbeat ─────────────────────────────────────────────────

  const clearPingTimer = useCallback(() => {
    if (pingTimerRef.current != null) {
      clearInterval(pingTimerRef.current);
      pingTimerRef.current = null;
    }
  }, []);

  const clearPongTimeout = useCallback(() => {
    if (pongTimeoutRef.current != null) {
      clearTimeout(pongTimeoutRef.current);
      pongTimeoutRef.current = null;
    }
  }, []);

  // ── WebSocket lifecycle ───────────────────────────────────────────────────

  const connect = useCallback(async () => {
    if (!threadId || unmountedRef.current) return;

    const token = await getWsToken();
    if (unmountedRef.current) return;

    const url = buildWsUrl(threadId, token);
    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      if (unmountedRef.current) {
        ws.close();
        return;
      }
      reconnectAttemptRef.current = 0;
      setConnectionState("connected");

      // Start heartbeat
      clearPingTimer();
      pingTimerRef.current = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: "ping" }));

          // Expect pong within PONG_TIMEOUT_MS
          clearPongTimeout();
          pongTimeoutRef.current = setTimeout(() => {
            // No pong received — force reconnect
            ws.close();
          }, PONG_TIMEOUT_MS);
        }
      }, PING_INTERVAL_MS);
    };

    ws.onmessage = (event: MessageEvent) => {
      let parsed: WsEvent;
      try {
        parsed = JSON.parse(event.data as string) as WsEvent;
      } catch {
        return;
      }

      // Clear pong timeout on any message (including pong)
      if (parsed.type === "pong") {
        clearPongTimeout();
        return;
      }

      onMessageRef.current?.(parsed);
    };

    ws.onclose = () => {
      clearPingTimer();
      clearPongTimeout();

      if (unmountedRef.current) return;

      const attempt = reconnectAttemptRef.current;
      const delay =
        BACKOFF_DELAYS[Math.min(attempt, BACKOFF_DELAYS.length - 1)];
      reconnectAttemptRef.current = attempt + 1;

      setConnectionState("reconnecting");

      // Invalidate message cache so we catch up on reconnect
      void queryClient.invalidateQueries({
        queryKey: ["chat-messages", threadId],
      });

      reconnectTimerRef.current = setTimeout(() => {
        void connect();
      }, delay);
    };

    ws.onerror = () => {
      // onclose fires after onerror — reconnect handled there
    };
  }, [threadId, queryClient, clearPingTimer, clearPongTimeout]);

  // ── Effect: open/close on threadId change ────────────────────────────────

  useEffect(() => {
    unmountedRef.current = false;

    if (!threadId) {
      setConnectionState("disconnected");
      return;
    }

    void connect();

    return () => {
      unmountedRef.current = true;

      if (reconnectTimerRef.current != null) {
        clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = null;
      }
      clearPingTimer();
      clearPongTimeout();

      if (wsRef.current) {
        wsRef.current.onclose = null; // prevent reconnect on intentional close
        wsRef.current.close();
        wsRef.current = null;
      }

      setConnectionState("disconnected");
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [threadId]);

  // ── Send helpers ──────────────────────────────────────────────────────────

  const sendMessage = useCallback((payload: SendMessagePayload) => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({ type: "message", ...payload }));
  }, []);

  const sendTyping = useCallback(() => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({ type: "typing" }));
  }, []);

  const sendRead = useCallback((seq: number) => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({ type: "read", seq }));
  }, []);

  return { connectionState, sendMessage, sendTyping, sendRead };
}
