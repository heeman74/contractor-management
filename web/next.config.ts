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
};

export default nextConfig;
