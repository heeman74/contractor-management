"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, useParams } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { ChatBubble } from "@/features/ai/components/ChatBubble";
import { TypingIndicator } from "@/features/ai/components/TypingIndicator";
import { ChatInput } from "@/features/ai/components/ChatInput";
import { TaskPreviewList } from "@/features/ai/components/TaskPreviewList";
import { useInterviewChat } from "@/features/ai/hooks/useInterviewChat";

export default function AIInterviewPage() {
  const router = useRouter();
  const params = useParams<{ id: string; scopeId: string }>();
  const projectId = params.id;
  const scopeId = params.scopeId;

  const {
    messages,
    isStreaming,
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
  } = useInterviewChat();

  const [isSaving, setIsSaving] = useState(false);
  const [tradeName, setTradeName] = useState("this trade");
  const bottomRef = useRef<HTMLDivElement>(null);

  // Start conversation on mount
  useEffect(() => {
    if (scopeId) {
      startConversation(scopeId);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scopeId]);

  // Auto-scroll to bottom on new messages / tokens
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isStreaming]);

  const handleSend = (message: string) => {
    sendMessage(message);
  };

  // "Accept Plan" — triggered when contractor approves the AI-generated task list
  const handleAcceptPlan = async () => {
    if (tasks.length === 0) return;
    setIsSaving(true);
    try {
      await completeInterview(tasks);
      router.push(`/projects/${projectId}`);
    } catch (e) {
      console.error("[AIInterviewPage] completeInterview error:", e);
    } finally {
      setIsSaving(false);
    }
  };

  const handleRestartInterview = async () => {
    // Restart by starting a new conversation for this scope
    await startConversation(scopeId);
  };

  const hasPreview = tasks.length > 0;

  return (
    <div className="flex h-screen flex-col bg-background">
      {/* Fixed header */}
      <header className="flex flex-shrink-0 items-center gap-3 border-b bg-background px-4 py-3">
        <Link
          href={`/projects/${projectId}`}
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" />
          Project
        </Link>
        <Separator orientation="vertical" className="h-4" />
        <h1 className="text-xl font-semibold" style={{ fontSize: "20px", fontWeight: 600 }}>
          AI Interview — {tradeName}
        </h1>
      </header>

      {/* Main area */}
      <div className="flex flex-1 flex-col overflow-hidden">
        {/* Chat section */}
        <div
          className={`flex flex-col overflow-hidden ${hasPreview ? "flex-[2]" : "flex-1"}`}
        >
          <ScrollArea className="flex-1">
            <div className="flex flex-col gap-4 px-4 py-4">
              {messages.length === 0 && !isStreaming && (
                // Empty state
                <div className="flex flex-col items-center justify-center py-16 text-center">
                  <h2 className="text-lg font-semibold">
                    Let&apos;s build your task plan
                  </h2>
                  <p className="mt-2 max-w-sm text-sm text-muted-foreground">
                    I&apos;ll ask you a few questions about your {tradeName} scope to
                    create a detailed task plan.
                  </p>
                </div>
              )}

              {messages.map((msg, i) => (
                <ChatBubble
                  key={msg.id}
                  message={msg}
                  isStreaming={
                    isStreaming && i === messages.length - 1 && msg.role === "assistant"
                  }
                />
              ))}

              {/* Typing indicator */}
              {isStreaming &&
                messages.length > 0 &&
                messages[messages.length - 1]?.role === "assistant" &&
                !messages[messages.length - 1]?.content && (
                  <TypingIndicator />
                )}

              {/* Error display */}
              {error && !isStreaming && (
                <div className="rounded-lg bg-destructive/10 px-4 py-3 text-sm text-destructive">
                  {error}
                </div>
              )}

              <div ref={bottomRef} />
            </div>
          </ScrollArea>
        </div>

        {/* Preview section */}
        {hasPreview && (
          <>
            <Separator />
            <div className="flex-1 overflow-auto px-4 py-4">
              <TaskPreviewList
                tasks={tasks}
                onUpdate={updateTask}
                onRemove={removeTask}
                onReorder={reorderTasks}
                onAddTask={addTask}
                onAcceptPlan={handleAcceptPlan}
                onRestartInterview={handleRestartInterview}
                isLoading={isStreaming && tasks.length === 0}
                isSaving={isSaving}
                tradeName={tradeName}
              />
            </div>
          </>
        )}
      </div>

      {/* Fixed bottom chat input */}
      <div className="flex-shrink-0 border-t bg-background px-4 py-3">
        {conversationId && (
          <ChatInput
            onSend={handleSend}
            isStreaming={isStreaming}
            placeholder="Answer the question above..."
            disabled={isSaving}
          />
        )}
        {!conversationId && (
          <p className="text-center text-sm text-muted-foreground">
            Starting interview...
          </p>
        )}
      </div>
    </div>
  );
}
