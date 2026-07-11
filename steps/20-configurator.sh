# 20 — RatOS Configurator (Next.js app on :3000, provides /configure + `ratos` CLI)
# (sourced by install.sh)
# Uses the PREBUILT deployment branch — do NOT build from source on a 1GB Pi (OOM).

need_cmd node
git_ensure "${RK_CONFIGURATOR_REPO}" "${RK_CONFIGURATOR_DIR}" "${RK_CONFIGURATOR_BRANCH}"

SETUP="${RK_CONFIGURATOR_DIR}/scripts/setup.sh"
[[ -f "${SETUP}" ]] || die "configurator setup.sh not found at ${SETUP} (wrong branch? expected ${RK_CONFIGURATOR_BRANCH})"

report "Running configurator setup.sh (installs deps, creates ratos-configurator.service + ratos CLI)"
# setup.sh is the RatOS-maintained installer; it expects to run as the printer user.
as_user "bash '${SETUP}'" || die "configurator setup.sh failed — inspect ${RK_CONFIGURATOR_DIR} and rerun: ./install.sh 20"

report "Enabling + starting ratos-configurator.service"
sudo systemctl daemon-reload || true
sudo systemctl enable ratos-configurator.service 2>/dev/null || warn "could not enable service (setup.sh may name it differently)"
sudo systemctl restart ratos-configurator.service 2>/dev/null || warn "could not restart service via systemctl"

wait_for_configurator

# The `ratos` CLI is what config-repo's ratos-install.sh uses to register klippy extensions.
if command -v ratos >/dev/null 2>&1; then
  ok "ratos CLI available: $(command -v ratos)"
else
  warn "ratos CLI not on PATH. setup.sh normally symlinks it to /usr/local/bin/ratos. Step 30 needs it."
fi
