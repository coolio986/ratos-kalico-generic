# 30 — RatOS configuration repo (macros, hooks, klippy extensions, printer defs)
# (sourced by install.sh) — requires the configurator to be up (step 20) so
# `ratos extensions register` works.

as_user "mkdir -p '${RK_CONFIG}'"

git_ensure "${RK_CONFIGURATION_REPO}" "${RK_CONFIG}/RatOS" "${RK_CONFIGURATION_BRANCH}"
git_ensure "${RK_THEME_REPO}"        "${RK_CONFIG}/.theme" "${RK_THEME_BRANCH}"

INSTALL="${RK_CONFIG}/RatOS/scripts/ratos-install.sh"
[[ -f "${INSTALL}" ]] || die "ratos-install.sh not found at ${INSTALL}"

# ratos-install.sh will (see scripts/ratos-common.sh):
#   - write a fresh printer.cfg from templates/initial-printer.template.cfg
#   - symlink board udev rules
#   - install beacon, git hooks, python deps
#   - register klippy extensions via the `ratos` CLI (needs configurator up)
report "Running ratos-install.sh (registers extensions, udev, beacon, hooks)"
if [[ -f "${RK_CONFIG}/printer.cfg" ]]; then
  warn "existing printer.cfg found — backing up to printer.cfg.pre-ratos"
  as_user "cp '${RK_CONFIG}/printer.cfg' '${RK_CONFIG}/printer.cfg.pre-ratos'"
fi
as_user "bash '${INSTALL}'" || die "ratos-install.sh failed — is the configurator running? (./install.sh 20)"
ok "RatOS configuration installed"

warn "printer.cfg is now the RatOS TEMPLATE. Your real V-Core 4 IDEX config (from 'Current Configuration/') must be restored in a later step / manually."
