---
phase: 22-task-execution-and-photo-annotation
plan: "04"
subsystem: photo-annotation
tags: [flutter, canvas, annotation, web, typescript, normalized-coordinates]
dependency_graph:
  requires: [22-02]
  provides: [annotation-schema, photo-annotation-screen, web-annotation-canvas]
  affects: [22-05, task-execution-ui]
tech_stack:
  added:
    - annotation_schema.dart — AnnotationLayer/Annotation data model with JSON serialization
    - usePhotoAnnotation.ts — ref-based canvas state hook
    - drawAnnotation/redrawCanvas — pure canvas rendering functions
    - shadcn progress component (for Plan 05)
  patterns:
    - Normalized 0-1 coordinates for cross-platform annotation rendering
    - Non-destructive annotation storage (base photo immutable; JSON overlay)
    - TDD approach: 9 unit tests written before schema implementation
    - View/draw mode toggle (InteractiveViewer vs GestureDetector in Flutter)
    - useRef (not useState) for annotation array to prevent canvas clearing on re-render
key_files:
  created:
    - mobile/lib/features/projects/domain/annotation_schema.dart
    - mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart
    - mobile/test/features/projects/photo_annotation_test.dart
    - web/src/features/tasks/types.ts
    - web/src/features/tasks/hooks/usePhotoAnnotation.ts
    - web/src/features/tasks/components/PhotoAnnotationCanvas.tsx
    - web/src/components/ui/progress.tsx
  modified:
    - mobile/lib/core/routing/app_router.dart
decisions:
  - "Annotation JSON uses normalized 0-1 coordinates — no raw pixel values stored; enables cross-platform rendering at any resolution"
  - "useRef (not useState) for annotation array in usePhotoAnnotation — prevents React re-renders from clearing canvas imperatively"
  - "crypto.randomUUID() used instead of uuid package — built-in to modern browsers/Node.js; no package needed"
  - "InteractiveViewer disabled during draw mode — prevents gesture conflicts between pan/zoom and drawing gestures"
  - "AnnotationPainter.shouldRepaint always returns true — annotations are mutable state, not const"
  - "Color.toARGB32() used instead of deprecated Color.value — forward compatible with Flutter 3.x"
metrics:
  duration: 10m
  completed: "2026-03-24"
  tasks: 2
  files: 7
---

# Phase 22 Plan 04: Photo Annotation — Mobile + Web Summary

**One-liner:** Shared JSON annotation schema with normalized 0-1 coordinates, Flutter CustomPainter screen with 4 tools (arrow, circle, text, measurement ruler), and HTML5 Canvas web component — both platforms read and write the same JSON format.

## What Was Built

### Task 1: Annotation JSON Schema + Mobile PhotoAnnotationScreen

**`mobile/lib/features/projects/domain/annotation_schema.dart`**
- `enum AnnotationTool { arrow, circle, text, measurement }`
- `class Annotation` — single annotation with normalized 0-1 coordinates, tool-specific fields, JSON serialization
- `class AnnotationLayer` — top-level container with version=1, canvas dimensions, annotations list
- `toJsonString()` / `fromJsonString()` — round-trip serialization for `TaskAttachment.annotationData`
- Unknown tool types are gracefully skipped during deserialization (forward compatibility)

**`mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart`**
- `ConsumerStatefulWidget` with params: `localPath` (photo), `annotationData` (optional existing JSON)
- View mode (default): `InteractiveViewer` with pinch-to-zoom and pan
- Draw mode: `GestureDetector` captures pan gestures; InteractiveViewer disabled to prevent conflicts
- 4 tools: Arrow (pan start→end creates directed line), Circle (pan draws bounding ellipse), Text (tap→AlertDialog), Measurement (pan start→end + showDialog for label)
- `_AnnotationPainter`: CustomPainter with arrow heads, ovals, text labels with shadows, measurement rulers with tick marks and midpoint labels
- Bottom toolbar: 4 tool buttons, 5 color swatches (red/orange/yellow/blue/black), undo, clear-all
- Top bar: "Discard Changes" (pops null), "Save Annotation" (pops JSON string), "Done Drawing" chip
- Route registered: `GoRoute` for `RouteNames.photoAnnotation` accepting `extra: {localPath, annotationData}`

**`mobile/test/features/projects/photo_annotation_test.dart`** — 9 unit tests, all passing:
1. `toJson` produces version=1, canvasWidth, canvasHeight, annotations list
2. `fromJson` round-trips correctly
3. Arrow annotation serializes startX/Y/endX/Y as 0-1 values
4. Circle annotation serializes x/y/width/height as 0-1 values
5. Text annotation serializes x/y/label/fontSize
6. Measurement annotation serializes startX/Y/endX/Y/label
7. Empty annotations list serializes/deserializes correctly
8. Unknown tool type in JSON is gracefully skipped
9. `toJsonString` produces valid parseable JSON

### Task 2: Web PhotoAnnotationCanvas + usePhotoAnnotation Hook

**`web/src/features/tasks/types.ts`** — TypeScript types matching Flutter schema exactly:
- `type AnnotationTool = 'arrow' | 'circle' | 'text' | 'measurement'`
- `interface Annotation` — same fields as Dart model with optional normalized coordinates
- `interface AnnotationLayer` — version:1, canvasWidth, canvasHeight, annotations[]

**`web/src/features/tasks/hooks/usePhotoAnnotation.ts`**
- `usePhotoAnnotation(initialAnnotations?)` hook — annotation state management
- `useRef` for annotation array (mutable without re-render) — prevents canvas clearing
- `drawAnnotation(ctx, ann, w, h)` — renders single annotation with denormalized coordinates
- Arrow: line + arrowhead triangle via atan2; Circle: ctx.ellipse; Text: fillText with shadow; Measurement: line + tick marks at endpoints + centered label at midpoint
- `redrawCanvas(canvas, annotations)` — clear + redraw all annotations
- `addAnnotation`, `undoAnnotation`, `clearAnnotations`, `setActiveTool`, `setActiveColor`
- `getAnnotationLayer(width, height)` — returns `AnnotationLayer` for serialization

**`web/src/features/tasks/components/PhotoAnnotationCanvas.tsx`**
- Props: `imageUrl`, `initialAnnotations?`, `onSave`, `onDiscard`
- `<img>` with `onLoad` syncing canvas dimensions to image natural size
- `<canvas>` absolutely positioned over image with `aria-label` + `role="img"` for accessibility
- Pan mode (default): cursor=grab, events disabled; Draw mode: crosshair, events active
- Mouse event handlers for arrow, circle, text (window.prompt), measurement (window.prompt+label)
- Toolbar: mode toggle, 4 tool buttons with Lucide icons, 5 color swatches, undo, clear-all, save/discard (shadcn Button)

**`web/src/components/ui/progress.tsx`** — shadcn Progress component installed for Plan 05.

## Deviations from Plan

### Auto-fixed Issues

**[Rule 1 - Bug] Removed unused uuid import from PhotoAnnotationScreen**
- Found during: Task 1 (dart analyze warning)
- Issue: `uuid` import from package:uuid/uuid.dart was unused (IDs generated in annotation_schema.dart)
- Fix: Removed the import
- Files modified: `mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart`

**[Rule 1 - Bug] Fixed deprecated Color.value usage**
- Found during: Task 1 (dart analyze info — deprecated_member_use)
- Issue: `color.value.toRadixString(16)` uses deprecated `.value` accessor in Flutter 3.32+
- Fix: Changed to `color.toARGB32().toRadixString(16)`
- Files modified: `mobile/lib/features/projects/presentation/screens/photo_annotation_screen.dart`

**[Rule 2 - Missing] Used crypto.randomUUID() instead of uuid package**
- Found during: Task 2 (uuid not in web package.json or node_modules)
- Issue: `uuid` npm package not available in web project
- Fix: Used built-in `crypto.randomUUID()` — modern browsers and Node.js 19+
- Impact: No package.json change needed

**[Rule 1 - Bug] Fixed implicit any in setRedrawTrigger callbacks**
- Found during: Task 2 (TypeScript strict mode)
- Issue: `(t) => t + 1` — `t` implicitly has type `any` under strict mode
- Fix: Changed to `(t: number) => t + 1`
- Files modified: `web/src/features/tasks/hooks/usePhotoAnnotation.ts`

## Self-Check: PASSED

All 7 created files verified present on disk.
Both commits (88c5e2d, 04d06ce) verified in git history.
All 9 annotation unit tests pass (`flutter test test/features/projects/photo_annotation_test.dart`).
TypeScript compiles without errors in tasks feature (`tsc --noEmit --project tsconfig.json`).
Dart analyze shows no errors or warnings in new files.
