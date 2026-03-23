"use client";

import { useRef, useState, useEffect, useCallback } from "react";
import { Send, Paperclip } from "lucide-react";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";

interface ChatInputProps {
  onSend: (message: string, imageFile?: File) => void;
  isStreaming?: boolean;
  placeholder?: string;
  disabled?: boolean;
}

export function ChatInput({
  onSend,
  isStreaming = false,
  placeholder = "Type a message...",
  disabled = false,
}: ChatInputProps) {
  const [value, setValue] = useState("");
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== "undefined" ? navigator.onLine : true
  );
  const [imagePreview, setImagePreview] = useState<{
    file: File;
    url: string;
  } | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);
    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, []);

  const handleSend = useCallback(() => {
    const trimmed = value.trim();
    if (!trimmed || isStreaming || !isOnline || disabled) return;
    onSend(trimmed, imagePreview?.file);
    setValue("");
    setImagePreview(null);
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
    }
  }, [value, isStreaming, isOnline, disabled, onSend, imagePreview]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleTextareaChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setValue(e.target.value);
    // Auto-expand up to 4 rows
    const el = e.target;
    el.style.height = "auto";
    const lineHeight = parseInt(getComputedStyle(el).lineHeight) || 20;
    const maxHeight = lineHeight * 4 + 16; // 4 rows + padding
    el.style.height = `${Math.min(el.scrollHeight, maxHeight)}px`;
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const url = URL.createObjectURL(file);
    setImagePreview({ file, url });
    e.target.value = "";
  };

  const isSendDisabled =
    !value.trim() || isStreaming || !isOnline || disabled;

  return (
    <div className="flex flex-col gap-2">
      {/* Offline banner */}
      {!isOnline && (
        <Alert variant="destructive" role="alert">
          <AlertDescription>
            AI features require an internet connection.
          </AlertDescription>
        </Alert>
      )}

      {/* Image preview */}
      {imagePreview && (
        <div className="flex items-center gap-2 rounded-lg border bg-muted px-3 py-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={imagePreview.url}
            alt="Attached image"
            className="h-10 w-10 rounded object-cover"
          />
          <span className="flex-1 truncate text-xs text-muted-foreground">
            {imagePreview.file.name}
          </span>
          <button
            type="button"
            className="text-xs text-destructive hover:underline"
            onClick={() => {
              URL.revokeObjectURL(imagePreview.url);
              setImagePreview(null);
            }}
          >
            Remove
          </button>
        </div>
      )}

      {/* Input row */}
      <div className="flex items-end gap-2">
        {/* Attach button */}
        <Button
          type="button"
          variant="outline"
          size="icon"
          disabled={!isOnline || disabled || isStreaming}
          onClick={() => fileInputRef.current?.click()}
          aria-label="Attach image"
          className="flex-shrink-0"
        >
          <Paperclip className="h-4 w-4" />
        </Button>

        {/* Hidden file input */}
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={handleFileChange}
        />

        {/* Textarea */}
        <Textarea
          ref={textareaRef}
          value={value}
          onChange={handleTextareaChange}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={!isOnline || disabled || isStreaming}
          rows={1}
          className="flex-1 resize-none overflow-hidden"
          style={{ minHeight: "40px" }}
        />

        {/* Send button */}
        <Button
          type="button"
          disabled={isSendDisabled}
          onClick={handleSend}
          aria-label="Send message"
          className="flex-shrink-0"
        >
          <Send className="h-4 w-4" />
          <span className="sr-only">Send Message</span>
        </Button>
      </div>
    </div>
  );
}
