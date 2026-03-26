#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}"
APP_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
APP_USER="${APP_USER:-codex-gateway}"
APP_GROUP="${APP_GROUP:-${APP_USER}}"
RUN_PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_command sudo
need_command bun

if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  sudo useradd --system --create-home --home-dir "${APP_ROOT}" --shell /usr/sbin/nologin "${APP_USER}"
fi

sudo mkdir -p "${APP_ROOT}"
sudo chown -R "${APP_USER}:${APP_GROUP}" "${APP_ROOT}"

sudo -u "${APP_USER}" env PATH="${RUN_PATH}" bash -lc "
  set -euo pipefail
  cd '${APP_DIR}'
  if [ ! -f .env ]; then
    cp .env.example .env
  fi
  chmod +x start.sh scripts/check-ubuntu-prereqs.sh
  bun install --production
"

cat <<EOF
Repository prepared at: ${APP_DIR}

Next steps:
1. Edit ${APP_DIR}/.env
2. Run ${APP_DIR}/scripts/check-ubuntu-prereqs.sh
3. Run ${APP_DIR}/start.sh
4. Install systemd/codex-gateway.service and enable the service
EOF
