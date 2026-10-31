# syntax=docker/dockerfile:1.7
# Lumina Layers v2.0.1 — 非官方容器化
# 说明：官方不提供 Docker 支持，此文件自行构建。
# 前端必须用 nginx 反代 /api，因为 vite.config.ts 只配了 server.proxy，
# preview 与静态产物都不会转发请求。

# ---------- 阶段一：构建前端静态产物 ----------
FROM node:24-bookworm-slim AS frontend

WORKDIR /src/frontend
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY frontend/package.json frontend/pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY frontend/ ./
RUN pnpm build

# ---------- 阶段二：运行时 ----------
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    LUMINA_API_HOST=0.0.0.0 \
    LUMINA_API_PORT=8000

RUN apt-get update && apt-get install -y --no-install-recommends \
      nginx tini curl ca-certificates \
      libgl1 libglib2.0-0 libgomp1 \
      fontconfig fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

WORKDIR /app

COPY requirements.txt ./
RUN python -m pip install --upgrade pip \
 && python -m pip install -r requirements.txt

COPY . .
COPY --from=frontend /src/frontend/dist /app/frontend/dist
COPY deploy/nginx.conf /etc/nginx/conf.d/lumina.conf

EXPOSE 4174

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["sh","-c","python api_server.py & nginx -g 'daemon off;'"]
