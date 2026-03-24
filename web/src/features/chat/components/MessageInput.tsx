"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent,
} from "react";
import { Paperclip, Send } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { SendMessagePayload } from "../types";

// ── Types ─────────────────────────────────────────────────────────────────────

export interface ThreadMember {
  user_id: string;
  name: string;
}

export interface MessageInputProps {
  threadId: string;
  threadName: string;
  members?: ThreadMember[];
  onSend: (payload: SendMessagePayload) => void;
  onTyping: () => void;
}

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * Message input area with:
 * - Auto-growing textarea (1–5 lines)
 * - Paperclip attachment button (image/*, .pdf)
 * - Send button (disabled when empty)
 * - @mention Popover autocomplete
 * - Staged attachment preview with remove button
 * - Debounced typing emission (500ms)
 */
export function MessageInput({
  threadId,
  threadName,
  members = [],
  onSend,
  onTyping,
}: MessageInputProps) {
  const [text, setText] = useState("");
  const [mentionQuery, setMentionQuery] = useState<string | null>(null);
  const [mentionOpen, setMentionOpen] = useState(false);
  const [stagedFile, setStagedFile] = useState<File | null>(null);
  const [stagedPreviewUrl, setStagedPreviewUrl] = useState<string | null>(null);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mentionStartRef = useRef<number | null>(null);

  // ── Auto-grow textarea ────────────────────────────────────────────────────

  function autoGrow(el: HTMLTextAreaElement) {
    el.style.height = "auto";
    const lineHeight = parseInt(getComputedStyle(el).lineHeight || "20");
    const maxHeight = lineHeight * 5;
    el.style.height = `${Math.min(el.scrollHeight, maxHeight)}px`;
  }

  // ── Typed text → mention detection ───────────────────────────────────────

  function handleChange(e: ChangeEvent<HTMLTextAreaElement>) {
    const val = e.target.value;
    setText(val);
    autoGrow(e.target);

    // Debounced typing emission
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(() => {
      onTyping();
    }, 500);

    // @mention detection: find "@" before cursor
    const cursor = e.target.selectionStart ?? val.length;
    const beforeCursor = val.slice(0, cursor);
    const atMatch = /@(\w*)$/.exec(beforeCursor);
    if (atMatch) {
      mentionStartRef.current = atMatch.index;
      setMentionQuery(atMatch[1]);
      setMentionOpen(true);
    } else {
      setMentionOpen(false);
      setMentionQuery(null);
    }
  }

  // ── @mention selection ────────────────────────────────────────────────────

  const insertMention = useCallback(
    (member: ThreadMember) => {
      const cursor = textareaRef.current?.selectionStart ?? text.length;
      const start = mentionStartRef.current ?? cursor;
      const before = text.slice(0, start);
      const after = text.slice(cursor);
      const newText = `${before}@${member.name} ${after}`;
      setText(newText);
      setMentionOpen(false);
      setMentionQuery(null);

      // Refocus textarea
      requestAnimationFrame(() => textareaRef.current?.focus());
    },
    [text]
  );

  // ── Ctrl+Enter to send (optional) / just Enter for newline ───────────────

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      handleSend();
    }
    if (e.key === "Escape" && mentionOpen) {
      setMentionOpen(false);
    }
  }

  // ── File staging ──────────────────────────────────────────────────────────

  function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setStagedFile(file);

    if (file.type.startsWith("image/")) {
      const url = URL.createObjectURL(file);
      setStagedPreviewUrl(url);
    } else {
      setStagedPreviewUrl(null);
    }

    // Reset input so the same file can be re-selected after removal
    e.target.value = "";
  }

  function removeStagedFile() {
    if (stagedPreviewUrl) URL.revokeObjectURL(stagedPreviewUrl);
    setStagedFile(null);
    setStagedPreviewUrl(null);
  }

  // Revoke object URL on unmount
  useEffect(() => {
    return () => {
      if (stagedPreviewUrl) URL.revokeObjectURL(stagedPreviewUrl);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Send ──────────────────────────────────────────────────────────────────

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed && !stagedFile) return;

    // Collect @mentions from text
    const mentionMatches = Array.from(trimmed.matchAll(/@(\w+)/g));
    const mentionAll = trimmed.includes("@all");
    const mentionedNames = mentionMatches
      .map((m) => m[1])
      .filter((n) => n !== "all");
    const mentionedIds = mentionedNames
      .map((name) => members.find((m) => m.name.split(" ")[0] === name)?.user_id)
      .filter((id): id is string => id != null);

    const payload: SendMessagePayload = {
      id: crypto.randomUUID(),
      content: trimmed || undefined,
      mentions: mentionedIds.length > 0 ? mentionedIds : undefined,
      mention_all: mentionAll || undefined,
    };

    // If there's a staged file, upload it first
    if (stagedFile) {
      try {
        const formData = new FormData();
        formData.append("file", stagedFile);
        const resp = await fetch(
          `/api/proxy?path=${encodeURIComponent(`/api/v1/chat/threads/${threadId}/messages`)}`,
          { method: "POST", body: formData }
        );
        if (resp.ok) {
          const data = (await resp.json()) as {
            attachment_url?: string;
            attachment_type?: "photo" | "pdf" | "annotated_photo";
          };
          payload.attachment_url = data.attachment_url;
          payload.attachment_type = data.attachment_type;
        }
      } catch {
        // Upload failed — send without attachment rather than blocking
      }
      removeStagedFile();
    }

    onSend(payload);
    setText("");
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
    }
  }

  // ── Filtered member suggestions ───────────────────────────────────────────

  const filteredMembers =
    mentionQuery === null
      ? []
      : members.filter((m) =>
          m.name.toLowerCase().startsWith(mentionQuery.toLowerCase())
        );

  const allOption: ThreadMember = { user_id: "__all__", name: "all" };
  const suggestions =
    mentionQuery === null
      ? []
      : [
          ...("all".startsWith(mentionQuery.toLowerCase()) ? [allOption] : []),
          ...filteredMembers,
        ];

  const isEmpty = text.trim() === "" && !stagedFile;

  return (
    <div className="border-t bg-background px-4 py-3">
      {/* Staged attachment preview */}
      {stagedFile && (
        <div className="mb-2 flex items-center gap-2 rounded-md border bg-muted p-2 text-sm">
          {stagedPreviewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={stagedPreviewUrl}
              alt="Attachment preview"
              className="h-10 w-10 rounded object-cover"
            />
          ) : (
            <span className="truncate">{stagedFile.name}</span>
          )}
          <button
            type="button"
            className="ml-auto text-muted-foreground hover:text-foreground"
            onClick={removeStagedFile}
            aria-label="Remove attachment"
          >
            ×
          </button>
        </div>
      )}

      <div className="relative flex items-end gap-2">
        {/* Attachment button */}
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

        {/* @mention autocomplete dropdown (anchored above textarea) */}
        {mentionOpen && suggestions.length > 0 && (
          <div className="absolute bottom-full left-0 right-0 z-50 mb-1 max-h-48 overflow-y-auto rounded-md border bg-popover shadow-md">
            <ul role="listbox" aria-label="Mention suggestions">
              {suggestions.map((member) => (
                <li key={member.user_id}>
                  <button
                    type="button"
                    className="w-full px-3 py-2 text-left text-sm hover:bg-muted focus:bg-muted focus:outline-none"
                    onMouseDown={(e) => {
                      e.preventDefault(); // prevent textarea blur
                      insertMention(member);
                    }}
                  >
                    @{member.name}
                  </button>
                </li>
              ))}
            </ul>
          </div>
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

        {/* Send button */}
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
