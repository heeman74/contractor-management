"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent,
  type RefObject,
} from "react";
import type { SendMessagePayload } from "../types";

const TYPING_DEBOUNCE_MS = 500;
const MAX_TEXTAREA_LINES = 5;
const DEFAULT_LINE_HEIGHT_PX = 20;
const MENTION_ALL_TOKEN = "all";

export interface ThreadMember {
  user_id: string;
  name: string;
}

interface UseMessageInputParams {
  threadId: string;
  members: ThreadMember[];
  onSend: (payload: SendMessagePayload) => void;
  onTyping: () => void;
}

export interface UseMessageInputReturn {
  text: string;
  isEmpty: boolean;
  stagedFile: File | null;
  stagedPreviewUrl: string | null;
  mentionOpen: boolean;
  suggestions: ThreadMember[];
  textareaRef: RefObject<HTMLTextAreaElement | null>;
  fileInputRef: RefObject<HTMLInputElement | null>;
  handleChange: (event: ChangeEvent<HTMLTextAreaElement>) => void;
  handleKeyDown: (event: KeyboardEvent<HTMLTextAreaElement>) => void;
  handleFileChange: (event: ChangeEvent<HTMLInputElement>) => void;
  handleSend: () => Promise<void>;
  insertMention: (member: ThreadMember) => void;
  removeStagedFile: () => void;
}

function autoGrowTextarea(element: HTMLTextAreaElement) {
  element.style.height = "auto";
  const lineHeight =
    parseInt(getComputedStyle(element).lineHeight || `${DEFAULT_LINE_HEIGHT_PX}`);
  const maxHeight = lineHeight * MAX_TEXTAREA_LINES;
  element.style.height = `${Math.min(element.scrollHeight, maxHeight)}px`;
}

export function findMentionQuery(textBeforeCursor: string): {
  query: string;
  startIndex: number;
} | null {
  const atMatch = /@(\w*)$/.exec(textBeforeCursor);
  if (!atMatch) return null;
  return { query: atMatch[1], startIndex: atMatch.index };
}

export function resolveMentionedIds(text: string, members: ThreadMember[]): string[] {
  const mentionedNames = Array.from(text.matchAll(/@(\w+)/g))
    .map((match) => match[1])
    .filter((name) => name !== MENTION_ALL_TOKEN);
  return mentionedNames
    .map((name) => members.find((m) => m.name.split(" ")[0] === name)?.user_id)
    .filter((id): id is string => id != null);
}

async function uploadAttachment(
  threadId: string,
  file: File
): Promise<Pick<SendMessagePayload, "attachment_url" | "attachment_type">> {
  const formData = new FormData();
  formData.append("file", file);
  const response = await fetch(
    `/api/proxy?path=${encodeURIComponent(`/api/v1/chat/threads/${threadId}/messages`)}`,
    { method: "POST", body: formData }
  );
  if (!response.ok) return {};
  const data = (await response.json()) as {
    attachment_url?: string;
    attachment_type?: SendMessagePayload["attachment_type"];
  };
  return {
    attachment_url: data.attachment_url,
    attachment_type: data.attachment_type,
  };
}

export function useMessageInput({
  threadId,
  members,
  onSend,
  onTyping,
}: UseMessageInputParams): UseMessageInputReturn {
  const [text, setText] = useState("");
  const [mentionQuery, setMentionQuery] = useState<string | null>(null);
  const [mentionOpen, setMentionOpen] = useState(false);
  const [stagedFile, setStagedFile] = useState<File | null>(null);
  const [stagedPreviewUrl, setStagedPreviewUrl] = useState<string | null>(null);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mentionStartRef = useRef<number | null>(null);

  function emitTypingDebounced() {
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(onTyping, TYPING_DEBOUNCE_MS);
  }

  function handleChange(event: ChangeEvent<HTMLTextAreaElement>) {
    const value = event.target.value;
    setText(value);
    autoGrowTextarea(event.target);
    emitTypingDebounced();

    const cursor = event.target.selectionStart ?? value.length;
    const mention = findMentionQuery(value.slice(0, cursor));
    if (mention) {
      mentionStartRef.current = mention.startIndex;
      setMentionQuery(mention.query);
      setMentionOpen(true);
    } else {
      setMentionOpen(false);
      setMentionQuery(null);
    }
  }

  const insertMention = useCallback(
    (member: ThreadMember) => {
      const cursor = textareaRef.current?.selectionStart ?? text.length;
      const start = mentionStartRef.current ?? cursor;
      const before = text.slice(0, start);
      const after = text.slice(cursor);
      setText(`${before}@${member.name} ${after}`);
      setMentionOpen(false);
      setMentionQuery(null);
      requestAnimationFrame(() => textareaRef.current?.focus());
    },
    [text]
  );

  function handleKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      void handleSend();
    }
    if (event.key === "Escape" && mentionOpen) {
      setMentionOpen(false);
    }
  }

  function handleFileChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setStagedFile(file);
    setStagedPreviewUrl(
      file.type.startsWith("image/") ? URL.createObjectURL(file) : null
    );
    // Reset input so the same file can be re-selected after removal
    event.target.value = "";
  }

  function removeStagedFile() {
    if (stagedPreviewUrl) URL.revokeObjectURL(stagedPreviewUrl);
    setStagedFile(null);
    setStagedPreviewUrl(null);
  }

  useEffect(() => {
    return () => {
      if (stagedPreviewUrl) URL.revokeObjectURL(stagedPreviewUrl);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed && !stagedFile) return;

    const mentionedIds = resolveMentionedIds(trimmed, members);
    const payload: SendMessagePayload = {
      id: crypto.randomUUID(),
      content: trimmed || undefined,
      mentions: mentionedIds.length > 0 ? mentionedIds : undefined,
      mention_all: trimmed.includes("@all") || undefined,
    };

    if (stagedFile) {
      try {
        const attachment = await uploadAttachment(threadId, stagedFile);
        payload.attachment_url = attachment.attachment_url;
        payload.attachment_type = attachment.attachment_type;
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

  const allOption: ThreadMember = { user_id: "__all__", name: MENTION_ALL_TOKEN };
  const suggestions =
    mentionQuery === null
      ? []
      : [
          ...(MENTION_ALL_TOKEN.startsWith(mentionQuery.toLowerCase())
            ? [allOption]
            : []),
          ...members.filter((m) =>
            m.name.toLowerCase().startsWith(mentionQuery.toLowerCase())
          ),
        ];

  return {
    text,
    isEmpty: text.trim() === "" && !stagedFile,
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
  };
}
