import { useState } from "react";
import Image from "next/image";
import type { AttachmentResponse, JobNoteResponse } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { formatRelativeTime } from "@/lib/format";
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
          className="rounded overflow-hidden focus:outline-none focus:ring-2 focus:ring-ring"
        >
          {attachment.remote_url ? (
            <Image
              src={attachment.remote_url}
              alt={attachment.filename}
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
        </button>
      ))}
    </div>
  );
}

interface JobNotesCardProps {
  notes: JobNoteResponse[];
  onAddNote: (body: string) => void;
  isAddingNote: boolean;
}

export function JobNotesCard({
  notes,
  onAddNote,
  isAddingNote,
}: JobNotesCardProps) {
  const [noteBody, setNoteBody] = useState("");
  const [lightboxPhoto, setLightboxPhoto] = useState<AttachmentResponse | null>(
    null
  );

  function submitNote() {
    onAddNote(noteBody);
    setNoteBody("");
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
          <div className="flex justify-end">
            <Button
              size="sm"
              onClick={submitNote}
              disabled={!noteBody.trim() || isAddingNote}
            >
              Add Note
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
