import type { NextConfig } from "next";

// Pin the workspace root to this directory. Without this, Next infers the root by
// walking up for lockfiles and can latch onto a stray one outside the project
// (e.g. ~/package-lock.json), which breaks module resolution — Turbopack fails to
// resolve `tailwindcss` from `globals.css`. Keeping it explicit makes dev, build,
// standalone output, and CI resolve from `web/` regardless of the machine.
const projectRoot = import.meta.dirname;

const FASTAPI_URL = process.env.FASTAPI_URL ?? "http://localhost:8000";

const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingRoot: projectRoot,
  turbopack: {
    root: projectRoot,
  },
  // Serve uploaded files (job-note attachments, task photos, images) from FastAPI's
  // /files StaticFiles mount. Attachment remote_url values are "/files/..." — without
  // this rewrite they would resolve to the web origin and 404.
  async rewrites() {
    return [
      {
        source: "/files/:path*",
        destination: `${FASTAPI_URL}/files/:path*`,
      },
    ];
  },
  // Baseline security response headers. Deliberately conservative CSP directives
  // (frame-ancestors/object-src/base-uri) that harden clickjacking + base-tag and
  // data-exfil vectors without constraining script-src (which would risk breaking
  // Next's inline bootstrap/hydration). XSS itself is fixed at the source via
  // DOMPurify on the one dangerouslySetInnerHTML sink.
  async headers() {
    const isProd = process.env.NODE_ENV === "production";
    const securityHeaders = [
      { key: "X-Frame-Options", value: "DENY" },
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
      {
        key: "Content-Security-Policy",
        value: "frame-ancestors 'none'; object-src 'none'; base-uri 'self'",
      },
      ...(isProd
        ? [
            {
              key: "Strict-Transport-Security",
              value: "max-age=31536000; includeSubDomains",
            },
          ]
        : []),
    ];
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
