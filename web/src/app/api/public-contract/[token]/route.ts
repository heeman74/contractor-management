import { NextRequest, NextResponse } from "next/server";
import {
  UPSTREAM_MAX_DURATION_SECONDS,
  UPSTREAM_UNREACHABLE_DETAIL,
  fetchUpstream,
} from "@/lib/server/upstream";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

// The upstream may be cold; allow the wait rather than dying on a default.
export const maxDuration = UPSTREAM_MAX_DURATION_SECONDS;

/**
 * Public, cookie-free proxy for the tokenized contract view.
 *
 * The magic-link token IS the capability — this endpoint forwards to
 * GET {FASTAPI}/api/v1/public/contracts/{token} WITHOUT the access_token cookie,
 * so the signing page works for a logged-out client. It deliberately does not
 * route through /api/proxy (which requires the authenticated cookie).
 */
export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ token: string }> }
): Promise<NextResponse> {
  const { token } = await params;

  if (!token) {
    return NextResponse.json({ detail: "Missing token" }, { status: 400 });
  }

  const upstream = await fetchUpstream(
    `${FASTAPI_URL}/api/v1/public/contracts/${encodeURIComponent(token)}`,
    { headers: { Accept: "application/json" }, cache: "no-store" }
  );
  if (upstream === null) {
    return NextResponse.json({ detail: UPSTREAM_UNREACHABLE_DETAIL }, { status: 502 });
  }

  const body = await upstream.text();
  return new NextResponse(body, {
    status: upstream.status,
    headers: {
      "Content-Type":
        upstream.headers.get("content-type") ?? "application/json",
    },
  });
}
