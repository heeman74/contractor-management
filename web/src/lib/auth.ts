import "server-only";
import { cookies } from "next/headers";
import { decodeJwt } from "jose";
import type { AuthUser } from "@/types/api";

/**
 * Server-side utility to extract the authenticated user from the httpOnly access_token cookie.
 *
 * Uses jose.decodeJwt() for decode-only (no signature verification) — FastAPI verifies the
 * token on every API request. This is intentional: the server component just needs user
 * metadata for conditional rendering without an extra round-trip.
 *
 * Returns null if no cookie is present or if the token payload is malformed.
 *
 * Usage: call from Server Components only (this file is marked server-only).
 */
export async function getServerUser(): Promise<AuthUser | null> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("access_token")?.value;

  if (!accessToken) {
    return null;
  }

  try {
    const payload = decodeJwt(accessToken);

    const userId = payload.sub;
    const companyId = payload.company_id;
    const roles = payload.roles;

    if (
      typeof userId !== "string" ||
      typeof companyId !== "string" ||
      !Array.isArray(roles)
    ) {
      return null;
    }

    return {
      user_id: userId,
      company_id: companyId,
      roles: roles as string[],
    };
  } catch {
    // Malformed token — treat as unauthenticated
    return null;
  }
}
