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
};

export default nextConfig;
