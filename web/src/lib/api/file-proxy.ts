import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

/**
 * Server-side proxy for authenticated file downloads.
 *
 * Uploaded files used to be served by a public rewrite straight to FastAPI's
 * (unauthenticated) StaticFiles mount. FastAPI now requires a token and enforces
 * tenant/thread ownership, so a plain <img src="/files/..."> would 401. The browser
 * automatically sends the httpOnly access_token cookie to these same-origin routes;
 * we read it here (never exposed to client JS) and forward it as a Bearer header,
 * then stream the backend response straight through — no buffering.
 *
 * `prefix` is the backend mount ("/files" or "/uploads/chat"); `segments` are the
 * catch-all route params. The backend independently validates auth + path safety,
 * so this never needs to trust the path.
 */
export async function proxyFile(
  request: NextRequest,
  prefix: string,
  segments: string[]
): Promise<NextResponse> {
  const accessToken = (await cookies()).get("access_token")?.value;
  if (!accessToken) {
    return NextResponse.json({ detail: "Not authenticated" }, { status: 401 });
  }

  const path = segments.map(encodeURIComponent).join("/");
  const search = request.nextUrl.search;
  const upstreamUrl = `${FASTAPI_URL}${prefix}/${path}${search}`;

  let upstream: Response;
  try {
    upstream = await fetch(upstreamUrl, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch {
    return NextResponse.json(
      { detail: "Unable to reach file service" },
      { status: 502 }
    );
  }

  // Stream the body through, preserving the content-type/length/disposition the
  // backend set. Do NOT forward Set-Cookie or other sensitive upstream headers.
  const headers = new Headers();
  for (const h of ["content-type", "content-length", "content-disposition", "cache-control"]) {
    const v = upstream.headers.get(h);
    if (v) headers.set(h, v);
  }
  headers.set("X-Content-Type-Options", "nosniff");

  return new NextResponse(upstream.body, {
    status: upstream.status,
    headers,
  });
}
