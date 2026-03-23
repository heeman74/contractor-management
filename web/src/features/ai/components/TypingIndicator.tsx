"use client";

import { Bot } from "lucide-react";

export function TypingIndicator() {
  return (
    <div
      className="flex items-start gap-2"
      aria-label="ContractorHub AI is typing"
    >
      {/* AI Avatar */}
      <div className="flex flex-shrink-0 flex-col items-center gap-1">
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
          <Bot className="h-4 w-4 text-muted-foreground" />
        </div>
        <span className="text-[10px] text-muted-foreground whitespace-nowrap">
          ContractorHub AI
        </span>
      </div>

      {/* Typing dots bubble */}
      <div className="flex items-center gap-1 rounded-xl bg-muted px-4 py-3">
        <style>{`
          @keyframes bounce {
            0%, 80%, 100% { transform: translateY(0); }
            40% { transform: translateY(-6px); }
          }
        `}</style>
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="block h-2 w-2 rounded-full bg-primary"
            style={{
              animation: "bounce 1.4s ease-in-out infinite",
              animationDelay: `${i * 0.15}s`,
            }}
            aria-hidden="true"
          />
        ))}
      </div>
    </div>
  );
}
