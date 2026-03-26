#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if ! command -v bun >/dev/null 2>&1; then
  echo "bun is not installed or not in PATH" >&2
  exit 1
fi

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

export OAUTH_APP_DATA_DIR="${OAUTH_APP_DATA_DIR:-${ROOT_DIR}/data}"
export OAUTH_APP_WEB_DIR="${OAUTH_APP_WEB_DIR:-${ROOT_DIR}/src/web}"
export OAUTH_APP_HOST="${OAUTH_APP_HOST:-127.0.0.1}"
export OAUTH_APP_PORT="${OAUTH_APP_PORT:-4777}"

case "${OAUTH_APP_HOST}" in
  127.0.0.1|localhost|::1)
    ;;
  *)
    if [ -z "${OAUTH_APP_ENCRYPTION_KEY:-}" ]; then
      echo "OAUTH_APP_ENCRYPTION_KEY is required for non-loopback binding" >&2
      exit 1
    fi
    if [ -z "${OAUTH_APP_ADMIN_TOKEN:-}" ]; then
      echo "OAUTH_APP_ADMIN_TOKEN should be set for any non-loopback binding" >&2
      exit 1
    fi
    ;;
esac

mkdir -p "${OAUTH_APP_DATA_DIR}"
cd "${ROOT_DIR}"
exec bun src/index.ts
