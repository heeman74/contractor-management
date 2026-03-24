/**
 * Annotation types shared between mobile (Flutter) and web (HTML5 Canvas).
 *
 * Coordinates are normalized to 0.0–1.0 relative to the photo dimensions.
 * This ensures annotations render correctly at any resolution on both platforms.
 *
 * JSON schema version: 1
 * Stored in: TaskAttachment.annotationData (nullable TEXT / JSONB)
 */

/** The 4 annotation tools available for photo annotation. */
export type AnnotationTool = "arrow" | "circle" | "text" | "measurement";

/**
 * A single annotation on a photo.
 *
 * Field usage by tool:
 * - arrow:       startX, startY, endX, endY
 * - circle:      x, y, width, height  (bounding rect, top-left + size)
 * - text:        x, y, label, fontSize
 * - measurement: startX, startY, endX, endY, label
 */
export interface Annotation {
  /** Unique ID (UUID v4). */
  id: string;

  /** Drawing tool that produced this annotation. */
  tool: AnnotationTool;

  /** Stroke/fill color as CSS hex string, e.g. "#FF0000". */
  color: string;

  /** Stroke width in pixels. */
  thickness: number;

  // ── Arrow / Measurement fields (normalized 0–1) ──────────────────────────

  /** Start X coordinate (normalized 0–1). Used by arrow and measurement. */
  startX?: number;

  /** Start Y coordinate (normalized 0–1). Used by arrow and measurement. */
  startY?: number;

  /** End X coordinate (normalized 0–1). Used by arrow and measurement. */
  endX?: number;

  /** End Y coordinate (normalized 0–1). Used by arrow and measurement. */
  endY?: number;

  // ── Circle / Text fields (normalized 0–1) ────────────────────────────────

  /** Bounding rect top-left X (normalized 0–1). Used by circle and text. */
  x?: number;

  /** Bounding rect top-left Y (normalized 0–1). Used by circle and text. */
  y?: number;

  /** Bounding rect width (normalized 0–1). Used by circle. */
  width?: number;

  /** Bounding rect height (normalized 0–1). Used by circle. */
  height?: number;

  // ── Text / Measurement label ─────────────────────────────────────────────

  /** Text content for text tool, or measurement value for measurement tool (e.g., "24 inches"). */
  label?: string;

  /** Font size in pixels. Used by text tool. Defaults to 16. */
  fontSize?: number;
}

/**
 * The complete annotation overlay for a photo.
 *
 * Non-destructive: the base photo is never modified.
 * Annotation JSON is stored separately in TaskAttachment.annotationData.
 *
 * @example
 * ```json
 * {
 *   "version": 1,
 *   "canvasWidth": 1920,
 *   "canvasHeight": 1080,
 *   "annotations": [...]
 * }
 * ```
 */
export interface AnnotationLayer {
  /** Schema version — always 1 for current format. */
  version: 1;

  /** Original photo width in pixels (used for coordinate denormalization). */
  canvasWidth: number;

  /** Original photo height in pixels (used for coordinate denormalization). */
  canvasHeight: number;

  /** Ordered list of annotations to render on top of the photo. */
  annotations: Annotation[];
}
