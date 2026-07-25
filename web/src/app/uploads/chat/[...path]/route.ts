import { NextRequest } from "next/server";
import { proxyFile } from "@/lib/api/file-proxy";

// Authenticated proxy for chat attachments. FastAPI enforces thread membership
// on top of authentication, so a non-member (even in the same company) gets 403.
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ path: string[] }> }
) {
  const { path } = await params;
  return proxyFile(request, "/uploads/chat", path);
}
