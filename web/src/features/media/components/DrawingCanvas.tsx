"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Undo2, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { canvasToBlob } from "../lib/flatten";

const CANVAS_WIDTH = 1000;
const CANVAS_HEIGHT = 700;

const COLORS = ["#0e1726", "#D32F2F", "#F5A623", "#1565C0", "#2E7D32"];
const WIDTHS = [2, 4, 8];

interface Point {
  x: number;
  y: number;
}
interface Stroke {
  color: string;
  width: number;
  points: Point[];
}

interface DrawingCanvasProps {
  onExport: (blob: Blob) => void;
  onCancel: () => void;
}

/** From-scratch drawing pad (freehand) exported as a flattened PNG. */
export function DrawingCanvas({ onExport, onCancel }: DrawingCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const strokesRef = useRef<Stroke[]>([]);
  const drawingRef = useRef<Stroke | null>(null);
  const [color, setColor] = useState(COLORS[0]);
  const [width, setWidth] = useState(WIDTHS[1]);
  const [isExporting, setIsExporting] = useState(false);

  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    const all = drawingRef.current
      ? [...strokesRef.current, drawingRef.current]
      : strokesRef.current;
    for (const stroke of all) {
      if (stroke.points.length === 0) continue;
      ctx.strokeStyle = stroke.color;
      ctx.lineWidth = stroke.width;
      ctx.beginPath();
      ctx.moveTo(stroke.points[0].x, stroke.points[0].y);
      for (const p of stroke.points.slice(1)) ctx.lineTo(p.x, p.y);
      ctx.stroke();
    }
  }, []);

  useEffect(() => {
    redraw();
  }, [redraw]);

  const posFromEvent = (e: React.PointerEvent<HTMLCanvasElement>): Point => {
    const canvas = canvasRef.current!;
    const rect = canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * canvas.width,
      y: ((e.clientY - rect.top) / rect.height) * canvas.height,
    };
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    drawingRef.current = { color, width, points: [posFromEvent(e)] };
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawingRef.current) return;
    drawingRef.current.points.push(posFromEvent(e));
    redraw();
  };

  const handlePointerUp = () => {
    if (drawingRef.current && drawingRef.current.points.length > 0) {
      strokesRef.current = [...strokesRef.current, drawingRef.current];
    }
    drawingRef.current = null;
    redraw();
  };

  const undo = () => {
    strokesRef.current = strokesRef.current.slice(0, -1);
    redraw();
  };
  const clear = () => {
    strokesRef.current = [];
    redraw();
  };

  const save = async () => {
    const canvas = canvasRef.current;
    if (!canvas || strokesRef.current.length === 0) return;
    setIsExporting(true);
    try {
      onExport(await canvasToBlob(canvas));
    } finally {
      setIsExporting(false);
    }
  };

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-card p-2">
        {COLORS.map((c) => (
          <button
            key={c}
            type="button"
            aria-label={`Color ${c}`}
            onClick={() => setColor(c)}
            className={cn(
              "h-6 w-6 rounded-full border-2",
              color === c ? "border-foreground" : "border-transparent"
            )}
            style={{ backgroundColor: c }}
          />
        ))}
        <div className="mx-1 h-6 w-px bg-border" />
        {WIDTHS.map((w) => (
          <button
            key={w}
            type="button"
            aria-label={`Stroke width ${w}`}
            onClick={() => setWidth(w)}
            className={cn(
              "flex h-7 w-7 items-center justify-center rounded-md border",
              width === w ? "border-brand bg-brand/10" : "border-border"
            )}
          >
            <span
              className="rounded-full bg-foreground"
              style={{ width: w + 2, height: w + 2 }}
            />
          </button>
        ))}
        <div className="mx-1 h-6 w-px bg-border" />
        <Button variant="outline" size="sm" onClick={undo} title="Undo">
          <Undo2 className="h-4 w-4" />
        </Button>
        <Button variant="outline" size="sm" onClick={clear} title="Clear">
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <div className="overflow-hidden rounded-lg border border-border bg-white">
        <canvas
          ref={canvasRef}
          width={CANVAS_WIDTH}
          height={CANVAS_HEIGHT}
          className="block w-full touch-none"
          style={{ cursor: "crosshair", aspectRatio: `${CANVAS_WIDTH} / ${CANVAS_HEIGHT}` }}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerLeave={handlePointerUp}
        />
      </div>

      <div className="flex justify-end gap-2">
        <Button variant="ghost" size="sm" onClick={onCancel}>
          Cancel
        </Button>
        <Button variant="brand" size="sm" onClick={save} disabled={isExporting}>
          Add drawing
        </Button>
      </div>
    </div>
  );
}
