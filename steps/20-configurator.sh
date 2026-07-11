# 20 — RatOS Configurator (Next.js app on :3000, provides /configure + `ratos` CLI)
# (sourced by install.sh) — uses the PREBUILT deployment branch.
# The deployment layout is: app/ (prebuilt app) + configuration/ (bundled config repo).
# app/scripts/setup.sh does everything: pnpm deps, `ratos` CLI, systemd service, udev
# rules, sudoers, and SYMLINKS config/RatOS -> configuration/ (so step 30 must not clone).

need_cmd node
need_cmd pnpm
git_ensure "${RK_CONFIGURATOR_REPO}" "${RK_CONFIGURATOR_DIR}" "${RK_CONFIGURATOR_BRANCH}"

SETUP="${RK_CONFIGURATOR_DIR}/app/scripts/setup.sh"
[[ -f "${SETUP}" ]] || die "configurator setup.sh not found at ${SETUP} (wrong branch? expected ${RK_CONFIGURATOR_BRANCH})"

# Workaround: configurator setup.sh install_cli runs `rm` (no -f) on the CLI path,
# which aborts on a fresh box where /usr/local/bin/ratos doesn't exist yet.
# Ensure a plain file is present so that rm succeeds. (Proper fix: `rm -f` in the fork.)
sudo sh -c 'rm -f /usr/local/bin/ratos; : > /usr/local/bin/ratos'
# A partially-failed setup.sh leaves root-owned /tmp/03*-ratos-configurator-* files
# that then block `touch` on the next run. Clear them so re-runs are clean.
sudo rm -f /tmp/03*-ratos-configurator-* 2>/dev/null || true

report "Running configurator setup.sh (pnpm deps, ratos CLI, service, udev, symlink config)"
# runs as the printer user; refuses root. it uses sudo internally (passwordless).
as_user "bash '${SETUP}'" || die "configurator setup.sh failed — inspect: sudo journalctl -u ratos-configurator -n 100 ; rerun: ./install.sh 20"

report "Starting ratos-configurator.service"
sudo systemctl daemon-reload || true
sudo systemctl enable ratos-configurator.service 2>/dev/null || true
sudo systemctl restart ratos-configurator.service 2>/dev/null || warn "could not (re)start service via systemctl"

wait_for_configurator

if command -v ratos >/dev/null 2>&1; then
  ok "ratos CLI available: $(command -v ratos)"
else
  warn "ratos CLI not on PATH — step 30 (extension registration) needs it. setup.sh symlinks it to /usr/local/bin/ratos."
fi
