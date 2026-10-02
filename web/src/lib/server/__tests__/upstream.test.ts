/**
 * @jest-environment node
 */
/**
 * A sleeping backend must not read as a broken one.
 *
 * The distinction that matters: a failure to get ANY response is retried,
 * because the attempt that fails is usually the one doing the waking. An HTTP
 * error response is a real answer and must pass through untouched — retrying a
 * 401 would be wrong, and masking it would be worse.
 */
import { type RequestListener, type Server, createServer } from "node:http";
import type { AddressInfo } from "node:net";

import { UPSTREAM_TIMEOUT_MS, fetchUpstream } from "../upstream";

const originalFetch = global.fetch;

afterEach(() => {
  global.fetch = originalFetch;
});

it("returns the response when the first attempt succeeds", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("ok", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res?.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("retries once when the first attempt never lands — the cold-start case", async () => {
  const fetchMock = jest
    .fn()
    .mockRejectedValueOnce(new Error("timeout"))
    .mockResolvedValueOnce(new Response("ok", { status: 200 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res?.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("returns null only after both attempts fail", async () => {
  const fetchMock = jest.fn().mockRejectedValue(new Error("ECONNREFUSED"));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/health");

  expect(res).toBeNull();
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("does NOT retry an HTTP error — a 401 is an answer, not a failure", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response("nope", { status: 401 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  const res = await fetchUpstream("http://api.test/login", { method: "POST" });

  expect(res?.status).toBe(401);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

it("applies a stated timeout rather than inheriting a default", async () => {
  const fetchMock = jest.fn().mockResolvedValue(new Response(null, { status: 204 }));
  global.fetch = fetchMock as unknown as typeof fetch;

  await fetchUpstream("http://api.test/x", { method: "POST", body: "{}" });

  const init = fetchMock.mock.calls[0][1] as RequestInit;
  expect(init.signal).toBeInstanceOf(AbortSignal);
  expect(init.method).toBe("POST");
  expect(init.body).toBe("{}");
});

it("allows enough time for an observed cold start", () => {
  // The deployed API took ~62s to wake. A budget under that would reintroduce
  // the exact failure this helper exists to prevent.
  expect(UPSTREAM_TIMEOUT_MS).toBeGreaterThan(62_000);
});

/**
 * The production 401: a trailing-slash redirect that lost the credentials.
 *
 * These run against real servers rather than a fetch mock, because the bug was
 * in fetch's own redirect handling — a mock would have happily "passed" the
 * header through and proved nothing.
 */
describe("redirects", () => {
  const servers: Server[] = [];

  const listen = (handler: RequestListener): Promise<number> => {
    const server = createServer(handler);
    servers.push(server);
    return new Promise((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        resolve((server.address() as AddressInfo).port);
      });
    });
  };

  afterEach(async () => {
    await Promise.all(
      servers.splice(0).map((s) => new Promise((done) => s.close(() => done(null))))
    );
  });

  it("re-issues a scheme-downgraded hop on the origin it started from", async () => {
    // The production shape exactly: same host, Location downgraded to http
    // because that is what the upstream received behind the TLS terminator.
    // Re-issuing on the original origin is what keeps the hop same-origin, and
    // same-origin is the only reason the credentials survive — proven against
    // real servers in the sibling test below, where a cross-origin hop arrives
    // with no Authorization at all.
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(
        new Response(null, {
          status: 307,
          headers: { Location: "http://api.test/api/v1/jobs/?limit=10" },
        })
      )
      .mockResolvedValueOnce(new Response("ok", { status: 200 }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const res = await fetchUpstream("https://api.test/api/v1/jobs?limit=10", {
      headers: { Authorization: "Bearer the-real-token" },
    });

    expect(res?.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[1][0]).toBe("https://api.test/api/v1/jobs/?limit=10");
    const followInit = fetchMock.mock.calls[1][1] as RequestInit;
    expect(followInit.headers).toEqual({ Authorization: "Bearer the-real-token" });
  });

  it("confirms a cross-origin hop is what loses the header", async () => {
    // Not a test of our code — a check that the premise still holds in this
    // runtime. If fetch ever stops stripping Authorization across origins, the
    // origin-rewriting above becomes unnecessary rather than load-bearing.
    let authSeen: string | undefined = "header never arrived";
    const targetPort = await listen((req, res) => {
      authSeen = req.headers.authorization;
      res.end("ok");
    });
    const sourcePort = await listen((_req, res) => {
      res.writeHead(307, { Location: `http://127.0.0.1:${targetPort}/api/v1/jobs/` });
      res.end();
    });

    await fetch(`http://127.0.0.1:${sourcePort}/api/v1/jobs`, {
      headers: { Authorization: "Bearer the-real-token" },
    });

    expect(authSeen).toBeUndefined();
  });

  it("preserves the method and body through a 307", async () => {
    // A same-origin hop, which fetch already followed correctly — this guards
    // our own following against regressing what it replaced.
    let seen: { method?: string; body: string } = { body: "" };
    const port = await listen((req, res) => {
      if (req.url === "/api/v1/quotes") {
        res.writeHead(307, { Location: "/api/v1/quotes/" });
        res.end();
        return;
      }
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        seen = { method: req.method, body };
        res.end("ok");
      });
    });

    await fetchUpstream(`http://127.0.0.1:${port}/api/v1/quotes`, {
      method: "POST",
      body: '{"title":"x"}',
    });

    expect(seen.method).toBe("POST");
    expect(seen.body).toBe('{"title":"x"}');
  });

  it("refuses to carry credentials to a different host", async () => {
    // A redirect off-host must not hand our token to whoever answers there.
    const sourcePort = await listen((_req, res) => {
      res.writeHead(307, { Location: "http://attacker.example/api/v1/jobs/" });
      res.end();
    });

    const res = await fetchUpstream(`http://127.0.0.1:${sourcePort}/api/v1/jobs`, {
      headers: { Authorization: "Bearer the-real-token" },
    });

    // The hop is not taken; the redirect itself comes back.
    expect(res?.status).toBe(307);
  });

  it("does not follow a redirect loop forever", async () => {
    const sourcePort = await listen((_req, res) => {
      res.writeHead(307, { Location: "/api/v1/jobs/" });
      res.end();
    });

    const res = await fetchUpstream(`http://127.0.0.1:${sourcePort}/api/v1/jobs`);

    expect(res?.status).toBe(307);
  });
});

/**
 * A 429 the API did not write.
 *
 * Everything the API sends is JSON, so a refusal without a JSON body came from
 * the platform in front of it — which sees a single address posting every user's
 * login and reads that as credential stuffing. Free web services cannot receive
 * private-network requests, so this hop has to cross the public edge and the
 * throttle cannot be designed away; waiting briefly and trying once more gets a
 * person in during a short one.
 */
describe("a throttle that is not the API's", () => {
  const platform429 = () =>
    new Response("<html>too many requests</html>", {
      status: 429,
      headers: { "content-type": "text/html" },
    });

  it("waits and tries once more", async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(platform429())
      .mockResolvedValueOnce(new Response("{}", { status: 200 }));
    global.fetch = fetchMock as unknown as typeof fetch;

    const res = await fetchUpstream("https://api.test/api/v1/auth/login");

    expect(res?.status).toBe(200);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("gives up after the second refusal rather than looping", async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(platform429())
      .mockResolvedValueOnce(platform429());
    global.fetch = fetchMock as unknown as typeof fetch;

    const res = await fetchUpstream("https://api.test/api/v1/auth/login");

    expect(res?.status).toBe(429);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("does not retry the API's own rate limit", async () => {
    // Arguing with a decision the API already made, and spending someone's
    // remaining budget to do it.
    const fetchMock = jest.fn().mockResolvedValue(
      new Response(JSON.stringify({ detail: "Too many attempts." }), {
        status: 429,
        headers: { "content-type": "application/json" },
      })
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    const res = await fetchUpstream("https://api.test/api/v1/auth/login");

    expect(res?.status).toBe(429);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
