import { NextRequest, NextResponse } from "next/server";
import {
  UPSTREAM_MAX_DURATION_SECONDS,
  UPSTREAM_UNREACHABLE_DETAIL,
  fetchUpstream,
} from "@/lib/server/upstream";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

// The upstream may be cold; allow the wait rather than dying on a default.
export const maxDuration = UPSTREAM_MAX_DURATION_SECONDS;

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const fastapiRes = await fetchUpstream(`${FASTAPI_URL}/api/v1/auth/reset-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
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
