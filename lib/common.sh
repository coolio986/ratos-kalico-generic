#!/usr/bin/env bash
# Shared helpers. Sourced by install.sh and every step.

set -Eeuo pipefail

RK_GREEN='\033[0;32m'; RK_RED='\033[0;31m'; RK_YELLOW='\033[1;33m'; RK_BLUE='\033[0;34m'; RK_NC='\033[0m'

report()  { echo -e "\n${RK_BLUE}###### $*${RK_NC}"; }
ok()      { echo -e "${RK_GREEN}  ok: $*${RK_NC}"; }
warn()    { echo -e "${RK_YELLOW}  warn: $*${RK_NC}"; }
die()     { echo -e "${RK_RED}  ERROR: $*${RK_NC}" >&2; exit 1; }

# Run as the target user (never as root) when the script itself runs under sudo/root.
as_user() {
  if [[ "$(id -un)" == "${RK_USER}" ]]; then
    bash -lc "$*"
  else
    sudo -u "${RK_USER}" -H bash -lc "$*"
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found"; }

# Idempotent git clone: clone if absent, otherwise fetch+checkout the branch.
git_ensure() {
  local repo="$1" dir="$2" branch="$3"
  if [[ -d "${dir}/.git" ]]; then
    report "Updating $(basename "$dir") (${branch})"
    as_user "cd '${dir}' && git fetch --depth 1 origin '${branch}' && git checkout '${branch}' && git reset --hard 'origin/${branch}'"
  else
    report "Cloning $(basename "$dir") (${branch})"
    as_user "git clone --depth 1 -b '${branch}' '${repo}' '${dir}'"
  fi
}

require_not_root() {
  [[ "$(id -un)" == "${RK_USER}" ]] || warn "running as $(id -un); target user is ${RK_USER}. Steps use sudo -u ${RK_USER} where needed."
}

# Wait until the configurator answers on its port (returns 404 for unknown paths when up).
wait_for_configurator() {
  local url="http://localhost:${RK_CONFIGURATOR_PORT}"
  report "Waiting for configurator on ${url}"
  local i
  for i in $(seq 1 60); do
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
    if [[ "${code}" == "404" || "${code}" == "200" || "${code}" == "307" ]]; then
      ok "configurator responding (HTTP ${code})"; return 0
    fi
    sleep 5
  done
  die "configurator did not come up on ${url} — check: sudo journalctl -u ratos-configurator -n 100"
}
