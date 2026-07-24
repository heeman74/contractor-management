import { useState } from "react";
import Image from "next/image";
import { PenLine } from "lucide-react";
import type { AttachmentResponse, JobNoteResponse } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { formatRelativeTime } from "@/lib/format";
import { MediaComposer } from "@/features/media/components/MediaComposer";
import type { PendingAttachment } from "@/features/media/types";
import { PhotoLightbox } from "./photo-lightbox";

const MAX_NOTE_LENGTH = 2000;

function NoteAttachments({
  attachments,
  onOpenPhoto,
}: {
  attachments: AttachmentResponse[];
  onOpenPhoto: (attachment: AttachmentResponse) => void;
}) {
  if (attachments.length === 0) return null;

  return (
    <div className="grid grid-cols-4 gap-2 mt-2">
      {attachments.map((attachment) => (
        <button
          key={attachment.id}
          onClick={() => onOpenPhoto(attachment)}
          className="relative rounded overflow-hidden focus:outline-none focus:ring-2 focus:ring-ring"
        >
          {attachment.remote_url ? (
            <Image
              src={attachment.remote_url}
              alt={attachment.caption ?? attachment.attachment_type}
              width={200}
              height={200}
              unoptimized
              className="aspect-square w-full rounded object-cover bg-gray-100"
            />
          ) : (
            <div className="flex items-center justify-center aspect-square bg-gray-100 rounded">
              <span className="text-xs text-gray-400">Photo unavailable</span>
            </div>
          )}
          {attachment.attachment_type === "drawing" && (
            <span
              className="absolute left-1 top-1 flex h-4 w-4 items-center justify-center rounded-full bg-brand text-brand-foreground"
              title="Drawing"
            >
              <PenLine className="h-2.5 w-2.5" />
            </span>
          )}
        </button>
      ))}
    </div>
  );
}

interface JobNotesCardProps {
  notes: JobNoteResponse[];
  onAddNote: (body: string, attachments: PendingAttachment[]) => void;
  isAddingNote: boolean;
}

export function JobNotesCard({
  notes,
  onAddNote,
  isAddingNote,
}: JobNotesCardProps) {
  const [noteBody, setNoteBody] = useState("");
  const [attachments, setAttachments] = useState<PendingAttachment[]>([]);
  const [lightboxPhoto, setLightboxPhoto] = useState<AttachmentResponse | null>(
    null
  );

  const canSubmit = (noteBody.trim().length > 0 || attachments.length > 0) && !isAddingNote;

  function submitNote() {
    if (!canSubmit) return;
    onAddNote(noteBody, attachments);
    setNoteBody("");
    setAttachments([]);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Notes</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {notes.length === 0 ? (
          <p className="text-sm text-gray-500">
            No notes yet. Add a note to track progress or log important details.
          </p>
        ) : (
          <ul className="space-y-4">
            {notes.map((note) => (
              <li key={note.id} className="space-y-1">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-gray-500">
                    {note.author_id.slice(0, 8)}
                  </span>
                  <span className="text-xs text-gray-400">
                    {formatRelativeTime(note.created_at)}
                  </span>
                </div>
                <p className="text-sm text-gray-700">{note.body}</p>
                <NoteAttachments
                  attachments={note.attachments}
                  onOpenPhoto={setLightboxPhoto}
                />
              </li>
            ))}
          </ul>
        )}

        <div className="space-y-2 pt-2 border-t">
          <Textarea
            placeholder="Add a note..."
            className="resize-none"
            maxLength={MAX_NOTE_LENGTH}
            value={noteBody}
            onChange={(e) => setNoteBody(e.target.value)}
          />
          <MediaComposer
            value={attachments}
            onChange={setAttachments}
            disabled={isAddingNote}
          />
          <div className="flex justify-end">
            <Button size="sm" onClick={submitNote} disabled={!canSubmit}>
              {isAddingNote ? "Adding…" : "Add Note"}
            </Button>
          </div>
        </div>
      </CardContent>

      <PhotoLightbox
        photo={lightboxPhoto}
        onClose={() => setLightboxPhoto(null)}
      />
    </Card>
  );
}
