import { drawAnnotation } from "@/features/tasks/hooks/usePhotoAnnotation";
import type { AnnotationLayer } from "@/features/tasks/types";

/** Load an image element from a URL (object URL or remote), resolving on load. */
export function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new window.Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("Failed to load image"));
    img.src = src;
  });
}

/** Convert a canvas to a Blob (PNG by default). */
export function canvasToBlob(canvas: HTMLCanvasElement, type = "image/png"): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("Canvas export failed"))),
      type
    );
  });
}

/**
 * Flatten an image + its annotation layer into a single PNG blob.
 *
 * Used where the backend stores only an image (e.g. job-note attachments, which
 * have no annotation_data field), so annotations are burned into the pixels.
 * Reuses drawAnnotation so the flattened output matches the on-screen overlay.
 */
export async function flattenAnnotatedImage(
  imageUrl: string,
  layer: AnnotationLayer
): Promise<Blob> {
  const img = await loadImage(imageUrl);
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = img.naturalHeight;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas 2D context unavailable");

  ctx.drawImage(img, 0, 0);
  for (const annotation of layer.annotations) {
    drawAnnotation(ctx, annotation, canvas.width, canvas.height);
  }
  return canvasToBlob(canvas);
}
