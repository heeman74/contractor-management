/**
 * @jest-environment node
 */
/**
 * The API only ever sees this app.
 *
 * Every browser request reaches it through here, so unless the browser's address
 * is carried along, per-client rate limits collapse into one bucket for the
 * whole world — `5/minute` on login meant five logins a minute across all users,
 * and a person testing collected 429s somebody else had earned.
 */
import {
  CLIENT_IP_HEADER,
  clientIpHeaders,
  clientIpOf,
  upstreamErrorBody,
} from "../upstream";

const requestWith = (headers: Record<string, string>) =>
  new Request("https://app.test/api/auth/login", { headers });

it("takes the browser from the front of the forwarded chain", () => {
  // The platform appends its own hops, so later entries are proxies, not people.
  const request = requestWith({
    "x-forwarded-for": "203.0.113.9, 10.0.0.4, 10.0.0.5",
  });

  expect(clientIpOf(request)).toBe("203.0.113.9");
});

it("tolerates a chain written with spaces", () => {
  expect(clientIpOf(requestWith({ "x-forwarded-for": "  203.0.113.9 " }))).toBe(
    "203.0.113.9"
  );
});

it("falls back to x-real-ip", () => {
  expect(clientIpOf(requestWith({ "x-real-ip": "203.0.113.10" }))).toBe(
    "203.0.113.10"
  );
});

it("returns null when the address is unknowable", () => {
  // So the caller omits the header and the API keys on the connecting address,
  // rather than counting every unknown caller as one shared client.
  expect(clientIpOf(requestWith({}))).toBeNull();
});

it("builds the header the API reads", () => {
  expect(clientIpHeaders(requestWith({ "x-forwarded-for": "203.0.113.9" }))).toEqual({
    [CLIENT_IP_HEADER]: "203.0.113.9",
  });
});

it("builds no header at all when there is nothing to say", () => {
  expect(clientIpHeaders(requestWith({}))).toEqual({});
});

/**
 * An upstream error that is not JSON did not come from the API.
 *
 * The platform throttling this app's own calls to the API arrived at the browser
 * as "Login failed" — a credential message for a network event, which sent the
 * search in entirely the wrong direction for hours.
 */
describe("upstreamErrorBody", () => {
  it("passes the API's own detail through untouched", async () => {
    const response = new Response(
      JSON.stringify({ detail: "Invalid email or password" }),
      { status: 401, headers: { "content-type": "application/json" } }
    );

    expect(await upstreamErrorBody(response, "Login failed.")).toEqual({
      detail: "Invalid email or password",
    });
  });

  it("says the request never reached the API when the body is not JSON", async () => {
    const response = new Response("<html>429 from somewhere else</html>", {
      status: 429,
      headers: { "content-type": "text/html" },
    });

    const { detail } = await upstreamErrorBody(response, "Login failed.");

    expect(detail).toContain("429");
    expect(detail).toContain("did not reach the application");
    expect(detail).not.toBe("Login failed.");
  });

  it("does the same for an empty body", async () => {
    const { detail } = await upstreamErrorBody(
      new Response(null, { status: 502 }),
      "Login failed."
    );

    expect(detail).toContain("502");
  });
});

it("logs who answered when the refusal is not the API's", async () => {
  // Two rounds were spent guessing at this from outside. The sender puts its
  // name in these headers, so the next occurrence names itself.
  const logged: string[] = [];
  const spy = jest
    .spyOn(console, "error")
    .mockImplementation((line) => logged.push(String(line)));

  const response = new Response("<html>too many requests</html>", {
    status: 429,
    headers: {
      "content-type": "text/html",
      server: "cloudflare",
      "cf-ray": "a44584d7baf751ae-LAX",
      "retry-after": "30",
    },
  });

  await upstreamErrorBody(response, "Login failed.");

  spy.mockRestore();
  expect(logged).toHaveLength(1);
  const entry = JSON.parse(logged[0]);
  expect(entry.event).toBe("upstream_error_not_from_api");
  expect(entry.status).toBe(429);
  expect(entry.server).toBe("cloudflare");
  expect(entry.cfRay).toBe("a44584d7baf751ae-LAX");
  expect(entry.retryAfter).toBe("30");
  expect(entry.body).toContain("too many requests");
});

it("logs nothing when the API answered for itself", async () => {
  const spy = jest.spyOn(console, "error").mockImplementation(() => {});

  await upstreamErrorBody(
    new Response(JSON.stringify({ detail: "Invalid email or password" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    }),
    "Login failed."
  );

  expect(spy).not.toHaveBeenCalled();
  spy.mockRestore();
});
