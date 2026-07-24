"use client";

import { useRef, useState } from "react";
import Image from "next/image";
import { ImagePlus, Pencil, PenLine, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { PhotoAnnotationCanvas } from "@/features/tasks/components/PhotoAnnotationCanvas";
import type { AnnotationLayer } from "@/features/tasks/types";
import { DrawingCanvas } from "./DrawingCanvas";
import { flattenAnnotatedImage } from "../lib/flatten";
import type { PendingAttachment } from "../types";

let pendingSeq = 0;

interface MediaComposerProps {
  value: PendingAttachment[];
  onChange: (next: PendingAttachment[]) => void;
  disabled?: boolean;
  /** Hide the flatten-into-image annotate action (e.g. where non-destructive
   *  post-upload annotation is available instead). */
  hideAnnotate?: boolean;
}

/**
 * Collects photos, from-scratch drawings, and annotated photos as a list of
 * pending attachments (each a File ready to upload). Annotations are flattened
 * into the image, since job-note attachments store only an image.
 */
export function MediaComposer({ value, onChange, disabled, hideAnnotate }: MediaComposerProps) {
  const photoInputRef = useRef<HTMLInputElement>(null);
  const annotateInputRef = useRef<HTMLInputElement>(null);
  const [drawOpen, setDrawOpen] = useState(false);
  const [annotateUrl, setAnnotateUrl] = useState<string | null>(null);

  function add(item: Omit<PendingAttachment, "id" | "previewUrl">, file: File) {
    onChange([
      ...value,
      { ...item, id: `pending-${pendingSeq++}`, file, previewUrl: URL.createObjectURL(file) },
    ]);
  }

  function remove(id: string) {
    const target = value.find((v) => v.id === id);
    if (target) URL.revokeObjectURL(target.previewUrl);
    onChange(value.filter((v) => v.id !== id));
  }

  function handlePhotos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    for (const file of files) add({ file, attachmentType: "photo" }, file);
    e.target.value = "";
  }

  function handleAnnotatePick(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) setAnnotateUrl(URL.createObjectURL(file));
    e.target.value = "";
  }

  async function handleAnnotationSave(json: string) {
    if (!annotateUrl) return;
    const layer = JSON.parse(json) as AnnotationLayer;
    const blob = await flattenAnnotatedImage(annotateUrl, layer);
    const file = new File([blob], `annotated-${Date.now()}.png`, { type: "image/png" });
    add({ file, attachmentType: "photo" }, file);
    URL.revokeObjectURL(annotateUrl);
    setAnnotateUrl(null);
  }

  function handleDrawingExport(blob: Blob) {
    const file = new File([blob], `drawing-${Date.now()}.png`, { type: "image/png" });
    add({ file, attachmentType: "drawing" }, file);
    setDrawOpen(false);
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          onClick={() => photoInputRef.current?.click()}
        >
          <ImagePlus className="mr-1.5 h-4 w-4" /> Photo
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          onClick={() => setDrawOpen(true)}
        >
          <PenLine className="mr-1.5 h-4 w-4" /> Draw
        </Button>
        {!hideAnnotate && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={disabled}
            onClick={() => annotateInputRef.current?.click()}
          >
            <Pencil className="mr-1.5 h-4 w-4" /> Annotate photo
          </Button>
        )}

        <input
          ref={photoInputRef}
          type="file"
          accept="image/*"
          multiple
          hidden
          onChange={handlePhotos}
        />
        <input
          ref={annotateInputRef}
          type="file"
          accept="image/*"
          hidden
          onChange={handleAnnotatePick}
        />
      </div>

      {value.length > 0 && (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
          {value.map((item) => (
            <div key={item.id} className="relative aspect-square">
              <Image
                src={item.previewUrl}
                alt={item.attachmentType}
                fill
                unoptimized
                className="rounded object-cover ring-1 ring-border"
              />
              <button
                type="button"
                aria-label="Remove attachment"
                onClick={() => remove(item.id)}
                className="absolute -right-1.5 -top-1.5 flex h-5 w-5 items-center justify-center rounded-full bg-foreground text-background shadow"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Draw-from-scratch dialog */}
      <Dialog open={drawOpen} onOpenChange={setDrawOpen}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>Draw</DialogTitle>
          </DialogHeader>
          {drawOpen && (
            <DrawingCanvas onExport={handleDrawingExport} onCancel={() => setDrawOpen(false)} />
          )}
        </DialogContent>
      </Dialog>

      {/* Annotate-a-photo dialog */}
      <Dialog open={annotateUrl !== null} onOpenChange={(open) => !open && setAnnotateUrl(null)}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>Annotate photo</DialogTitle>
          </DialogHeader>
          {annotateUrl && (
            <PhotoAnnotationCanvas
              imageUrl={annotateUrl}
              onSave={handleAnnotationSave}
              onDiscard={() => {
                URL.revokeObjectURL(annotateUrl);
                setAnnotateUrl(null);
              }}
            />
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
