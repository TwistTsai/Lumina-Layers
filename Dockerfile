# syntax=docker/dockerfile:1.7
# Lumina Layers v2.0.1 — 非官方容器化
#
# 关键约束：frontend/src/i18n/translations.ts 硬依赖仓库根的 electron/splash-text.json，
# 所以构建上下文必须包含 electron，且构建阶段要整仓 COPY 后用 pnpm --dir frontend build。
# 前端请求全部走 /api 前缀，由 nginx 反代到容器内 8000；vite.config.ts 没有 preview.proxy，
# 用 preview 或纯静态服务都会 404。

# ---------- 阶段一：构建前端静态产物 ----------
FROM node:24-bookworm-slim AS frontend

WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate

COPY . .
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm --dir frontend install --frozen-lockfile \
 && pnpm --dir frontend build

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

# 先只有依赖清单，改代码不会重装 Python 包
COPY requirements.txt ./
RUN python -m pip install --upgrade pip \
 && python -m pip install -r requirements.txt

COPY . .
COPY --from=frontend /src/frontend/dist /app/frontend/dist
COPY deploy/nginx.conf /etc/nginx/conf.d/lumina.conf

EXPOSE 4174

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["sh","-c","python api_server.py & nginx -g 'daemon off;'"]
