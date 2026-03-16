import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

async function handleProxy(request: NextRequest): Promise<NextResponse> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("access_token")?.value;

  if (!accessToken) {
    return NextResponse.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const path = searchParams.get("path");

  if (!path) {
    return NextResponse.json({ detail: "Missing path parameter" }, { status: 400 });
  }

  const upstreamUrl = `${FASTAPI_URL}${path}`;

  const headers: HeadersInit = {
    Authorization: `Bearer ${accessToken}`,
  };

  // Forward content-type if present (for POST/PATCH with JSON body)
  const contentType = request.headers.get("content-type");
  if (contentType) {
    headers["Content-Type"] = contentType;
  }

  const method = request.method;
  const hasBody = method === "POST" || method === "PATCH" || method === "PUT";

  let upstreamRes: Response;
  try {
    upstreamRes = await fetch(upstreamUrl, {
      method,
      headers,
      body: hasBody ? await request.text() : undefined,
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach backend service" },
      { status: 502 }
    );
  }

  // Forward FastAPI response (status + body) back to client
  const responseBody = await upstreamRes.text();
  return new NextResponse(responseBody, {
    status: upstreamRes.status,
    headers: {
      "Content-Type": upstreamRes.headers.get("content-type") ?? "application/json",
    },
  });
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function PATCH(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}

export async function DELETE(request: NextRequest): Promise<NextResponse> {
  return handleProxy(request);
}
