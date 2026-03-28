import { cn, clampPercent } from "../utils";

describe("cn", () => {
  test("merges class names", () => {
    expect(cn("px-2", "py-1")).toBe("px-2 py-1");
  });

  test("handles conditional classes", () => {
    expect(cn("base", false && "hidden", "visible")).toBe("base visible");
  });

  test("deduplicates conflicting Tailwind classes", () => {
    // tailwind-merge should resolve px-2 vs px-4
    expect(cn("px-2", "px-4")).toBe("px-4");
  });

  test("handles undefined and null inputs", () => {
    expect(cn("base", undefined, null)).toBe("base");
  });

  test("returns empty string for no inputs", () => {
    expect(cn()).toBe("");
  });
});

describe("clampPercent", () => {
  test("returns value within 0-100 range unchanged", () => {
    expect(clampPercent(50)).toBe(50);
    expect(clampPercent(0)).toBe(0);
    expect(clampPercent(100)).toBe(100);
  });

  test("clamps values above 100 to 100", () => {
    expect(clampPercent(150)).toBe(100);
    expect(clampPercent(999)).toBe(100);
  });

  test("clamps values below 0 to 0", () => {
    expect(clampPercent(-10)).toBe(0);
    expect(clampPercent(-999)).toBe(0);
  });

  test("handles boundary values", () => {
    expect(clampPercent(0.001)).toBe(0.001);
    expect(clampPercent(99.999)).toBe(99.999);
  });
});
