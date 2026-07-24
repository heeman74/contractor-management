"use client";

import { useEffect, useRef } from "react";
import { loadImage } from "@/features/media/lib/flatten";
import { drawAnnotation } from "../hooks/usePhotoAnnotation";
import type { AnnotationLayer } from "../types";

const RESOLUTION = 320;

interface AnnotatedThumbnailProps {
  imageUrl: string;
  layer: AnnotationLayer;
  className?: string;
}

/**
 * Read-only thumbnail that renders a photo with its annotations burned on top
 * (contain-fit, so normalized coordinates map exactly). Reuses drawAnnotation so
 * the preview matches the full editor.
 */
export function AnnotatedThumbnail({ imageUrl, layer, className }: AnnotatedThumbnailProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    let cancelled = false;
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    loadImage(imageUrl)
      .then((img) => {
        if (cancelled) return;
        const { width, height } = canvas;
        ctx.fillStyle = "#f3f4f6";
        ctx.fillRect(0, 0, width, height);

        const scale = Math.min(width / img.naturalWidth, height / img.naturalHeight);
        const dw = img.naturalWidth * scale;
        const dh = img.naturalHeight * scale;
        const ox = (width - dw) / 2;
        const oy = (height - dh) / 2;
        ctx.drawImage(img, ox, oy, dw, dh);

        // Annotations are normalized 0–1 relative to the image rect.
        ctx.save();
        ctx.translate(ox, oy);
        for (const annotation of layer.annotations) {
          drawAnnotation(ctx, annotation, dw, dh);
        }
        ctx.restore();
      })
      .catch(() => {
        /* leave the neutral background if the image fails to load */
      });

    return () => {
      cancelled = true;
    };
  }, [imageUrl, layer]);

  return <canvas ref={canvasRef} width={RESOLUTION} height={RESOLUTION} className={className} />;
}
