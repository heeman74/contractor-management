"use client";

import { Bot } from "lucide-react";
import type { ChatMessage } from "../hooks/useIntakeChat";

interface ChatBubbleProps {
  message: ChatMessage;
  isStreaming?: boolean;
}

export function ChatBubble({ message, isStreaming = false }: ChatBubbleProps) {
  const isUser = message.role === "user";

  if (isUser) {
    return (
      <div className="flex justify-end" aria-label="Your message">
        <div
          className="max-w-[70%] rounded-xl bg-primary px-4 py-2 text-sm text-primary-foreground"
          style={{ wordBreak: "break-word" }}
        >
          {message.content}
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-start gap-2" aria-label="ContractorHub AI">
      {/* AI Avatar */}
      <div className="flex flex-shrink-0 flex-col items-center gap-1">
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
          <Bot className="h-4 w-4 text-muted-foreground" />
        </div>
        <span className="text-[10px] text-muted-foreground whitespace-nowrap">
          ContractorHub AI
        </span>
      </div>

      {/* Message bubble */}
      <div
        className="max-w-[70%] rounded-xl bg-muted px-4 py-2 text-sm"
        style={{ wordBreak: "break-word" }}
      >
        {message.content}
        {isStreaming && (
          <span
            className="ml-0.5 inline-block h-3 w-0.5 animate-pulse bg-current align-middle"
            aria-hidden="true"
          />
        )}
        {/* Image thumbnail if present */}
        {(message as ChatMessage & { imageUrl?: string }).imageUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={(message as ChatMessage & { imageUrl?: string }).imageUrl}
            alt="Attached image"
            className="mt-2 h-20 w-20 cursor-pointer rounded object-cover"
            onClick={() => {
              window.open(
                (message as ChatMessage & { imageUrl?: string }).imageUrl,
                "_blank"
              );
            }}
          />
        )}
      </div>
    </div>
  );
}
