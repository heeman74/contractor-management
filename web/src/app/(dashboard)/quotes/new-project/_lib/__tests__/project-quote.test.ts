import {
  buildProjectQuotePayload,
  emptyFieldSection,
  quoteTotal,
  sectionTotal,
  validateProjectQuote,
  type ProjectQuoteFieldSection,
} from "../project-quote";

function section(
  field: string,
  items: Array<Partial<ProjectQuoteFieldSection["items"][number]>>
): ProjectQuoteFieldSection {
  return {
    key: `s-${field}`,
    field,
    items: items.map((i, idx) => ({
      key: `i-${field}-${idx}`,
      item_type: "labor",
      description: "",
      quantity: "1",
      unit: "hr",
      unit_price: "0",
      ...i,
    })),
  };
}

describe("buildProjectQuotePayload", () => {
  test("flattens sections, carries field, and assigns a single sort sequence", () => {
    const sections = [
      section("Electrical", [
        { item_type: "labor", description: "Install panel", quantity: "8", unit: "hr", unit_price: "90" },
        { item_type: "material", description: "Panel", quantity: "1", unit: "ea", unit_price: "400" },
      ]),
      section("Plumbing", [
        { item_type: "labor", description: "Run lines", quantity: "6", unit: "hr", unit_price: "85" },
      ]),
    ];
    const payload = buildProjectQuotePayload("  Cafe Buildout  ", sections);

    expect(payload.title).toBe("Cafe Buildout");
    expect(payload.line_items).toHaveLength(3);
    expect(payload.line_items.map((i) => [i.field, i.description, i.sort_order])).toEqual([
      ["Electrical", "Install panel", 0],
      ["Electrical", "Panel", 1],
      ["Plumbing", "Run lines", 2],
    ]);
  });

  test("drops blank-description rows and defaults an unnamed field to General", () => {
    const sections = [
      section("", [
        { description: "Real work", unit_price: "10" },
        { description: "   ", unit_price: "10" },
      ]),
    ];
    const payload = buildProjectQuotePayload("T", sections);
    expect(payload.line_items).toHaveLength(1);
    expect(payload.line_items[0].field).toBe("General");
  });
});

describe("totals", () => {
  test("section and quote totals sum quantity × unit price", () => {
    const s = section("Electrical", [
      { description: "a", quantity: "8", unit_price: "90" }, // 720
      { description: "b", quantity: "1", unit_price: "400" }, // 400
    ]);
    expect(sectionTotal(s)).toBe(1120);
    expect(quoteTotal([s, section("P", [{ description: "c", quantity: "2", unit_price: "50" }])])).toBe(
      1220
    );
  });
});

describe("validateProjectQuote", () => {
  const good = [
    section("Electrical", [{ description: "Install", unit_price: "10" }]),
  ];

  test("passes for a titled quote with a described item under a named field", () => {
    expect(validateProjectQuote("Cafe", good)).toEqual({ ok: true });
  });

  test("requires a title", () => {
    expect(validateProjectQuote("  ", good).ok).toBe(false);
  });

  test("requires at least one described line item", () => {
    const empty = [emptyFieldSection("s0", "i0")];
    expect(validateProjectQuote("Cafe", empty).ok).toBe(false);
  });

  test("requires a field name when a section has described items", () => {
    const unnamed = [section("", [{ description: "Install", unit_price: "10" }])];
    const res = validateProjectQuote("Cafe", unnamed);
    expect(res.ok).toBe(false);
    expect(res.error).toMatch(/field/i);
  });
});
