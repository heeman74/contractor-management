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

import { POST, DELETE } from "../route";

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
