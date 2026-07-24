import "@testing-library/jest-dom";

// jsdom lacks the pointer-capture / scroll APIs that Radix UI (Select, etc.)
// calls during interaction. Stub them so component tests can drive Radix widgets.
if (typeof Element !== "undefined") {
  Element.prototype.hasPointerCapture ??= () => false;
  Element.prototype.releasePointerCapture ??= () => {};
  Element.prototype.scrollIntoView ??= () => {};
}
