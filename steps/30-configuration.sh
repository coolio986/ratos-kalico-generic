# 30 — RatOS configuration install (macros, hooks, klippy extensions, printer defs)
# (sourced by install.sh) — requires the configurator up (step 20) so
# `ratos extensions register` works.
#
# NOTE (v2.1.x): config/RatOS is a SYMLINK to the configurator's bundled configuration/,
# created by setup.sh in step 20. We do NOT clone RatOS-configuration here.

RATOS_CFG_DIR="${RK_CONFIG}/RatOS"
INSTALL="${RATOS_CFG_DIR}/scripts/ratos-install.sh"
[[ -e "${INSTALL}" ]] || die "config/RatOS not linked (missing ${INSTALL}). Did step 20 run setup.sh? Layout should be: ${RATOS_CFG_DIR} -> ${RK_CONFIGURATOR_DIR}/configuration"
ok "config/RatOS present -> $(readlink -f "${RATOS_CFG_DIR}" 2>/dev/null || echo "${RATOS_CFG_DIR}")"

# Theme (cosmetic mainsail skin) — separate repo, optional.
git_ensure "${RK_THEME_REPO}" "${RK_CONFIG}/.theme" "${RK_THEME_BRANCH}" || warn "theme clone failed (non-fatal)"

# ratos-install.sh will (see configuration/scripts/ratos-common.sh):
#   - write a fresh printer.cfg from templates/initial-printer.template.cfg
#   - symlink board udev rules
#   - install beacon, git hooks, python deps
#   - register klippy extensions via the `ratos` CLI (needs configurator up)
# Workaround: the bundled (deployment) ratos-install.sh reads the printer template from
# "$SCRIPT_DIR/templates" (scripts/templates) but templates live at the repo root.
# Add a compatibility symlink so install_printer_config resolves. (Proper fix: fork.)
REAL_RATOS="$(readlink -f "${RATOS_CFG_DIR}")"
if [[ -d "${REAL_RATOS}/templates" && ! -e "${REAL_RATOS}/scripts/templates" ]]; then
  as_user "ln -s ../templates '${REAL_RATOS}/scripts/templates'"
  ok "added scripts/templates -> ../templates compat symlink"
fi

report "Running ratos-install.sh (registers extensions, udev, beacon, hooks)"
if [[ -f "${RK_CONFIG}/printer.cfg" ]] && [[ ! -f "${RK_CONFIG}/printer.cfg.pre-ratos" ]]; then
  warn "existing printer.cfg found — backing up to printer.cfg.pre-ratos"
  as_user "cp '${RK_CONFIG}/printer.cfg' '${RK_CONFIG}/printer.cfg.pre-ratos'"
fi
as_user "bash '${INSTALL}'" || die "ratos-install.sh failed — is the configurator running? (./install.sh 20)"
ok "RatOS configuration installed"

# Extensions are only REGISTERED by ratos-install.sh; they must also be SYMLINKED into
# klipper's klippy/extras + klippy/kinematics so klipper can load them.
report "Materializing registered klippy extensions into klipper (ratos extensions symlink)"
as_user "ratos extensions symlink" || warn "ratos extensions symlink failed — run manually: ratos extensions symlink"
ok "extensions symlinked into klipper"

# The bundled install_udev_rules has a CFG_DIR bug: it creates a single broken symlink
# literally named '*.rules' (unexpanded glob) instead of per-board rules, so /dev/RatOS/*
# and /dev/<board> never appear (breaks flashing + MCU serial paths). Install them right.
report "Installing board udev rules (fixes bundled install_udev_rules bug)"
sudo rm -f "/etc/udev/rules.d/*.rules"
BOARDS_DIR="$(readlink -f "${RATOS_CFG_DIR}")/boards"
if [[ -d "${BOARDS_DIR}" ]]; then
  for f in "${BOARDS_DIR}"/*/*.rules; do [[ -e "${f}" ]] && sudo ln -sf "${f}" /etc/udev/rules.d/; done
  sudo udevadm control --reload-rules && sudo udevadm trigger --action=add --subsystem-match=tty || true
  ok "board udev rules installed + triggered (/dev/RatOS/* symlinks)"
else
  warn "boards dir not found at ${BOARDS_DIR}"
fi

warn "printer.cfg is now the RatOS TEMPLATE. Your real V-Core 4 IDEX config (from 'Current Configuration/') gets restored in a later step / manually."
