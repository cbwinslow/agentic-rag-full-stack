# Multi-stage build for production
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN npm install -g pnpm && \
    pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM node:20-alpine AS production
WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json .
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 3000
CMD ["pnpm","start"]

# Development image with hot reloading
FROM node:20-alpine AS development
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN npm install -g pnpm && \
    pnpm install --frozen-lockfile
COPY . .
CMD ["pnpm","dev"]
