"use client";

import {
  ArrowRight,
  Circle,
  Minus,
  Ruler,
  Type,
  Undo2,
  Trash2,
} from "lucide-react";
import { useCallback, useRef, useState } from "react";

import { Button } from "@/components/ui/button";

import type { AnnotationLayer, AnnotationTool } from "../types";
import { usePhotoAnnotation } from "../hooks/usePhotoAnnotation";

/** Color presets matching mobile implementation. */
const COLOR_PRESETS: { color: string; label: string }[] = [
  { color: "#D32F2F", label: "Red" },
  { color: "#F57C00", label: "Orange" },
  { color: "#FFC107", label: "Yellow" },
  { color: "#1565C0", label: "Blue" },
  { color: "#000000", label: "Black" },
];

/** Tool definitions with Lucide icons and labels. */
const TOOLS: {
  tool: AnnotationTool;
  label: string;
  Icon: React.ComponentType<{ size?: number; className?: string }>;
}[] = [
  { tool: "arrow", label: "Arrow", Icon: ArrowRight },
  { tool: "circle", label: "Circle", Icon: Circle },
  { tool: "text", label: "Text", Icon: Type },
  { tool: "measurement", label: "Measure", Icon: Ruler },
];

// ─── Props ───────────────────────────────────────────────────────────────────

export interface PhotoAnnotationCanvasProps {
  /** URL of the photo to annotate. */
  imageUrl: string;
  /** Optional existing annotation JSON to pre-load. */
  initialAnnotations?: AnnotationLayer;
  /** Called with the annotation JSON string when Save is clicked. */
  onSave: (json: string) => void;
  /** Called when Discard Changes is clicked. */
  onDiscard: () => void;
}

// ─── Component ───────────────────────────────────────────────────────────────

/**
 * Photo annotation canvas component.
 *
 * Renders a photo with an HTML5 Canvas overlay for drawing annotations.
 * Supports 4 tools: arrow, circle, text (prompt), measurement (prompt + label).
 *
 * The canvas size matches the natural dimensions of the loaded image.
 * All annotation coordinates are normalized to 0–1 for cross-platform
 * compatibility with the mobile (Flutter) implementation.
 *
 * Pan mode: CSS cursor "grab", canvas events disabled.
 * Draw mode: canvas mouse events active, pan disabled.
 */
export function PhotoAnnotationCanvas({
  imageUrl,
  initialAnnotations,
  onSave,
  onDiscard,
}: PhotoAnnotationCanvasProps) {
  const {
    canvasRef,
    activeTool,
    activeColor,
    addAnnotation,
    undoAnnotation,
    clearAnnotations,
    setActiveTool,
    setActiveColor,
    getAnnotationLayer,
  } = usePhotoAnnotation(initialAnnotations);

  // ── Mode state ────────────────────────────────────────────────────────────
  const [mode, setMode] = useState<"pan" | "draw">("pan");

  // ── Image load state (needed for canvas dimension sync) ──────────────────
  const imgRef = useRef<HTMLImageElement>(null);

  // ── In-progress drag state ────────────────────────────────────────────────
  const isDraggingRef = useRef(false);
  const dragStartRef = useRef<{ x: number; y: number } | null>(null);

  // ── Image load handler ────────────────────────────────────────────────────
  const handleImageLoad = useCallback(() => {
    const img = imgRef.current;
    const canvas = canvasRef.current;
    if (!img || !canvas) return;

    // Match canvas pixel dimensions to the image's natural dimensions.
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
  }, [canvasRef]);

  // ── Canvas coordinate helpers ─────────────────────────────────────────────

  /** Get mouse position relative to canvas, normalized to 0–1. */
  const getNormalizedPos = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      const canvas = canvasRef.current;
      if (!canvas) return { nx: 0, ny: 0 };
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      return {
        nx: ((e.clientX - rect.left) * scaleX) / canvas.width,
        ny: ((e.clientY - rect.top) * scaleY) / canvas.height,
      };
    },
    [canvasRef]
  );

  // ── Mouse event handlers ──────────────────────────────────────────────────

  const handleMouseDown = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (mode !== "draw") return;
      const { nx, ny } = getNormalizedPos(e);
      isDraggingRef.current = true;
      dragStartRef.current = { x: nx, y: ny };
    },
    [mode, getNormalizedPos]
  );

  const handleMouseUp = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (mode !== "draw" || !isDraggingRef.current) return;
      isDraggingRef.current = false;

      const start = dragStartRef.current;
      if (!start) return;
      dragStartRef.current = null;

      const { nx, ny } = getNormalizedPos(e);

      switch (activeTool) {
        case "arrow": {
          addAnnotation({
            tool: "arrow",
            color: activeColor,
            thickness: 3,
            startX: start.x,
            startY: start.y,
            endX: nx,
            endY: ny,
          });
          break;
        }

        case "circle": {
          const x = Math.min(start.x, nx);
          const y = Math.min(start.y, ny);
          const width = Math.abs(nx - start.x);
          const height = Math.abs(ny - start.y);
          if (width > 0.001 && height > 0.001) {
            addAnnotation({
              tool: "circle",
              color: activeColor,
              thickness: 3,
              x,
              y,
              width,
              height,
            });
          }
          break;
        }

        case "measurement": {
          const label = window.prompt("Enter measurement (e.g. 24 inches)");
          if (label && label.trim()) {
            addAnnotation({
              tool: "measurement",
              color: activeColor,
              thickness: 2,
              startX: start.x,
              startY: start.y,
              endX: nx,
              endY: ny,
              label: label.trim(),
            });
          }
          break;
        }

        default:
          break;
      }
    },
    [mode, activeTool, activeColor, addAnnotation, getNormalizedPos]
  );

  const handleCanvasClick = useCallback(
    (e: React.MouseEvent<HTMLCanvasElement>) => {
      if (mode !== "draw" || activeTool !== "text") return;
      const { nx, ny } = getNormalizedPos(e);
      const label = window.prompt("Enter text label");
      if (label && label.trim()) {
        addAnnotation({
          tool: "text",
          color: activeColor,
          thickness: 1,
          x: nx,
          y: ny,
          label: label.trim(),
          fontSize: 16,
        });
      }
    },
    [mode, activeTool, activeColor, addAnnotation, getNormalizedPos]
  );

  // ── Save handler ──────────────────────────────────────────────────────────

  const handleSave = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const layer = getAnnotationLayer(canvas.width, canvas.height);
    onSave(JSON.stringify(layer));
  }, [canvasRef, getAnnotationLayer, onSave]);

  // ── Render ────────────────────────────────────────────────────────────────

  const canvasCursor = mode === "pan" ? "grab" : "crosshair";

  return (
    <div className="flex flex-col gap-3">
      {/* ── Canvas area ─────────────────────────────────────────────────── */}
      <div className="relative w-full overflow-hidden rounded-lg border border-border bg-black">
        {/* Base photo */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          ref={imgRef}
          src={imageUrl}
          alt="Photo to annotate"
          className="block w-full"
          onLoad={handleImageLoad}
        />

        {/* Annotation canvas — absolutely positioned over image */}
        <canvas
          ref={canvasRef}
          aria-label="Photo annotation canvas"
          role="img"
          className="absolute inset-0 w-full h-full"
          style={{ cursor: canvasCursor }}
          onMouseDown={handleMouseDown}
          onMouseUp={handleMouseUp}
          onClick={handleCanvasClick}
        />
      </div>

      {/* ── Toolbar ──────────────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-2 p-2 rounded-lg border border-border bg-card">
        {/* Mode toggle */}
        <Button
          variant={mode === "draw" ? "default" : "outline"}
          size="sm"
          onClick={() => setMode(mode === "draw" ? "pan" : "draw")}
          className="text-xs"
        >
          {mode === "draw" ? "Drawing Mode" : "View Mode"}
        </Button>

        <div className="w-px h-6 bg-border" />

        {/* Tool buttons */}
        {TOOLS.map(({ tool, label, Icon }) => (
          <Button
            key={tool}
            variant="outline"
            size="sm"
            aria-pressed={activeTool === tool}
            title={label}
            onClick={() => {
              setActiveTool(tool);
              setMode("draw");
            }}
            className={
              activeTool === tool && mode === "draw"
                ? "bg-primary text-primary-foreground border-primary"
                : ""
            }
          >
            <Icon size={16} />
            <span className="sr-only">{label}</span>
          </Button>
        ))}

        <div className="w-px h-6 bg-border" />

        {/* Color swatches */}
        {COLOR_PRESETS.map(({ color, label }) => (
          <button
            key={color}
            title={label}
            aria-label={`Color: ${label}`}
            onClick={() => setActiveColor(color)}
            className="rounded-full border-2 transition-all"
            style={{
              width: 24,
              height: 24,
              backgroundColor: color,
              borderColor: activeColor === color ? "#fff" : "transparent",
              outline:
                activeColor === color ? "2px solid #888" : "none",
            }}
          />
        ))}

        <div className="w-px h-6 bg-border" />

        {/* Undo */}
        <Button
          variant="outline"
          size="sm"
          title="Undo"
          onClick={undoAnnotation}
        >
          <Undo2 size={16} />
          <span className="sr-only">Undo</span>
        </Button>

        {/* Clear all */}
        <Button
          variant="outline"
          size="sm"
          title="Clear all annotations"
          onClick={() => {
            if (window.confirm("Clear all annotations?")) {
              clearAnnotations();
            }
          }}
        >
          <Trash2 size={16} />
          <span className="sr-only">Clear all</span>
        </Button>

        <div className="flex-1" />

        {/* Discard */}
        <Button variant="ghost" size="sm" onClick={onDiscard}>
          Discard Changes
        </Button>

        {/* Save */}
        <Button variant="default" size="sm" onClick={handleSave}>
          Save Annotation
        </Button>
      </div>

      {/* Unused icon to ensure it's not tree-shaken — only for type check */}
      <span className="sr-only">
        <Minus size={0} />
      </span>
    </div>
  );
}
