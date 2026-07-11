# 00 — system prep: packages, node, swap, groups
# (sourced by install.sh)

report "Installing system dependencies (apt)"
sudo apt-get update
# RatOS deps: python3-serial (klipper), python3-opencv (VAOC camera),
# python3-numpy + python3-matplotlib (resonance/shaper graphs). Plus web + build tools.
sudo apt-get install -y \
  git curl wget unzip nginx \
  python3-serial python3-opencv python3-numpy python3-matplotlib \
  inotify-tools polkitd pkexec ca-certificates jq \
  || die "apt dependency install failed"
ok "apt dependencies installed"

# --- Node.js (configurator is a Next.js app) --------------------------------
report "Ensuring Node.js >= 18"
node_ok=0
if command -v node >/dev/null 2>&1; then
  ver="$(node -v | sed 's/^v//; s/\..*//')"
  [[ "${ver:-0}" -ge 18 ]] && node_ok=1
fi
if [[ $node_ok -eq 0 ]]; then
  # Debian 13 (trixie) ships nodejs 20 in apt; prefer that. Fall back to NodeSource.
  sudo apt-get install -y nodejs npm || true
  if command -v node >/dev/null 2>&1 && [[ "$(node -v | sed 's/^v//; s/\..*//')" -ge 18 ]]; then
    node_ok=1
  else
    warn "apt node too old/missing; installing NodeSource ${RK_NODE_MAJOR}.x"
    curl -fsSL "https://deb.nodesource.com/setup_${RK_NODE_MAJOR}.x" | sudo -E bash - || warn "NodeSource setup failed (trixie may be unsupported)"
    sudo apt-get install -y nodejs || true
  fi
fi
command -v node >/dev/null 2>&1 && ok "node $(node -v)" || warn "Node.js not installed — configurator step will fail until fixed"

# pnpm: the configurator's setup.sh runs `npm install -g pnpm` AS THE USER, which
# fails EACCES against Debian's apt-node global dir. Install it system-wide (root) here.
report "Ensuring pnpm (system-wide)"
if ! command -v pnpm >/dev/null 2>&1; then
  sudo npm install -g pnpm@9 || warn "global pnpm install failed — configurator step may fail"
fi
command -v pnpm >/dev/null 2>&1 && ok "pnpm $(pnpm -v 2>/dev/null)" || warn "pnpm missing"

# --- Serial/gpio groups for the printer user --------------------------------
report "Adding ${RK_USER} to hardware groups"
sudo usermod -aG tty,dialout,gpio,video "${RK_USER}" 2>/dev/null || true
ok "groups set (re-login needed to take effect)"

# --- Swap: 1GB Pi 4 is tight with Node running ------------------------------
report "Ensuring swap (1GB RAM board needs headroom for Node)"
if ! sudo swapon --show | grep -q .; then
  if command -v dphys-swapfile >/dev/null 2>&1; then
    sudo sed -i 's/^#\?CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile || true
    sudo dphys-swapfile setup && sudo dphys-swapfile swapon || warn "dphys-swapfile setup failed"
  else
    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
  ok "swap enabled"
else
  ok "swap already present: $(sudo swapon --show=NAME --noheadings | tr '\n' ' ')"
fi
