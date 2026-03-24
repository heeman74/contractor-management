"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { Annotation, AnnotationLayer, AnnotationTool } from "../types";

/**
 * Canvas rendering functions for annotation overlays.
 *
 * These are pure functions (no React state) — called from useEffect and event
 * handlers without triggering re-renders. This is critical for canvas drawing:
 * React re-renders clear canvas state, so all drawing state lives in refs.
 */

/** Convert a normalized 0–1 coordinate to a canvas pixel coordinate. */
function denorm(value: number, dimension: number): number {
  return value * dimension;
}

/** Draw an arrowhead at `to`, pointing from `from`. */
function drawArrowHead(
  ctx: CanvasRenderingContext2D,
  from: { x: number; y: number },
  to: { x: number; y: number }
): void {
  const arrowSize = 14;
  const angle = Math.atan2(to.y - from.y, to.x - from.x);

  ctx.beginPath();
  ctx.moveTo(to.x, to.y);
  ctx.lineTo(
    to.x - arrowSize * Math.cos(angle - 0.5),
    to.y - arrowSize * Math.sin(angle - 0.5)
  );
  ctx.moveTo(to.x, to.y);
  ctx.lineTo(
    to.x - arrowSize * Math.cos(angle + 0.5),
    to.y - arrowSize * Math.sin(angle + 0.5)
  );
  ctx.stroke();
}

/** Draw perpendicular tick marks at a ruler endpoint. */
function drawTickMark(
  ctx: CanvasRenderingContext2D,
  point: { x: number; y: number },
  other: { x: number; y: number }
): void {
  const tickLength = 8;
  const angle = Math.atan2(other.y - point.y, other.x - point.x);
  const perp = angle + Math.PI / 2;

  ctx.beginPath();
  ctx.moveTo(
    point.x + tickLength * Math.cos(perp),
    point.y + tickLength * Math.sin(perp)
  );
  ctx.lineTo(
    point.x - tickLength * Math.cos(perp),
    point.y - tickLength * Math.sin(perp)
  );
  ctx.stroke();
}

/**
 * Draw a single annotation onto a canvas context.
 *
 * Coordinates are denormalized from 0–1 to canvas pixel dimensions.
 */
export function drawAnnotation(
  ctx: CanvasRenderingContext2D,
  ann: Annotation,
  w: number,
  h: number
): void {
  ctx.strokeStyle = ann.color;
  ctx.fillStyle = ann.color;
  ctx.lineWidth = ann.thickness;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  switch (ann.tool) {
    case "arrow": {
      if (
        ann.startX == null ||
        ann.startY == null ||
        ann.endX == null ||
        ann.endY == null
      )
        return;
      const from = { x: denorm(ann.startX, w), y: denorm(ann.startY, h) };
      const to = { x: denorm(ann.endX, w), y: denorm(ann.endY, h) };
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
      drawArrowHead(ctx, from, to);
      break;
    }

    case "circle": {
      if (
        ann.x == null ||
        ann.y == null ||
        ann.width == null ||
        ann.height == null
      )
        return;
      const cx = denorm(ann.x + ann.width / 2, w);
      const cy = denorm(ann.y + ann.height / 2, h);
      const rx = denorm(ann.width / 2, w);
      const ry = denorm(ann.height / 2, h);
      ctx.beginPath();
      ctx.ellipse(cx, cy, Math.abs(rx), Math.abs(ry), 0, 0, 2 * Math.PI);
      ctx.stroke();
      break;
    }

    case "text": {
      if (ann.x == null || ann.y == null || !ann.label) return;
      const fontSize = ann.fontSize ?? 16;
      ctx.font = `bold ${fontSize}px sans-serif`;
      ctx.fillStyle = ann.color;
      // Shadow for readability over any background
      ctx.shadowColor = "rgba(0,0,0,0.7)";
      ctx.shadowBlur = 3;
      ctx.shadowOffsetX = 1;
      ctx.shadowOffsetY = 1;
      ctx.fillText(ann.label, denorm(ann.x, w), denorm(ann.y, h));
      ctx.shadowColor = "transparent";
      ctx.shadowBlur = 0;
      break;
    }

    case "measurement": {
      if (
        ann.startX == null ||
        ann.startY == null ||
        ann.endX == null ||
        ann.endY == null
      )
        return;
      const from = { x: denorm(ann.startX, w), y: denorm(ann.startY, h) };
      const to = { x: denorm(ann.endX, w), y: denorm(ann.endY, h) };

      // Main line
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();

      // Tick marks at endpoints
      drawTickMark(ctx, from, to);
      drawTickMark(ctx, to, from);

      // Label at midpoint
      if (ann.label) {
        const mid = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 };
        ctx.font = "bold 13px sans-serif";
        ctx.fillStyle = ann.color;
        ctx.shadowColor = "rgba(0,0,0,0.8)";
        ctx.shadowBlur = 3;
        ctx.shadowOffsetX = 1;
        ctx.shadowOffsetY = 1;
        const textMetrics = ctx.measureText(ann.label);
        ctx.fillText(
          ann.label,
          mid.x - textMetrics.width / 2,
          mid.y - 6
        );
        ctx.shadowColor = "transparent";
        ctx.shadowBlur = 0;
      }
      break;
    }
  }
}

/**
 * Redraw all annotations on the canvas.
 *
 * Clears the canvas first, then renders each annotation in order.
 */
export function redrawCanvas(
  canvas: HTMLCanvasElement,
  annotations: Annotation[]
): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  ctx.clearRect(0, 0, canvas.width, canvas.height);

  for (const ann of annotations) {
    drawAnnotation(ctx, ann, canvas.width, canvas.height);
  }
}

// ─── Hook ────────────────────────────────────────────────────────────────────

export interface UsePhotoAnnotationReturn {
  /** Ref to attach to the canvas element. */
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  /** Current list of annotations (read-only snapshot). */
  annotations: Annotation[];
  /** Currently active tool. */
  activeTool: AnnotationTool;
  /** Currently active color (hex). */
  activeColor: string;
  /** Add a new annotation and trigger a redraw. */
  addAnnotation: (ann: Omit<Annotation, "id">) => void;
  /** Remove the last annotation (undo). */
  undoAnnotation: () => void;
  /** Clear all annotations. */
  clearAnnotations: () => void;
  /** Set the active drawing tool. */
  setActiveTool: (tool: AnnotationTool) => void;
  /** Set the active drawing color (hex string). */
  setActiveColor: (color: string) => void;
  /** Get the complete annotation layer for serialization. */
  getAnnotationLayer: (canvasWidth: number, canvasHeight: number) => AnnotationLayer;
}

/**
 * Canvas state management hook for photo annotation.
 *
 * Uses `useRef` (not `useState`) for the annotation array to prevent React
 * re-renders from clearing the canvas on each annotation. The canvas is redrawn
 * imperatively via `redrawCanvas` whenever annotations change.
 *
 * `redrawTrigger` (a useState counter) forces a re-render of the React tree
 * only when needed (e.g., to update toolbar state), without losing canvas pixels.
 */
export function usePhotoAnnotation(
  initialAnnotations?: AnnotationLayer
): UsePhotoAnnotationReturn {
  // ── Refs (mutable, no re-render on change) ───────────────────────────────
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const annotationsRef = useRef<Annotation[]>(
    initialAnnotations?.annotations ?? []
  );
  const activeToolRef = useRef<AnnotationTool>("arrow");
  const activeColorRef = useRef<string>("#D32F2F");

  // ── State (triggers re-render for toolbar UI updates) ────────────────────
  const [redrawTrigger, setRedrawTrigger] = useState(0);
  const [activeTool, setActiveToolState] = useState<AnnotationTool>("arrow");
  const [activeColor, setActiveColorState] = useState<string>("#D32F2F");

  // ── Redraw effect ────────────────────────────────────────────────────────
  useEffect(() => {
    if (canvasRef.current) {
      redrawCanvas(canvasRef.current, annotationsRef.current);
    }
  }, [redrawTrigger]);

  // ── Annotation mutations ─────────────────────────────────────────────────

  const addAnnotation = useCallback((ann: Omit<Annotation, "id">) => {
    annotationsRef.current = [
      ...annotationsRef.current,
      { ...ann, id: crypto.randomUUID() },
    ];
    setRedrawTrigger((t: number) => t + 1);
  }, []);

  const undoAnnotation = useCallback(() => {
    if (annotationsRef.current.length === 0) return;
    annotationsRef.current = annotationsRef.current.slice(0, -1);
    setRedrawTrigger((t: number) => t + 1);
  }, []);

  const clearAnnotations = useCallback(() => {
    annotationsRef.current = [];
    setRedrawTrigger((t: number) => t + 1);
  }, []);

  const setActiveTool = useCallback((tool: AnnotationTool) => {
    activeToolRef.current = tool;
    setActiveToolState(tool);
  }, []);

  const setActiveColor = useCallback((color: string) => {
    activeColorRef.current = color;
    setActiveColorState(color);
  }, []);

  const getAnnotationLayer = useCallback(
    (canvasWidth: number, canvasHeight: number): AnnotationLayer => ({
      version: 1,
      canvasWidth,
      canvasHeight,
      annotations: annotationsRef.current,
    }),
    []
  );

  return {
    canvasRef,
    annotations: annotationsRef.current,
    activeTool,
    activeColor,
    addAnnotation,
    undoAnnotation,
    clearAnnotations,
    setActiveTool,
    setActiveColor,
    getAnnotationLayer,
  };
}
