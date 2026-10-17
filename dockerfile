# syntax=docker/dockerfile:1.7
FROM node:lts AS builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential python3 git && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g typescript@5.7.3 --force

# ---- API deps (cached unless package*.json or the prisma schema changes) ----
COPY apps/api/package*.json ./apps/api/
COPY apps/api/src/prisma ./apps/api/src/prisma
RUN --mount=type=cache,target=/root/.npm \
    cd apps/api && \
    npm install && \
    npm install --no-save @types/node

# ---- Client deps (cached unless package.json/yarn.lock changes) ----
COPY apps/client/package.json apps/client/yarn.lock* ./apps/client/
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    cd apps/client && \
    yarn install --ignore-scripts --network-timeout 1000000 && \
    yarn add --dev typescript@5.7.3 @types/node --network-timeout 1000000

# ---- Now copy source and build ----
COPY ecosystem.config.js ./ecosystem.config.js
COPY apps/api ./apps/api
COPY apps/client ./apps/client

RUN cd apps/api && npm run build && npm prune --omit=dev
RUN cd apps/client && yarn build


FROM node:lts AS runner

WORKDIR /app

COPY --from=builder /app/apps/api/ ./apps/api/
COPY --from=builder /app/apps/client/.next/standalone ./apps/client/
COPY --from=builder /app/apps/client/.next/static ./apps/client/.next/static
COPY --from=builder /app/apps/client/public ./apps/client/public
COPY --from=builder /app/ecosystem.config.js ./ecosystem.config.js

EXPOSE 3000 5003

RUN npm install -g pm2

CMD ["pm2-runtime", "ecosystem.config.js"]