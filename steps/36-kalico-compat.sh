# 36 — Kalico + Trixie compatibility patches for RatOS
# (sourced by install.sh) — RatOS targets its own klipper fork + Bookworm/py3.11. On Kalico
# + Debian 13 (py3.13) several things break. These idempotent patches fix them and survive
# configurator redeploys (this step re-applies after `git pull`).

RATOS_DIR="${RK_CONFIG}/RatOS"

# --- 1) check-version.py: Kalico moved klippy to a package with relative imports ----------
CV="${RK_CONFIGURATOR_DIR}/app/scripts/check-version.py"
if [[ -f "${CV}" ]]; then
  if grep -q "from klippy import reactor" "${CV}"; then
    ok "check-version.py already Kalico-compatible"
  else
    report "Patching check-version.py for Kalico package imports"
    as_user "cp '${CV}' '${CV}.pre-kalico'"
    as_user "sed -i 's|sys.path.append(os.path.join(KLIPPER_DIR, \"klippy\"))|sys.path.append(KLIPPER_DIR)|' '${CV}'"
    as_user "sed -i 's|^import reactor\$|from klippy import reactor|; s|^import serialhdl\$|from klippy import serialhdl|; s|^import clocksync\$|from klippy import clocksync|; s|^import mcu\$|from klippy import mcu|' '${CV}'"
    ok "check-version.py patched"
  fi
fi

# --- 2) ratos_hybrid_corexy kinematics: Kalico API — supports_dual_carriage + clear_homing_state
KIN="${RATOS_DIR}/klippy/kinematics/ratos_hybrid_corexy.py"
if [[ -f "${KIN}" ]]; then
  # 2a) supports_dual_carriage attribute (checked by Kalico printer.py for IDEX)
  if ! grep -q "supports_dual_carriage" "${KIN}"; then
    report "Adding supports_dual_carriage to ratos_hybrid_corexy (Kalico kinematics API)"
    as_user "python3 -c \"p='${KIN}'; s=open(p).read(); s=s.replace('self.printer = config.get_printer()','self.printer = config.get_printer()\n        self.supports_dual_carriage = True  # Kalico kinematics API (IDEX)',1); open(p,'w').write(s)\""
    grep -q "supports_dual_carriage" "${KIN}" && ok "supports_dual_carriage added" || warn "patch failed"
  else ok "supports_dual_carriage present"; fi
  # 2b) clear_homing_state method (Kalico force_move.py SET_KINEMATIC_POSITION calls it)
  if ! grep -q "def clear_homing_state" "${KIN}"; then
    report "Adding clear_homing_state to ratos_hybrid_corexy (Kalico kinematics API)"
    as_user "python3 -c \"p='${KIN}'; s=open(p).read(); m='    def clear_homing_state(self, axes):\n        for i, _ in enumerate(self.limits):\n            if i in axes:\n                self.limits[i] = (1.0, -1.0)\n\n'; s=s.replace('    def home_axis(', m+'    def home_axis(', 1); open(p,'w').write(s)\""
    grep -q "def clear_homing_state" "${KIN}" && ok "clear_homing_state added" || warn "patch failed"
  else ok "clear_homing_state present"; fi
fi

# --- 3) beacon.cfg: log_points is a RatOS bed_mesh patch absent in Kalico -----------------
BC="${RATOS_DIR}/z-probe/beacon.cfg"
if [[ -f "${BC}" ]] && grep -qE "^log_points:" "${BC}"; then
  report "Removing log_points from beacon.cfg (Kalico bed_mesh lacks it)"
  as_user "sed -i 's/^log_points:/#log_points:  # removed: Kalico stock bed_mesh/' '${BC}'"
  ok "log_points removed"
fi

# --- 4) V-Core 4 printer cfgs: split_delta_z 0.001 < Kalico minval 0.01 -------------------
for pc in "${RATOS_DIR}"/printers/v-core-4*/v-core-4*.cfg; do
  [[ -f "${pc}" ]] || continue
  if grep -qE "^split_delta_z: 0.001" "${pc}"; then
    as_user "sed -i 's/^split_delta_z: 0.001/split_delta_z: 0.01/' '${pc}'"
    ok "split_delta_z -> 0.01 in $(basename "$(dirname "${pc}")")"
  fi
done

# --- 5) pygam: klippy requirements pin 0.9.1 needs py<3.13; Trixie is py3.13 --------------
if ! "${RK_KLIPPY_ENV}/bin/python" -c "import pygam" 2>/dev/null; then
  report "Installing Python 3.13-compatible pygam into klippy-env"
  as_user "'${RK_KLIPPY_ENV}/bin/pip' install -q 'pygam>=0.10.1'" || warn "pygam install failed"
fi
"${RK_KLIPPY_ENV}/bin/python" -c "import pygam" 2>/dev/null && ok "pygam available in klippy-env" || warn "pygam missing"
