import { NextRequest, NextResponse } from "next/server";
import {
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

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const fastapiRes = await fetchUpstream(`${FASTAPI_URL}/api/v1/auth/reset-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...clientIpHeaders(request) },
      body: JSON.stringify(body),
    });
  if (fastapiRes === null) {
    return NextResponse.json(
      { detail: UPSTREAM_UNREACHABLE_DETAIL },
      { status: 502 }
    );
  }

  if (fastapiRes.status === 204) {
    return new NextResponse(null, { status: 204 });
  }

  const data = await fastapiRes.json().catch(() => ({ detail: "Reset failed" }));
  return NextResponse.json(data, { status: fastapiRes.status });
}
