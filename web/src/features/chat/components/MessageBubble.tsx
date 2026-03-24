"use client";

import { FileText, Clock, Check, CheckCheck } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { ChatMessage, ChatReadReceipt } from "../types";

// ── Helpers ───────────────────────────────────────────────────────────────────

function formatTimestamp(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / 86_400_000);

  if (diffDays === 0) {
    return date.toLocaleTimeString(undefined, {
      hour: "numeric",
      minute: "2-digit",
    });
  }
  if (diffDays < 7) {
    return date.toLocaleDateString(undefined, {
      weekday: "short",
      hour: "numeric",
      minute: "2-digit",
    });
  }
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function getInitials(name: string): string {
  return name
    .split(" ")
    .map((n) => n[0] ?? "")
    .slice(0, 2)
    .join("")
    .toUpperCase();
}

// ── Types ─────────────────────────────────────────────────────────────────────

export interface MessageBubbleProps {
  message: ChatMessage;
  isOwn: boolean;
  /** Status for own messages: pending = clock, sent = check, read = double-check */
  status?: "pending" | "sent" | "read";
  /** Read receipts shown below own messages */
  readReceipts?: ChatReadReceipt[];
}

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * A single chat message bubble.
 *
 * Own messages: right-aligned, primary background.
 * Other messages: left-aligned, muted background.
 *
 * Content variants: text, photo, PDF, annotated-photo.
 */
export function MessageBubble({
  message,
  isOwn,
  status = "sent",
  readReceipts = [],
}: MessageBubbleProps) {
  const timestamp = formatTimestamp(message.created_at);

  const ariaLabel = `${message.sender_name}: ${message.content ?? "attachment"}, ${timestamp}`;

  return (
    <div
      className={cn(
        "flex w-full gap-2 px-4 py-1",
        isOwn ? "flex-row-reverse" : "flex-row"
      )}
      aria-label={ariaLabel}
    >
      {/* Avatar for incoming messages */}
      {!isOwn && (
        <Avatar size="sm" className="mt-1 shrink-0">
          <AvatarFallback>{getInitials(message.sender_name)}</AvatarFallback>
        </Avatar>
      )}

      <div
        className={cn(
          "flex max-w-[75%] flex-col gap-1",
          isOwn ? "items-end" : "items-start"
        )}
      >
        {/* Sender name (incoming only) */}
        {!isOwn && (
          <span className="text-xs font-semibold text-muted-foreground">
            {message.sender_name}
          </span>
        )}

        {/* Bubble */}
        <div
          className={cn(
            "relative rounded-2xl px-3 py-2 text-sm",
            isOwn
              ? "rounded-tr-sm bg-primary text-primary-foreground"
              : "rounded-tl-sm bg-muted text-foreground",
            status === "pending" && isOwn && "opacity-70"
          )}
        >
          <BubbleContent message={message} />

          {/* Timestamp + status */}
          <div
            className={cn(
              "mt-1 flex items-center gap-1",
              isOwn ? "justify-end" : "justify-start"
            )}
          >
            <span
              className={cn(
                "text-xs",
                isOwn ? "text-primary-foreground/70" : "text-muted-foreground"
              )}
            >
              {timestamp}
            </span>
            {isOwn && <StatusIcon status={status} />}
          </div>
        </div>

        {/* Read receipts (own messages) */}
        {isOwn && readReceipts.length > 0 && (
          <ReadReceiptRow receipts={readReceipts} />
        )}
      </div>
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function BubbleContent({ message }: { message: ChatMessage }) {
  const { attachment_type, attachment_url, content } = message;

  if (attachment_type === "photo" && attachment_url) {
    return (
      <div className="flex flex-col gap-1">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={attachment_url}
          alt="Shared photo"
          className="max-w-[200px] cursor-pointer rounded-lg object-cover"
          onClick={() => window.open(attachment_url, "_blank")}
        />
        {content && <p className="text-sm">{content}</p>}
      </div>
    );
  }

  if (attachment_type === "annotated_photo" && attachment_url) {
    return (
      <div className="flex flex-col gap-1">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={attachment_url}
          alt="Annotated photo"
          className="max-w-[200px] cursor-pointer rounded-lg object-cover"
          onClick={() => window.open(attachment_url, "_blank")}
        />
        <Badge variant="secondary" className="w-fit text-xs">
          Annotated photo
        </Badge>
        {content && <p className="text-sm">{content}</p>}
      </div>
    );
  }

  if (attachment_type === "pdf" && attachment_url) {
    const filename = attachment_url.split("/").pop() ?? "Document.pdf";
    return (
      <button
        type="button"
        className="flex items-center gap-2 text-left underline-offset-2 hover:underline"
        onClick={() => window.open(attachment_url, "_blank")}
        aria-label={`PDF: ${filename}`}
      >
        <FileText className="size-4 shrink-0" />
        <span className="text-sm">{filename}</span>
      </button>
    );
  }

  // Default: plain text
  return <p className="whitespace-pre-wrap text-sm">{content}</p>;
}

function StatusIcon({ status }: { status: "pending" | "sent" | "read" }) {
  if (status === "pending") {
    return <Clock className="size-3 text-primary-foreground/70" />;
  }
  if (status === "read") {
    return <CheckCheck className="size-3 text-primary-foreground/70" />;
  }
  return <Check className="size-3 text-primary-foreground/70" />;
}

function ReadReceiptRow({ receipts }: { receipts: ChatReadReceipt[] }) {
  const [first, ...rest] = receipts;
  if (!first) return null;

  const label =
    rest.length === 0
      ? `Read by ${first.user_name}`
      : `Read by ${first.user_name} and ${rest.length} other${rest.length > 1 ? "s" : ""}`;

  return (
    <div
      className="flex items-center gap-1"
      aria-label={label}
      title={label}
    >
      {receipts.slice(0, 3).map((r) => (
        <Avatar key={r.user_id} size="sm" className="size-4">
          <AvatarFallback className="text-[8px]">
            {getInitials(r.user_name)}
          </AvatarFallback>
        </Avatar>
      ))}
      <span className="text-xs text-muted-foreground">{label}</span>
    </div>
  );
}
