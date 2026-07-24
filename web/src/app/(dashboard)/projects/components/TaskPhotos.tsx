"use client";

import { useState } from "react";
import Image from "next/image";
import { Pencil } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { MediaComposer } from "@/features/media/components/MediaComposer";
import type { PendingAttachment } from "@/features/media/types";
import { PhotoAnnotationCanvas } from "@/features/tasks/components/PhotoAnnotationCanvas";
import { AnnotatedThumbnail } from "@/features/tasks/components/AnnotatedThumbnail";
import type { AnnotationLayer } from "@/features/tasks/types";
import { usePermissions } from "@/lib/hooks/usePermissions";
import {
  useTaskAttachments,
  useUpdateTaskAnnotation,
  useUploadTaskAttachments,
} from "@/lib/hooks/useTaskAttachments";
import type { TaskAttachmentResponse } from "@/types/projects";

/** Read the annotation layer off an attachment, if present. */
function annotationLayer(photo: TaskAttachmentResponse): AnnotationLayer | undefined {
  const data = photo.annotation_data as unknown as AnnotationLayer | null;
  return data?.annotations ? data : undefined;
}

/** Task photo gallery with non-destructive annotation + add-media controls. */
export function TaskPhotos({ taskId }: { taskId: string }) {
  const { can } = usePermissions();
  const { data: attachments } = useTaskAttachments(taskId);
  const upload = useUploadTaskAttachments(taskId);
  const updateAnnotation = useUpdateTaskAnnotation(taskId);
  const [pending, setPending] = useState<PendingAttachment[]>([]);
  const [annotating, setAnnotating] = useState<TaskAttachmentResponse | null>(null);

  const canEdit = can("tasks.edit");
  const photos = attachments ?? [];

  function saveUploads() {
    upload.mutate(pending, {
      onSuccess: () => {
        setPending([]);
        toast.success("Photos added");
      },
      onError: () => toast.error("Failed to add photos"),
    });
  }

  function saveAnnotation(json: string) {
    if (!annotating) return;
    updateAnnotation.mutate(
      { attachmentId: annotating.id, annotationData: JSON.parse(json) },
      {
        onSuccess: () => {
          setAnnotating(null);
          toast.success("Annotation saved");
        },
        onError: () => toast.error("Failed to save annotation"),
      }
    );
  }

  return (
    <div>
      <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">
        Photos
      </h3>

      {photos.length === 0 ? (
        <p className="text-sm text-gray-500">No photos yet.</p>
      ) : (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
          {photos.map((photo) => {
            if (!photo.remote_url) return null;
            const layer = annotationLayer(photo);
            const thumbnail = (
              <>
                {layer ? (
                  <AnnotatedThumbnail
                    imageUrl={photo.remote_url}
                    layer={layer}
                    className="absolute inset-0 h-full w-full rounded object-cover ring-1 ring-border"
                  />
                ) : (
                  <Image
                    src={photo.remote_url}
                    alt={photo.caption ?? "Task photo"}
                    fill
                    unoptimized
                    className="rounded object-cover ring-1 ring-border"
                  />
                )}
                {layer && (
                  <span
                    className="absolute left-1 top-1 flex h-4 w-4 items-center justify-center rounded-full bg-brand text-brand-foreground"
                    title="Annotated"
                  >
                    <Pencil className="h-2.5 w-2.5" />
                  </span>
                )}
              </>
            );
            return canEdit ? (
              <button
                key={photo.id}
                type="button"
                onClick={() => setAnnotating(photo)}
                className="relative aspect-square"
                title="Annotate"
              >
                {thumbnail}
              </button>
            ) : (
              <a
                key={photo.id}
                href={photo.remote_url}
                target="_blank"
                rel="noopener noreferrer"
                className="relative aspect-square"
              >
                {thumbnail}
              </a>
            );
          })}
        </div>
      )}

      {canEdit && (
        <div className="mt-3 space-y-2">
          <MediaComposer
            value={pending}
            onChange={setPending}
            disabled={upload.isPending}
            hideAnnotate
          />
          {pending.length > 0 && (
            <div className="flex justify-end">
              <Button variant="brand" size="sm" onClick={saveUploads} disabled={upload.isPending}>
                {upload.isPending ? "Adding…" : `Add ${pending.length} to task`}
              </Button>
            </div>
          )}
        </div>
      )}

      {/* Non-destructive annotation of an existing photo */}
      <Dialog open={annotating !== null} onOpenChange={(open) => !open && setAnnotating(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>Annotate photo</DialogTitle>
          </DialogHeader>
          {annotating?.remote_url && (
            <PhotoAnnotationCanvas
              imageUrl={annotating.remote_url}
              initialAnnotations={annotationLayer(annotating)}
              onSave={saveAnnotation}
              onDiscard={() => setAnnotating(null)}
            />
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
