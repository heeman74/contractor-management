import { NextRequest, NextResponse } from "next/server";

/**
 * Next.js 16 proxy.ts route guard (runs at the edge before any route handler).
 *
 * IMPORTANT: This does NOT validate the JWT signature — it only checks for cookie
 * existence. This is an optimistic guard for fast redirects. Real token validation
 * happens when Route Handlers or Server Components call the FastAPI backend.
 *
 * Public routes bypass the guard. All other routes require the access_token cookie.
 * On missing cookie: redirect to /login (no redirectTo param — always goes to dashboard home).
 */

const PUBLIC_ROUTES = ["/login", "/api/auth/login", "/api/auth/refresh"];

export default function proxy(request: NextRequest): NextResponse {
  const { pathname } = request.nextUrl;

  // Allow public routes, Next.js internals, and static files
  if (
    PUBLIC_ROUTES.some((route) => pathname === route || pathname.startsWith(route + "/")) ||
    pathname.startsWith("/_next/") ||
    pathname === "/favicon.ico"
  ) {
    return NextResponse.next();
  }

  // Check for access_token cookie existence (optimistic guard)
  if (!request.cookies.has("access_token")) {
    const loginUrl = new URL("/login", request.url);
    return NextResponse.redirect(loginUrl);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
