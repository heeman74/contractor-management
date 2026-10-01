import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

import {
UPSTREAM_ERROR_HEADER,
  UPSTREAM_UNREACHABLE_DETAIL,
  clientIpHeaders,
  fetchUpstream,
} from "@/lib/server/upstream";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

// Next reads route segment config statically, so this must be a literal —
// referencing an imported constant fails the build with "Invalid segment
// configuration export". Keep in step with UPSTREAM_TIMEOUT_MS in
// lib/server/upstream.ts, which allows one retry inside this budget.
export const maxDuration = 90;

// Statuses the Fetch spec forbids from carrying a body.
const NULL_BODY_STATUSES = new Set([204, 205, 304]);

async function handleProxy(request: NextRequest): Promise<NextResponse> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("access_token")?.value;

  if (!accessToken) {
    return NextResponse.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const path = searchParams.get("path");

  if (!path) {
    return NextResponse.json({ detail: "Missing path parameter" }, { status: 400 });
  }

  // Validate against the PARSED/normalized URL, not the raw string. A raw-string
  // check for ".." / "://" is bypassable with URL-encoded dot segments (e.g.
  // "/api/v1/%2e%2e/%2e%2e/openapi.json"), which undici normalizes AFTER the check,
  // escaping the /api/v1/ allowlist to unauthenticated backend mounts (docs, openapi).
  // Resolving `path` against the upstream base and checking the normalized origin +
  // pathname closes encoded-traversal, protocol-relative (//host), and absolute-URL vectors.
  const upstreamBase = new URL(FASTAPI_URL);
  let target: URL;
  try {
    target = new URL(path, upstreamBase);
  } catch {
    return NextResponse.json({ detail: "Invalid path" }, { status: 400 });
  }
  if (
    target.origin !== upstreamBase.origin ||
    !target.pathname.startsWith("/api/v1/")
  ) {
    return NextResponse.json({ detail: "Invalid path" }, { status: 400 });
  }

  const upstreamUrl = target.href;

  const headers: HeadersInit = {
    Authorization: `Bearer ${accessToken}`,
    ...clientIpHeaders(request),
  };

  const contentType = request.headers.get("content-type") ?? "";
  // Multipart bodies (file uploads) must NOT be read as text — that corrupts the
  // binary bytes. Re-parse to FormData and let fetch regenerate a fresh boundary,
  // so we also must not forward the original multipart Content-Type header.
  const isMultipart = contentType.startsWith("multipart/form-data");
  if (contentType && !isMultipart) {
    headers["Content-Type"] = contentType;
  }

  const method = request.method;
  const hasBody = method === "POST" || method === "PATCH" || method === "PUT";

  let body: BodyInit | undefined;
  if (hasBody) {
    body = isMultipart ? await request.formData() : await request.text();
  }

  const upstreamRes = await fetchUpstream(upstreamUrl, { method, headers, body });
  if (upstreamRes === null) {
    // Marked, because the platform also answers 502 when THIS app is the one
    // not responding. The two are identical in devtools otherwise, and knowing
    // which end failed is the whole question when a request dies.
    return NextResponse.json(
      { detail: UPSTREAM_UNREACHABLE_DETAIL },
      { status: 502, headers: { [UPSTREAM_ERROR_HEADER]: "unreachable" } }
    );
  }

  // 204/205/304 are "null body status" codes: the Response constructor throws
  // `TypeError: Invalid response status code` if handed any body at all — an
  // empty string included. Every DELETE in the API and change-password return
  // 204, so forwarding them as text turned a successful call into a 500 while
  // the write had already committed.
  if (NULL_BODY_STATUSES.has(upstreamRes.status)) {
    return new NextResponse(null, { status: upstreamRes.status });
  }

  // An error whose body is not JSON did not come from the API — it is the
  // platform's own page, served when the service is asleep, suspended, or
  // restarting. Forwarded as-is it reaches the client as HTML it cannot read,
  // and every such failure surfaces as "An unexpected error occurred", which
  // names neither the cause nor the end it came from.
  const upstreamContentType = upstreamRes.headers.get("content-type") ?? "";
  if (!upstreamRes.ok && !upstreamContentType.includes("json")) {
    return NextResponse.json(
      {
        detail:
          `The API answered ${upstreamRes.status} without a message, which means ` +
          "the request never reached the application. It may be asleep, " +
          "restarting, or suspended.",
      },
      {
        status: upstreamRes.status,
        headers: { [UPSTREAM_ERROR_HEADER]: "platform-page" },
      }
    );
  }

  // Stream the body through rather than reading it as text. `text()` decodes
  // bytes as UTF-8, so every byte sequence that is not valid UTF-8 became a
  // replacement character — which inflated a 13KB quote PDF to 23KB and left a
  // file no reader would open. Streaming also avoids buffering a whole document
  // in memory on an instance that does not have much.
  const responseHeaders = new Headers({
    "Content-Type": upstreamRes.headers.get("content-type") ?? "application/json",
  });
  // Carried so a download keeps the filename the backend chose.
  const disposition = upstreamRes.headers.get("content-disposition");
  if (disposition) responseHeaders.set("Content-Disposition", disposition);
  // Carried so a throttled caller can wait the right amount of time. Dropping it
  // leaves "too many attempts" with no way to know how long too many lasts.
  const retryAfter = upstreamRes.headers.get("retry-after");
  if (retryAfter) responseHeaders.set("Retry-After", retryAfter);

  return new NextResponse(upstreamRes.body, {
    status: upstreamRes.status,
    headers: responseHeaders,
  });
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function PATCH(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function DELETE(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function PUT(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}
