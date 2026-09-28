import { formatQuoteReference } from "../quote-list";
import type { Quote } from "@/types/api";

function quote(partial: Partial<Quote>): Quote {
  return {
    id: "27e6e3b9-ff72-4507-8e27-3d990a24dfab",
    quote_number: null,
    ...partial,
  } as Quote;
}

describe("formatQuoteReference", () => {
  test("uses the zero-padded numeric quote number when present", () => {
    expect(formatQuoteReference(quote({ quote_number: 7 }))).toBe("0007");
    expect(formatQuoteReference(quote({ quote_number: 1234 }))).toBe("1234");
  });

  test("falls back to a UUID slice for legacy quotes without a number", () => {
    expect(formatQuoteReference(quote({ quote_number: null }))).toBe("QT-27E6E3");
  });
});
