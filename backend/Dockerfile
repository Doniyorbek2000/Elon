# syntax=docker/dockerfile:1
# Build on the full image (ships OpenSSL for Prisma); run on slim with only
# the OpenSSL runtime libraries copied over — no package manager access needed.
FROM node:22-bookworm AS build
WORKDIR /app
ENV PRISMA_HIDE_UPDATE_MESSAGE=1
COPY package.json package-lock.json ./
# Optional build secret `ca` for TLS-intercepting corporate proxies.
RUN --mount=type=secret,id=ca,required=false \
  if [ -f /run/secrets/ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/ca; fi; npm ci --no-audit --no-fund
COPY prisma ./prisma
RUN --mount=type=secret,id=ca,required=false \
  if [ -f /run/secrets/ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/ca; fi; npx prisma generate
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev \
  && mkdir -p /opt/ssl && cp -L /usr/lib/$(uname -m)-linux-gnu/libssl.so.3 /usr/lib/$(uname -m)-linux-gnu/libcrypto.so.3 /opt/ssl/

FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production PRISMA_HIDE_UPDATE_MESSAGE=1
COPY --from=build /opt/ssl/ /usr/local/lib/
RUN ldconfig
COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/prisma ./prisma
USER node
EXPOSE 3000
CMD ["node", "dist/src/main.js"]
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/api/v1/health/live').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
