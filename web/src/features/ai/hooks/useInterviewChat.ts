"use client";

import { useState, useCallback } from "react";
import { parseSSELine } from "./useIntakeChat";
import type { ChatMessage, ToolCall } from "./useIntakeChat";

// --- Types ---

export interface TaskPreview {
  title: string;
  description?: string;
  priority?: "low" | "medium" | "high";
  estimated_hours?: number;
  sort_order: number;
  materials_needed?: string;
}

interface ConversationResponse {
  id: string;
}

interface CompleteInterviewResponse {
  task_ids: string[];
}

// --- Hook ---

interface UseInterviewChatReturn {
  messages: ChatMessage[];
  isStreaming: boolean;
  currentStreamText: string;
  tasks: TaskPreview[];
  error: string | null;
  conversationId: string | null;
  startConversation: (scopeId: string) => Promise<void>;
  sendMessage: (message: string) => Promise<void>;
  completeInterview: (editedTasks: TaskPreview[]) => Promise<string[]>;
  updateTask: (index: number, updates: Partial<TaskPreview>) => void;
  removeTask: (index: number) => void;
  addTask: () => void;
  reorderTasks: (newOrder: TaskPreview[]) => void;
}

export function useInterviewChat(): UseInterviewChatReturn {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [currentStreamText, setCurrentStreamText] = useState("");
  const [tasks, setTasks] = useState<TaskPreview[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);

  const addMessage = useCallback((msg: ChatMessage) => {
    setMessages((prev) => [...prev, msg]);
  }, []);

  const updateLastAssistantMessage = useCallback(
    (content: string, toolCalls?: ToolCall[]) => {
      setMessages((prev) => {
        const copy = [...prev];
        for (let i = copy.length - 1; i >= 0; i--) {
          if (copy[i].role === "assistant") {
            copy[i] = {
              ...copy[i],
              content,
              ...(toolCalls !== undefined ? { toolCalls } : {}),
            };
            return copy;
          }
        }
        return copy;
      });
    },
    []
  );

  const startConversation = useCallback(async (scopeId: string) => {
    try {
      const res = await fetch(
        `/api/ai-chat?path=${encodeURIComponent(`/api/v1/ai/interview/start?scope_id=${encodeURIComponent(scopeId)}`)}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        }
      );

      if (!res.ok) {
        const body = await res.json().catch(() => ({ detail: "Failed to start interview" }));
        setError((body as { detail?: string }).detail ?? "Failed to start interview");
        return;
      }

      const conv = (await res.json()) as ConversationResponse;
      setConversationId(conv.id);
      setMessages([]);
      setTasks([]);
      setError(null);
    } catch (e) {
      setError("Failed to start interview. Please check your connection.");
      console.error("[useInterviewChat] startConversation error:", e);
    }
  }, []);

  const sendMessage = useCallback(
    async (message: string) => {
      if (!conversationId) return;

      setError(null);

      const userMsg: ChatMessage = {
        id: crypto.randomUUID(),
        role: "user",
        content: message,
        timestamp: new Date(),
      };
      addMessage(userMsg);

      const assistantMsg: ChatMessage = {
        id: crypto.randomUUID(),
        role: "assistant",
        content: "",
        timestamp: new Date(),
      };
      addMessage(assistantMsg);

      setIsStreaming(true);
      setCurrentStreamText("");

      let accumulatedText = "";
      const pendingToolCalls: ToolCall[] = [];

      try {
        const res = await fetch(
          `/api/ai-chat?path=${encodeURIComponent("/api/v1/ai/interview/message")}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ conversation_id: conversationId, message }),
          }
        );

        if (!res.ok) {
          const body = await res.json().catch(() => ({ detail: "AI request failed" }));
          const errMsg = (body as { detail?: string }).detail ?? "AI request failed";
          setError(errMsg);
          updateLastAssistantMessage("Something went wrong. Please try again.");
          setIsStreaming(false);
          return;
        }

        if (!res.body) {
          setError("No response body");
          setIsStreaming(false);
          return;
        }

        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
        let buffer = "";

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += value;
          const parts = buffer.split("\n\n");
          buffer = parts.pop() ?? "";

          for (const part of parts) {
            const trimmed = part.trim();
            if (!trimmed) continue;

            const parsed = parseSSELine(trimmed);
            if (!parsed) continue;

            const { event, data } = parsed;

            if (event === "token") {
              const tokenData = data as { delta?: string };
              const delta = tokenData.delta ?? "";
              accumulatedText += delta;
              setCurrentStreamText(accumulatedText);
              updateLastAssistantMessage(accumulatedText);
            } else if (event === "tool_call") {
              const tcData = data as {
                tool?: string;
                input?: Record<string, unknown>;
                id?: string;
              };
              const toolCall: ToolCall = {
                tool: tcData.tool ?? "",
                input: tcData.input ?? {},
                id: tcData.id ?? "",
              };
              pendingToolCalls.push(toolCall);

              if (tcData.tool === "create_task") {
                const taskInput = tcData.input as {
                  title?: string;
                  description?: string;
                  priority?: "low" | "medium" | "high";
                  estimated_hours?: number;
                  sort_order?: number;
                  materials_needed?: string;
                };
                setTasks((prev) => [
                  ...prev,
                  {
                    title: taskInput.title ?? "",
                    description: taskInput.description,
                    priority: taskInput.priority,
                    estimated_hours: taskInput.estimated_hours,
                    sort_order: taskInput.sort_order ?? prev.length,
                    materials_needed: taskInput.materials_needed,
                  },
                ]);
                const transitional = "Generating your task plan...";
                accumulatedText = transitional;
                updateLastAssistantMessage(transitional, [...pendingToolCalls]);
              }
            } else if (event === "done") {
              updateLastAssistantMessage(
                accumulatedText || "Done.",
                pendingToolCalls.length > 0 ? pendingToolCalls : undefined
              );
              setIsStreaming(false);
              setCurrentStreamText("");
            } else if (event === "error") {
              const errData = data as { message?: string };
              const errMsg = errData.message ?? "Something went wrong.";
              setError(errMsg);
              updateLastAssistantMessage(
                "Something went wrong. Please try again.\n\nIf the problem persists, check your connection and reload."
              );
              setIsStreaming(false);
            }
          }
        }

        if (buffer.trim()) {
          const parsed = parseSSELine(buffer.trim());
          if (parsed?.event === "done") {
            updateLastAssistantMessage(accumulatedText || "Done.");
          }
        }

        setIsStreaming(false);
        setCurrentStreamText("");
      } catch (e) {
        console.error("[useInterviewChat] sendMessage error:", e);
        setError("Connection lost. Please check your internet connection and try again.");
        updateLastAssistantMessage(
          "Connection lost. Please check your internet connection and try again."
        );
        setIsStreaming(false);
        setCurrentStreamText("");
      }
    },
    [conversationId, addMessage, updateLastAssistantMessage]
  );

  const completeInterview = useCallback(
    async (editedTasks: TaskPreview[]): Promise<string[]> => {
      if (!conversationId) throw new Error("No active conversation");

      const res = await fetch(
        `/api/ai-chat?path=${encodeURIComponent("/api/v1/ai/interview/complete")}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            conversation_id: conversationId,
            tasks: editedTasks,
          }),
        }
      );

      if (!res.ok) {
        const body = await res.json().catch(() => ({ detail: "Failed to complete interview" }));
        throw new Error(
          (body as { detail?: string }).detail ?? "Failed to complete interview"
        );
      }

      const result = (await res.json()) as CompleteInterviewResponse;
      return result.task_ids;
    },
    [conversationId]
  );

  const updateTask = useCallback(
    (index: number, updates: Partial<TaskPreview>) => {
      setTasks((prev) =>
        prev.map((task, i) => (i === index ? { ...task, ...updates } : task))
      );
    },
    []
  );

  const removeTask = useCallback((index: number) => {
    setTasks((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const addTask = useCallback(() => {
    setTasks((prev) => [
      ...prev,
      {
        title: "New Task",
        sort_order: prev.length,
        priority: "medium",
      },
    ]);
  }, []);

  const reorderTasks = useCallback((newOrder: TaskPreview[]) => {
    setTasks(newOrder.map((task, i) => ({ ...task, sort_order: i })));
  }, []);

  return {
    messages,
    isStreaming,
    currentStreamText,
    tasks,
    error,
    conversationId,
    startConversation,
    sendMessage,
    completeInterview,
    updateTask,
    removeTask,
    addTask,
    reorderTasks,
  };
}
