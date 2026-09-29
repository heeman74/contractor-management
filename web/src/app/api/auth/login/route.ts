import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import type { TokenResponse, AuthUser } from "@/types/api";
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

const IS_PROD = process.env.NODE_ENV === "production";

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  const fastapiRes = await fetchUpstream(`${FASTAPI_URL}/api/v1/auth/login`, {
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

  if (!fastapiRes.ok) {
    const errorBody = await fastapiRes.json().catch(() => ({ detail: "Login failed" }));
    return NextResponse.json(errorBody, { status: fastapiRes.status });
  }

  const tokenData = (await fastapiRes.json()) as TokenResponse;

  const cookieStore = await cookies();

  cookieStore.set("access_token", tokenData.access_token, {
    httpOnly: true,
    secure: IS_PROD,
    sameSite: "lax",
    path: "/",
    maxAge: 900, // 15 minutes
  });

  cookieStore.set("refresh_token", tokenData.refresh_token, {
    httpOnly: true,
    secure: IS_PROD,
    sameSite: "lax",
    path: "/api/auth/refresh",
    maxAge: 2592000, // 30 days
  });

  // Return only user metadata — NEVER return tokens to client
  const userMeta: AuthUser = {
    user_id: tokenData.user_id,
    company_id: tokenData.company_id,
    roles: tokenData.roles,
    email: tokenData.email,
    display_name: tokenData.display_name,
    company_name: tokenData.company_name,
  };

  return NextResponse.json(userMeta, { status: 200 });
}
