import { NextRequest, NextResponse } from "next/server";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ detail: "Invalid JSON body" }, { status: 400 });
  }

  let fastapiRes: Response;
  try {
    fastapiRes = await fetch(`${FASTAPI_URL}/api/v1/auth/reset-password`, {
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

  if (fastapiRes.status === 204) {
    return new NextResponse(null, { status: 204 });
  }

  const data = await fastapiRes.json().catch(() => ({ detail: "Reset failed" }));
  return NextResponse.json(data, { status: fastapiRes.status });
}
