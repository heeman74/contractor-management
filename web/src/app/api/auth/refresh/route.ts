import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import type { TokenResponse, AuthUser } from "@/types/api";
import { clientIpHeaders, fetchUpstream } from "@/lib/server/upstream";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

// Next reads route segment config statically, so this must be a literal —
// referencing an imported constant fails the build with "Invalid segment
// configuration export". Keep in step with UPSTREAM_TIMEOUT_MS in
// lib/server/upstream.ts, which allows one retry inside this budget.
export const maxDuration = 90;

const IS_PROD = process.env.NODE_ENV === "production";

export async function POST(request: Request): Promise<NextResponse> {
  const cookieStore = await cookies();
  const refreshToken = cookieStore.get("refresh_token")?.value;

  if (!refreshToken) {
    return NextResponse.json({ detail: "No refresh token" }, { status: 401 });
  }

  // Retried with a stated timeout because this route ENDS THE SESSION on
  // failure. A cold upstream — ~62s on a free instance — would otherwise be
  // indistinguishable from a revoked token and would sign the user out for
  // nothing. The focus-triggered session watchdog calls this path, so a cold
  // start on tab focus was a spurious logout waiting to happen.
  const fastapiRes = await fetchUpstream(`${FASTAPI_URL}/api/v1/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...clientIpHeaders(request) },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (fastapiRes === null) {
    // Clear cookies on network error — force re-login
    cookieStore.set("access_token", "", { httpOnly: true, secure: IS_PROD, sameSite: "lax", path: "/", maxAge: 0 });
    cookieStore.set("refresh_token", "", { httpOnly: true, secure: IS_PROD, sameSite: "lax", path: "/api/auth/refresh", maxAge: 0 });
    return NextResponse.json({ detail: "Unable to reach authentication service" }, { status: 401 });
  }

  if (!fastapiRes.ok) {
    // Clear cookies on refresh failure — force re-login
    cookieStore.set("access_token", "", { httpOnly: true, secure: IS_PROD, sameSite: "lax", path: "/", maxAge: 0 });
    cookieStore.set("refresh_token", "", { httpOnly: true, secure: IS_PROD, sameSite: "lax", path: "/api/auth/refresh", maxAge: 0 });
    return NextResponse.json({ detail: "Session expired" }, { status: 401 });
  }

  const tokenData = (await fastapiRes.json()) as TokenResponse;

  // Rotate both cookies
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
    maxAge: 5184000, // 60 days
  });

  const userMeta: AuthUser = {
    user_id: tokenData.user_id,
    company_id: tokenData.company_id,
    roles: tokenData.roles,
  };

  return NextResponse.json(userMeta, { status: 200 });
}
