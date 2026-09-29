# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production=false

# Stage 2: Build the application
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
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
