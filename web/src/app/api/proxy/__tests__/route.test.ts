/**
 * @jest-environment node
 */
/**
 * The proxy must not hand a body to a null-body status.
 *
 * 204/205/304 make the Response constructor throw if given any body, empty
 * string included. Every DELETE in the API and change-password answer 204, so
 * forwarding them as text turned a committed write into a 500.
 */
import { NextRequest } from "next/server";

const mockCookieGet = jest.fn();
jest.mock("next/headers", () => ({
  cookies: async () => ({ get: mockCookieGet }),
}));

import { GET, POST, DELETE } from "../route";

const PROXY_URL =
  "http://localhost:3000/api/proxy?path=%2Fapi%2Fv1%2Fauth%2Fchange-password";

describe("api/proxy null-body statuses", () => {
  beforeEach(() => {
    jest.restoreAllMocks();
    mockCookieGet.mockReturnValue({ value: "test-access-token" });
  });

  it.each([204, 205, 304])("forwards %i without throwing", async (status) => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(null, { status, headers: { "x-upstream": "1" } })
    );

    const res = await POST(
      new NextRequest(PROXY_URL, {
        method: "POST",
        body: JSON.stringify({ current_password: "a", new_password: "b" }),
        headers: { "content-type": "application/json" },
      })
    );

    expect(res.status).toBe(status);
    await expect(res.text()).resolves.toBe("");
  });

  it("forwards a DELETE 204 without throwing", async () => {
    global.fetch = jest.fn().mockResolvedValue(new Response(null, { status: 204 }));

    const res = await DELETE(
      new NextRequest(
        "http://localhost:3000/api/proxy?path=%2Fapi%2Fv1%2Ffinance%2Fcost-entries%2Fabc",
        { method: "DELETE" }
      )
    );

    expect(res.status).toBe(204);
  });

  it("still forwards a JSON body for statuses that allow one", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(JSON.stringify({ detail: "Current password is incorrect" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      })
    );

    const res = await POST(
      new NextRequest(PROXY_URL, {
        method: "POST",
        body: JSON.stringify({ current_password: "wrong", new_password: "b" }),
        headers: { "content-type": "application/json" },
      })
    );

    expect(res.status).toBe(400);
    await expect(res.json()).resolves.toEqual({
      detail: "Current password is incorrect",
    });
  });
});

describe("binary responses", () => {
  // A PDF is not text. Reading the upstream with .text() decoded it as UTF-8,
  // so every byte that was not valid UTF-8 became U+FFFD — which inflated a
  // 13KB quote PDF to 23KB and produced a file no reader would open. The bytes
  // have to survive the proxy untouched.
  const PDF_BYTES = new Uint8Array([
    0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, // %PDF-1.7
    0x0a, 0x80, 0x81, 0xfe, 0xff, 0x00, 0x1b, 0x9d, // bytes that are invalid UTF-8
    0xc3, 0x28, 0xa0, 0xa1, 0xf0, 0x28, 0x8c, 0x28,
  ]);

  it("passes binary through byte for byte", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(PDF_BYTES, {
        status: 200,
        headers: {
          "content-type": "application/pdf",
          "content-disposition": 'attachment; filename="quote-abc.pdf"',
        },
      })
    ) as unknown as typeof fetch;

    const res = await GET(
      new NextRequest(
        "http://localhost:3000/api/proxy?path=%2Fapi%2Fv1%2Fquotes%2Fabc%2Fpdf"
      )
    );

    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/pdf");
    const received = new Uint8Array(await res.arrayBuffer());
    expect(received.length).toBe(PDF_BYTES.length);
    expect(Array.from(received)).toEqual(Array.from(PDF_BYTES));
  });

  it("keeps the filename the backend chose", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(PDF_BYTES, {
        status: 200,
        headers: {
          "content-type": "application/pdf",
          "content-disposition": 'attachment; filename="quote-abc.pdf"',
        },
      })
    ) as unknown as typeof fetch;

    const res = await GET(
      new NextRequest(
        "http://localhost:3000/api/proxy?path=%2Fapi%2Fv1%2Fquotes%2Fabc%2Fpdf"
      )
    );

    expect(res.headers.get("content-disposition")).toBe(
      'attachment; filename="quote-abc.pdf"'
    );
  });
});
