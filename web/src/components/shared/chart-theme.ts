/**
 * The single home for chart chrome, colour bands and geometry.
 *
 * Every value here is locked by the Phase 35 UI design contract (35-UI-SPEC
 * § Color, § Shared chart chrome). Chart files import from this module rather
 * than re-typing a hex, a row height or an axis bound, so a tooltip style or a
 * tier colour can never fork between two charts.
 */

/** Repeated verbatim by every shipped Reports chart — extracted so there is no fourth copy. */
export const CHART_TOOLTIP_STYLE = {
  backgroundColor: "white",
  border: "1px solid var(--border)",
  borderRadius: "6px",
  boxShadow: "0 1px 2px rgba(0,0,0,0.05)",
  padding: "8px",
} as const;

/** Chart chrome renders at 11px — SVG only, never part of the authored type scale. */
export const CHART_TICK = { fontSize: 11 } as const;

/** Colour encodes exactly one variable on the bullet bars: how much budget is spent. */
export const BUDGET_TIER_FILL = {
  normal: "#59637a",
  warning: "#f5a623",
  over: "#d64545",
} as const;

/** The warning band opens here, but only while money remains (see budgetTierFill). */
export const BUDGET_WARNING_PERCENT = 80;

/** Draft/complete/archived projects are de-emphasized, never excluded (D-12). */
export const INACTIVE_BAR_FILL_OPACITY = 0.45;

/** The 100% budget line every bullet bar is read against — ink, not a tier colour,
 *  because the reference is the same wherever a bar happens to fall. */
export const BULLET_REFERENCE_STROKE = "#0e1726";

/** The clamp overflow label. red-800 rather than --destructive: this glyph renders at
 *  11px, where #d64545 is sub-AA (35-UI-SPEC § the red rule). */
export const OVERFLOW_LABEL_FILL = "#991b1b";

/** Nominal ramp: cost categories carry no ordering, so hues are stable per name and never repeat. */
export const CATEGORY_FILL: Record<string, string> = {
  labor: "#0e1726",
  materials: "#59637a",
  subcontractor: "#8a93a6",
  other: "#b6bcc9",
};

/** Company-custom categories, assigned alphabetically. Beyond these two, categories roll up. */
export const CUSTOM_CATEGORY_FILLS = ["#3d4a63", "#d9dce3"] as const;

/** The rollup bucket. Also matches the system category of the same name. */
export const OTHER_CATEGORY_NAME = "Other";

/** Hue is spent on importance, not identity: the focal margin line gets maximum contrast,
 *  and cost is distinguished from revenue by texture so the trend reads in greyscale. */
export const TREND_SERIES = {
  margin: { stroke: "#0e1726", strokeWidth: 2.5 },
  revenue: { stroke: "#59637a", strokeWidth: 1.5 },
  cost: { stroke: "#59637a", strokeWidth: 1.5, strokeDasharray: "4 3" },
} as const;

export const BREAK_EVEN_STROKE = "#d64545";

/** Bullet-bar geometry: a floor per row, never compressed (35-UI-SPEC § Chart 1). */
export const BULLET_ROW_HEIGHT = 28;
export const BULLET_BAR_SIZE = 12;
export const BULLET_AXIS_WIDTH = 160;

/** Vertical room the plot needs for its value axis on top of the rows themselves. */
export const BULLET_CHART_AXIS_PADDING = 36;

/** The viewport is bounded; the plot inside it is not, so rows keep their full height. */
export const BULLET_VIEWPORT_MAX_CLASS = "max-h-[420px] overflow-y-auto pr-2";

export const CHART_HEIGHT = 280;

/** A single extreme overrun would otherwise collapse every other bar into a stub. */
export const PERCENT_AXIS_CLAMP = 200;

/** Headroom that keeps the 100% budget reference line on screen when nothing is near budget. */
export const PERCENT_AXIS_FLOOR = 120;

/** Six slices is the range in which a pie is defensible at all; past it, categories roll up. */
export const MAX_PIE_SLICES = 6;

/** Below this share, an on-slice label would collide with its neighbours. */
export const PIE_LABEL_MIN_PERCENT = 5;

/** A 160px axis at 11px fits ~26 characters; truncating at 22 leaves margin. */
export const LABEL_TRUNCATE_LENGTH = 22;
