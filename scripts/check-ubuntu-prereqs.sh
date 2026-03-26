#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

FAILURES=0
WARNINGS=0

ok() {
  echo "[OK] $*"
}

warn() {
  echo "[WARN] $*"
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo "[FAIL] $*"
  FAILURES=$((FAILURES + 1))
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

is_loopback_host() {
  case "${1:-}" in
    127.0.0.1|localhost|::1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_env_file() {
  if [ ! -f "${ENV_FILE}" ]; then
    fail ".env not found at ${ENV_FILE}"
    return
  fi

  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
  ok "Loaded .env from ${ENV_FILE}"
}

check_bun() {
  if ! has_command bun; then
    fail "bun is not installed or not in PATH"
    return
  fi

  local version
  version="$(bun --version 2>/dev/null || true)"
  ok "bun detected${version:+: ${version}}"
}

check_port() {
  local host port listen_output
  host="${OAUTH_APP_HOST:-127.0.0.1}"
  port="${OAUTH_APP_PORT:-4777}"

  if ! [[ "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
    fail "OAUTH_APP_PORT is invalid: ${port}"
    return
  fi

  if has_command ss; then
    listen_output="$(ss -ltn 2>/dev/null | awk -v port="${port}" 'NR > 1 && $4 ~ (":" port "$") { print $4 }' || true)"
  elif has_command lsof; then
    listen_output="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  elif has_command netstat; then
    listen_output="$(netstat -ltn 2>/dev/null | awk -v port="${port}" 'NR > 2 && $4 ~ (":" port "$") { print $4 }' || true)"
  else
    warn "No ss/lsof/netstat found; skipped port occupancy check for ${host}:${port}"
    return
  fi

  if [ -n "${listen_output}" ]; then
    fail "Port ${port} appears to be occupied"
  else
    ok "Port ${port} appears available"
  fi
}

check_bind_requirements() {
  local host
  host="${OAUTH_APP_HOST:-127.0.0.1}"

  if is_loopback_host "${host}"; then
    ok "Loopback bind host detected: ${host}"
    return
  fi

  ok "Non-loopback bind host detected: ${host}"

  if [ -z "${OAUTH_APP_ENCRYPTION_KEY:-}" ]; then
    fail "OAUTH_APP_ENCRYPTION_KEY is required for non-loopback binding"
  else
    ok "OAUTH_APP_ENCRYPTION_KEY is set"
  fi

  if [ -z "${OAUTH_APP_ADMIN_TOKEN:-}" ]; then
    fail "OAUTH_APP_ADMIN_TOKEN should be set for non-loopback binding"
  else
    ok "OAUTH_APP_ADMIN_TOKEN is set"
  fi
}

check_data_dir() {
  local data_dir probe_file
  data_dir="${OAUTH_APP_DATA_DIR:-${ROOT_DIR}/data}"

  if ! mkdir -p "${data_dir}" 2>/dev/null; then
    fail "Cannot create data directory: ${data_dir}"
    return
  fi

  if [ ! -d "${data_dir}" ]; then
    fail "Data directory is not a directory: ${data_dir}"
    return
  fi

  probe_file="${data_dir}/.codex_gateway_write_test.$$"
  if ! : > "${probe_file}" 2>/dev/null; then
    fail "Data directory is not writable: ${data_dir}"
    return
  fi

  rm -f "${probe_file}" >/dev/null 2>&1 || true
  ok "Data directory is writable: ${data_dir}"
}

main() {
  echo "Codex Gateway Ubuntu preflight"
  echo "Bundle root: ${ROOT_DIR}"

  load_env_file
  check_bun
  check_port
  check_bind_requirements
  check_data_dir

  echo ""
  if [ "${FAILURES}" -gt 0 ]; then
    echo "Preflight finished with ${FAILURES} failure(s) and ${WARNINGS} warning(s)."
    exit 1
  fi

  if [ "${WARNINGS}" -gt 0 ]; then
    echo "Preflight finished with ${WARNINGS} warning(s)."
    exit 0
  fi

  echo "Preflight passed."
}

main "$@"
