# syntax=docker/dockerfile:1.7
# One image, two processes: `node dist/main.js` (API) and `node dist/worker.js` (BullMQ workers).

FROM node:22.12.0-alpine3.21 AS build
WORKDIR /app
RUN apk add --no-cache openssl
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY prisma ./prisma
RUN npx prisma generate
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npx nest build && npm prune --omit=dev

FROM node:22.12.0-alpine3.21 AS runtime
WORKDIR /app
# ffmpeg: video transcoding (worker). tini: correct signal handling for graceful shutdown.
RUN apk add --no-cache openssl ffmpeg tini
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY package.json ./
USER node
EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/main.js"]
