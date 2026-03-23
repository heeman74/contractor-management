import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

async function getAccessToken(): Promise<string | undefined> {
  const cookieStore = await cookies();
  return cookieStore.get("access_token")?.value;
}

/**
 * POST /api/ai-chat?path=/api/v1/ai/intake/message
 *
 * SSE streaming proxy — pipes ReadableStream directly without buffering.
 * CRITICAL: Do NOT call upstreamRes.text() — that buffers the stream.
 */
export async function POST(request: NextRequest): Promise<Response> {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    return NextResponse.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const path = searchParams.get("path");

  if (!path) {
    return NextResponse.json(
      { detail: "Missing path parameter" },
      { status: 400 }
    );
  }

  // SSRF prevention — only allow AI endpoints
  if (
    !path.startsWith("/api/v1/ai/") ||
    path.includes("://") ||
    path.includes("..")
  ) {
    return NextResponse.json({ detail: "Invalid path" }, { status: 400 });
  }

  const body = await request.text();

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(`${FASTAPI_URL}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body,
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach backend service" },
      { status: 502 }
    );
  }

  if (!upstreamRes.ok) {
    // Non-streaming error — safe to buffer
    const errorText = await upstreamRes.text();
    return new NextResponse(errorText, {
      status: upstreamRes.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Pipe ReadableStream directly — never buffer for SSE
  return new Response(upstreamRes.body, {
    status: upstreamRes.status,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}

/**
 * GET /api/ai-chat?path=/api/v1/ai/conversations/{id}
 *
 * Standard buffered proxy for non-streaming endpoints (conversation fetch).
 */
export async function GET(request: NextRequest): Promise<NextResponse> {
  const accessToken = await getAccessToken();

  if (!accessToken) {
    return NextResponse.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const path = searchParams.get("path");

  if (!path) {
    return NextResponse.json(
      { detail: "Missing path parameter" },
      { status: 400 }
    );
  }

  if (
    !path.startsWith("/api/v1/ai/") ||
    path.includes("://") ||
    path.includes("..")
  ) {
    return NextResponse.json({ detail: "Invalid path" }, { status: 400 });
  }

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(`${FASTAPI_URL}${path}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach backend service" },
      { status: 502 }
    );
  }

  const responseBody = await upstreamRes.text();
  return new NextResponse(responseBody, {
    status: upstreamRes.status,
    headers: {
      "Content-Type":
        upstreamRes.headers.get("content-type") ?? "application/json",
    },
  });
}
