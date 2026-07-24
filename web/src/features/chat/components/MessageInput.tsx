"use client";

import { Paperclip, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import {
  useMessageInput,
  type ThreadMember,
} from "../hooks/useMessageInput";
import type { SendMessagePayload } from "../types";
import { MentionSuggestions } from "./MentionSuggestions";
import { StagedAttachmentPreview } from "./StagedAttachmentPreview";

export type { ThreadMember };

export interface MessageInputProps {
  threadId: string;
  threadName: string;
  members?: ThreadMember[];
  onSend: (payload: SendMessagePayload) => void;
  onTyping: () => void;
}

/**
 * Message input area with an auto-growing textarea, paperclip attachment
 * staging, @mention autocomplete, and debounced typing emission. All input
 * behaviour lives in {@link useMessageInput}; this component only renders it.
 */
export function MessageInput({
  threadId,
  threadName,
  members = [],
  onSend,
  onTyping,
}: MessageInputProps) {
  const {
    text,
    isEmpty,
    stagedFile,
    stagedPreviewUrl,
    mentionOpen,
    suggestions,
    textareaRef,
    fileInputRef,
    handleChange,
    handleKeyDown,
    handleFileChange,
    handleSend,
    insertMention,
    removeStagedFile,
  } = useMessageInput({ threadId, members, onSend, onTyping });

  return (
    <div className="border-t bg-background px-4 py-3">
      {stagedFile && (
        <StagedAttachmentPreview
          file={stagedFile}
          previewUrl={stagedPreviewUrl}
          onRemove={removeStagedFile}
        />
      )}

      <div className="relative flex items-end gap-2">
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*,.pdf"
          className="hidden"
          onChange={handleFileChange}
          aria-label="Attach file"
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="shrink-0"
          onClick={() => fileInputRef.current?.click()}
          aria-label="Add attachment"
        >
          <Paperclip className="size-4" />
        </Button>

        {mentionOpen && suggestions.length > 0 && (
          <MentionSuggestions suggestions={suggestions} onSelect={insertMention} />
        )}

        <textarea
          ref={textareaRef}
          rows={1}
          value={text}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          placeholder={`Message ${threadName}...`}
          aria-label={`Message ${threadName}`}
          className={cn(
            "min-h-12 flex-1 resize-none rounded-md border bg-background px-3 py-2 text-sm",
            "focus:outline-none focus:ring-2 focus:ring-ring",
            "placeholder:text-muted-foreground"
          )}
        />

        <Button
          type="button"
          variant="default"
          size="icon"
          className="shrink-0"
          disabled={isEmpty}
          onClick={() => void handleSend()}
          aria-label="Send message"
        >
          <Send className="size-4" />
        </Button>
      </div>
    </div>
  );
}
