#!/usr/bin/env bash
# ratos-kalico-generic — orchestrator
# Layers RatOS (configuration + configurator + extras) onto a stock Raspberry Pi OS
# box that already has a KIAUH-installed base (Kalico + Moonraker + Mainsail).
#
# Usage:
#   ./install.sh              # run all steps in order
#   ./install.sh 20 30        # run only the named step prefixes
#   RK_GH_OWNER=me ./install.sh
set -Eeuo pipefail

RK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${RK_ROOT}/config.env"
# shellcheck source=./lib/common.sh
source "${RK_ROOT}/lib/common.sh"

require_not_root

STEPS=(
  "00-system-prep.sh"
  "10-base-check.sh"
  "20-configurator.sh"
  "30-configuration.sh"
  "35-host-mcu.sh"
  "36-kalico-compat.sh"
  "40-nginx-proxy.sh"
  "50-moonraker-wire.sh"
  "60-extras.sh"
  "70-servos.sh"
  "80-register-extensions.sh"
  "90-finalize.sh"
)

filter=("$@")
run_step() {
  local f="$1"
  if [[ ${#filter[@]} -gt 0 ]]; then
    local keep=0 pat
    for pat in "${filter[@]}"; do [[ "$f" == "$pat"* ]] && keep=1; done
    [[ $keep -eq 1 ]] || return 0
  fi
  report "=== STEP $f ==="
  # shellcheck source=/dev/null
  source "${RK_ROOT}/steps/$f"
}

for s in "${STEPS[@]}"; do run_step "$s"; done

report "All requested steps complete."
echo -e "${RK_GREEN}Open http://<printer-ip>/  (Mainsail) and http://<printer-ip>/configure/  (RatOS Configurator).${RK_NC}"
