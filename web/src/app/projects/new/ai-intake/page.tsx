"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { ChatBubble } from "@/features/ai/components/ChatBubble";
import { TypingIndicator } from "@/features/ai/components/TypingIndicator";
import { ChatInput } from "@/features/ai/components/ChatInput";
import { TradeScopePreviewCard } from "@/features/ai/components/TradeScopePreviewCard";
import { useIntakeChat } from "@/features/ai/hooks/useIntakeChat";

export default function AIIntakePage() {
  return (
    <Suspense fallback={<div className="flex h-screen items-center justify-center">Loading...</div>}>
      <AIIntakeContent />
    </Suspense>
  );
}

function AIIntakeContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const projectId = searchParams.get("project_id") ?? undefined;

  const {
    messages,
    isStreaming,
    tradeScopes,
    error,
    conversationId,
    startConversation,
    sendMessage,
    completeIntake,
    removeTradeScope,
    updateTradeScope,
    reorderTradeScopes,
  } = useIntakeChat();

  const [isSaving, setIsSaving] = useState(false);
  const [projectName] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  // Start conversation on mount
  useEffect(() => {
    startConversation(projectId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Auto-scroll to bottom on new messages / tokens
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isStreaming]);

  const handleSend = (message: string) => {
    sendMessage(message);
  };

  const handleCreateProject = async () => {
    if (tradeScopes.length === 0) return;

    setIsSaving(true);
    try {
      // Derive project name from first user message if not set
      const nameToUse =
        projectName ||
        messages.find((m) => m.role === "user")?.content?.slice(0, 60) ||
        "New Project";

      const createdProjectId = await completeIntake(
        nameToUse,
        undefined,
        tradeScopes
      );
      router.push(`/projects/${createdProjectId}`);
    } catch (e) {
      console.error("[AIIntakePage] completeIntake error:", e);
    } finally {
      setIsSaving(false);
    }
  };

  const hasPreview = tradeScopes.length > 0;

  return (
    <div className="flex h-screen flex-col bg-background">
      {/* Fixed header */}
      <header className="flex flex-shrink-0 items-center gap-3 border-b bg-background px-4 py-3">
        <Link
          href="/projects"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" />
          Projects
        </Link>
        <Separator orientation="vertical" className="h-4" />
        <h1 className="text-xl font-semibold" style={{ fontSize: "20px", fontWeight: 600 }}>
          New Project — AI Intake
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
                    Tell me about your project
                  </h2>
                  <p className="mt-2 max-w-sm text-sm text-muted-foreground">
                    Describe what you&apos;re building — type, size, location, and
                    timeline — and I&apos;ll break it into trade scopes.
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

              {/* Typing indicator: show when streaming and last message has no content yet */}
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

        {/* Preview card section */}
        {hasPreview && (
          <>
            <Separator />
            <div className="flex-1 overflow-auto px-4 py-4">
              <TradeScopePreviewCard
                tradeScopes={tradeScopes}
                onUpdate={updateTradeScope}
                onRemove={removeTradeScope}
                onReorder={reorderTradeScopes}
                onCreateProject={handleCreateProject}
                isLoading={isStreaming && tradeScopes.length === 0}
                isSaving={isSaving}
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
            placeholder="Describe your project — what are you building?"
            disabled={isSaving}
          />
        )}
        {!conversationId && (
          <p className="text-center text-sm text-muted-foreground">
            Starting conversation...
          </p>
        )}
      </div>
    </div>
  );
}
