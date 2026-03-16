import { NextResponse } from "next/server";
import { cookies } from "next/headers";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

const IS_PROD = process.env.NODE_ENV === "production";

export async function POST(): Promise<NextResponse> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("access_token")?.value;

  if (accessToken) {
    try {
      await fetch(`${FASTAPI_URL}/api/v1/auth/logout`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}` },
      });
    } catch {
      // Best-effort — always clear cookies regardless of FastAPI response
    }
  }

  // Always clear both cookies — even if FastAPI call failed
  cookieStore.set("access_token", "", {
    httpOnly: true,
    secure: IS_PROD,
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });

  cookieStore.set("refresh_token", "", {
    httpOnly: true,
    secure: IS_PROD,
    sameSite: "lax",
    path: "/api/auth/refresh",
    maxAge: 0,
  });

  return NextResponse.json({ ok: true }, { status: 200 });
}
