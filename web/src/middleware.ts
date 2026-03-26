import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

/**
 * Generate a UUID v4 for request tracing.
 * Uses crypto.randomUUID() which is available in Edge Runtime.
 */
function generateRequestId(): string {
  return crypto.randomUUID();
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Read or generate X-Request-ID for trace correlation
  const requestId =
    request.headers.get("x-request-id") ?? generateRequestId();

  // Allow auth pages, API routes, and static assets
  if (
    pathname.startsWith("/login") ||
    pathname.startsWith("/register") ||
    pathname.startsWith("/api/") ||
    pathname.startsWith("/_next/") ||
    pathname.includes(".")
  ) {
    const response = NextResponse.next();
    response.headers.set("X-Request-ID", requestId);
    return response;
  }

  // Check for access token cookie
  const token = request.cookies.get("access_token");
  if (!token) {
    const loginUrl = new URL("/login", request.url);
    const response = NextResponse.redirect(loginUrl);
    response.headers.set("X-Request-ID", requestId);
    return response;
  }

  // Log at info level — lightweight, non-blocking
  // Note: console.log in Edge middleware outputs to server stdout
  const method = request.method;
  const logEntry = JSON.stringify({
    timestamp: new Date().toISOString(),
    level: "info",
    tag: "Middleware",
    message: `${method} ${pathname}`,
    requestId,
  });
  console.log(logEntry);

  const response = NextResponse.next();
  response.headers.set("X-Request-ID", requestId);
  return response;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
