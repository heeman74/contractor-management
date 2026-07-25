import type { NextConfig } from "next";

// Pin the workspace root to this directory. Without this, Next infers the root by
// walking up for lockfiles and can latch onto a stray one outside the project
// (e.g. ~/package-lock.json), which breaks module resolution — Turbopack fails to
// resolve `tailwindcss` from `globals.css`. Keeping it explicit makes dev, build,
// standalone output, and CI resolve from `web/` regardless of the machine.
const projectRoot = import.meta.dirname;


const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingRoot: projectRoot,
  turbopack: {
    root: projectRoot,
  },
  // NOTE: the previous public /files/* rewrite to FastAPI's StaticFiles mount was
  // removed — uploaded files are now served through authenticated route handlers
  // (src/app/files/[...path]/route.ts and src/app/uploads/chat/[...path]/route.ts)
  // that forward the httpOnly access_token cookie as a Bearer token.
  //
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
