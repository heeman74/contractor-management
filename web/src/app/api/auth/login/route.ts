import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import type { TokenResponse, AuthUser } from "@/types/api";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

const IS_PROD = process.env.NODE_ENV === "production";

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  let fastapiRes: Response;
  try {
    fastapiRes = await fetch(`${FASTAPI_URL}/api/v1/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach authentication service" },
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
  };

  return NextResponse.json(userMeta, { status: 200 });
}
