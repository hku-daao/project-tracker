# Use Docker instead of Railpack so secrets are NOT required at build time.
# Only env vars at runtime are needed (set in Railway Variables).

FROM node:20-bookworm-slim

WORKDIR /app

# Install dependencies only from package files (no secrets needed)
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev 2>/dev/null || npm install --production

# Copy application code
COPY . .

EXPOSE 3000

ENV NODE_ENV=production
ENV PORT=3000
ENV NODE_OPTIONS=--dns-result-order=ipv4first

CMD ["node", "server.js"]
