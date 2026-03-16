import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import type { TokenResponse, AuthUser } from "@/types/api";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

const IS_PROD = process.env.NODE_ENV === "production";

export async function POST(): Promise<NextResponse> {
  const cookieStore = await cookies();
  const refreshToken = cookieStore.get("refresh_token")?.value;

  if (!refreshToken) {
    return NextResponse.json({ detail: "No refresh token" }, { status: 401 });
  }

  let fastapiRes: Response;
  try {
    fastapiRes = await fetch(`${FASTAPI_URL}/api/v1/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
  } catch {
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
    maxAge: 2592000, // 30 days
  });

  const userMeta: AuthUser = {
    user_id: tokenData.user_id,
    company_id: tokenData.company_id,
    roles: tokenData.roles,
  };

  return NextResponse.json(userMeta, { status: 200 });
}
