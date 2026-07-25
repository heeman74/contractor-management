import { NextRequest } from "next/server";
import { proxyFile } from "@/lib/api/file-proxy";

// Authenticated proxy for uploaded files (job-note attachments, task photos,
// images). Replaces the old public /files/* rewrite so FastAPI's now-authenticated
// file endpoint receives the caller's token from the httpOnly cookie.
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyFile(request, "/files", path);
}
