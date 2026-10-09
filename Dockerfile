# The web app, built from the repository root.
#
# It exists because a service is configured with the repository root as its
# build context, and four deploys failed on
#
#     failed to read dockerfile: open Dockerfile: no such file or directory
#
# The proper fix is that service's Build & Deploy settings — one of:
#
#     Root Directory | Dockerfile Path      | Build Context
#     ---------------+----------------------+--------------
#     (blank)        | ./web/Dockerfile     | ./web
#     web            | ./Dockerfile         | .
#
# until which this file keeps the web app shipping. It is the same build as
# web/Dockerfile with the paths rebased, and the two must not drift: a test
# compares their stages.
#
# Why the web app and not the API: the deployed web UI is several commits
# behind while the API is current, so the root-pointed service is the web one.
# If that is ever wrong, the API's health check (/health) fails against a web
# image and the platform keeps the running version rather than serving it.

# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci --production=false

# Stage 2: Build the application
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY web/ ./
RUN npm run build

# Stage 3: Production runtime
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
USER nextjs
EXPOSE 3000

# Next's standalone server binds `process.env.HOSTNAME || "0.0.0.0"`. Container
# runtimes set HOSTNAME to the instance name (Render uses srv-xxxxxxxx), which
# does not resolve, so the server dies on boot with getaddrinfo ENOTFOUND and
# never opens a port. Forcing it here overrides whatever the platform injects.
CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]
