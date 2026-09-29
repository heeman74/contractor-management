import { NextRequest, NextResponse } from "next/server";
import {
  UPSTREAM_UNREACHABLE_DETAIL,
  fetchUpstream,
} from "@/lib/server/upstream";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

// Next reads route segment config statically, so this must be a literal —
// referencing an imported constant fails the build with "Invalid segment
// configuration export". Keep in step with UPSTREAM_TIMEOUT_MS in
// lib/server/upstream.ts, which allows one retry inside this budget.
export const maxDuration = 90;

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
