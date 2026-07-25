import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

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

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(upstreamUrl, {
      method,
      headers,
      body,
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach backend service" },
      { status: 502 }
    );
  }

  // Forward FastAPI response (status + body) back to client
  const responseBody = await upstreamRes.text();
  return new NextResponse(responseBody, {
    status: upstreamRes.status,
    headers: {
      "Content-Type": upstreamRes.headers.get("content-type") ?? "application/json",
    },
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
