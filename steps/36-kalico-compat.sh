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

# --- 6) beacon_mesh.py: Kalico ZMesh(params, name) — no reactor arg --------------------
# Stock RatOS/Klipper ZMesh.__init__(params, name, reactor); Kalico dropped reactor.
# Without this, BEACON_RATOS_CALIBRATE / BEACON_CREATE_SCAN_COMPENSATION_MESH dies with:
#   TypeError: ZMesh.__init__() takes 3 positional arguments but 4 were given
BM="${RATOS_DIR}/klippy/beacon_mesh.py"
if [[ -f "${BM}" ]] && grep -qE 'BedMesh\.ZMesh\([^)]*self\.reactor\)' "${BM}"; then
  report "Patching beacon_mesh.py ZMesh calls for Kalico (drop reactor arg)"
  as_user "python3 -c \"
from pathlib import Path
p = Path('${BM}')
s = p.read_text()
s = s.replace(
    'BedMesh.ZMesh(profiles[profile][\\\"mesh_params\\\"], profile, self.reactor)',
    'BedMesh.ZMesh(profiles[profile][\\\"mesh_params\\\"], profile)  # Kalico: no reactor arg')
s = s.replace(
    'BedMesh.ZMesh(params, profile_name, self.reactor)',
    'BedMesh.ZMesh(params, profile_name)  # Kalico: no reactor arg')
p.write_text(s)
\""
  if grep -qE 'BedMesh\.ZMesh\([^)]*self\.reactor\)' "${BM}"; then
    warn "beacon_mesh ZMesh patch incomplete"
  else
    ok "beacon_mesh ZMesh calls Kalico-compatible"
  fi
elif [[ -f "${BM}" ]]; then
  ok "beacon_mesh ZMesh already Kalico-compatible"
fi

# --- 7) Resonance graphs: run Klipper graph scripts via klippy-env -----------------------
# Scripts invoke graph_accelerometer.py / calibrate_shaper.py by path; their shebang is
# system python3, which on Kalico fails with ModuleNotFoundError: cffi (chelper).
# Always use KLIPPER_ENV python.
for _bt in \
  "${RATOS_DIR}/scripts/idex-generate-belt-tension-graph.sh" \
  "${RATOS_DIR}/scripts/generate-belt-tension-graph.sh" \
  "${RATOS_DIR}/scripts/idex-generate-shaper-graph.sh" \
  "${RATOS_DIR}/scripts/generate-shaper-graph-x.sh" \
  "${RATOS_DIR}/scripts/generate-shaper-graph-y.sh"
do
  [[ -f "${_bt}" ]] || continue
  _patched=0
  if grep -q 'graph_accelerometer.py' "${_bt}"; then
    if grep -qE '\$\{KLIPPER_ENV\}"/bin/python.*graph_accelerometer' "${_bt}" \
      || grep -qE "\$\{KLIPPER_ENV\}/bin/python.*graph_accelerometer" "${_bt}"; then
      ok "belt graph uses klippy-env: $(basename "${_bt}")"
    else
      report "Patching $(basename "${_bt}") graph_accelerometer → KLIPPER_ENV python"
      as_user "sed -i 's|\"\${KLIPPER_DIR}\"/scripts/graph_accelerometer.py|\"\${KLIPPER_ENV}\"/bin/python \"\${KLIPPER_DIR}\"/scripts/graph_accelerometer.py|g' '${_bt}'"
      _patched=1
    fi
  fi
  if grep -q 'calibrate_shaper.py' "${_bt}"; then
    if grep -qE '\$\{KLIPPER_ENV\}"/bin/python.*calibrate_shaper' "${_bt}" \
      || grep -qE "\$\{KLIPPER_ENV\}/bin/python.*calibrate_shaper" "${_bt}"; then
      ok "shaper graph uses klippy-env: $(basename "${_bt}")"
    else
      report "Patching $(basename "${_bt}") calibrate_shaper → KLIPPER_ENV python"
      as_user "sed -i 's|\"\${KLIPPER_DIR}\"/scripts/calibrate_shaper.py|\"\${KLIPPER_ENV}\"/bin/python \"\${KLIPPER_DIR}\"/scripts/calibrate_shaper.py|g' '${_bt}'"
      _patched=1
    fi
  fi
  [[ "${_patched}" -eq 1 ]] && ok "patched $(basename "${_bt}")"
done

# --- 7b) resonance_tester: restore RatOS-equivalent slow sweep on Kalico -----------------
# Kalico defaults sweeping_period to 0 (disabled). RatOS/mainline default is 1.2, which is
# the visible axis oscillation during belt/shaper tests (especially hybrid CoreXY IDEX).
_RC="${RK_CONFIG}/RatOS.cfg"
if [[ -f "${_RC}" ]] && grep -qE '^\[resonance_tester\]' "${_RC}"; then
  if grep -qE '^sweeping_period:' "${_RC}"; then
    ok "sweeping_period already set in RatOS.cfg"
  else
    report "Adding sweeping_period/sweeping_accel to [resonance_tester] in RatOS.cfg"
    as_user "python3 -c \"
from pathlib import Path
p = Path('${_RC}')
lines = p.read_text().splitlines(True)
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == '[resonance_tester]':
        body = []
        j = i + 1
        while j < len(lines) and lines[j].strip() and not lines[j].startswith('['):
            body.append(lines[j]); j += 1
        inserted = False
        new_body = []
        for b in body:
            if b.lstrip().startswith('probe_points:') and not inserted:
                new_body.append('sweeping_period: 1.2\\n')
                new_body.append('sweeping_accel: 400\\n')
                inserted = True
            new_body.append(b)
        if not inserted:
            new_body.append('sweeping_period: 1.2\\n')
            new_body.append('sweeping_accel: 400\\n')
        out.extend(new_body)
        i = j
        continue
    i += 1
p.write_text(''.join(out))
\""
    grep -qE '^sweeping_period:' "${_RC}" && ok "sweeping_period added to RatOS.cfg" || warn "sweeping_period patch failed"
  fi
fi

# Also bake into bundled configuration templates under RatOS/ (idempotent)
while IFS= read -r -d '' _cfg; do
  grep -qE '^\[resonance_tester\]' "${_cfg}" || continue
  grep -qE '^sweeping_period:' "${_cfg}" && continue
  report "Adding sweeping_* to $(basename "$(dirname "${_cfg}")")/$(basename "${_cfg}")"
  as_user "python3 -c \"
from pathlib import Path
p = Path('${_cfg}')
lines = p.read_text().splitlines(True)
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == '[resonance_tester]':
        body = []
        j = i + 1
        while j < len(lines) and lines[j].strip() and not lines[j].startswith('['):
            body.append(lines[j]); j += 1
        inserted = False
        new_body = []
        for b in body:
            if b.lstrip().startswith('probe_points:') and not inserted:
                new_body.append('sweeping_period: 1.2\\n')
                new_body.append('sweeping_accel: 400\\n')
                inserted = True
            new_body.append(b)
        if not inserted:
            new_body.append('sweeping_period: 1.2\\n')
            new_body.append('sweeping_accel: 400\\n')
        out.extend(new_body)
        i = j
        continue
    i += 1
p.write_text(''.join(out))
\""
done < <(find "${RATOS_DIR}" -name '*.cfg' -print0 2>/dev/null)

# --- 8) Configurator UI sanity (SciChart must be gone; VAOC uses MJPEG) -------------------
# Analysis/VAOC now ship as MIT uPlot + MJPEG-first camera (`/webcam/stream`). Do NOT
# patch SciChart fonts here — SciChart is removed from the OSS build. Fresh installs must
# pull a v2.1.x-deployment that already contains that build (see scripts/publish-configurator-
# deployment.sh). Fail loudly if a stale SciChart deployment is detected.
BUILD_STATIC="${RK_CONFIGURATOR_DIR}/app/build"
if [[ -d "${BUILD_STATIC}" ]]; then
  if find "${BUILD_STATIC}" -name 'scichart2d.wasm' -print -quit | grep -q . \
    || grep -Rql --include='*.js' 'SciChartSurface\|UseCommunityLicense\|scichart-react' "${BUILD_STATIC}" 2>/dev/null; then
    warn "Stale SciChart assets detected under ${BUILD_STATIC}"
    warn "Publish the OSS uPlot/VAOC build to ${RK_CONFIGURATOR_REPO} branch ${RK_CONFIGURATOR_BRANCH}"
    warn "then re-run: ./install.sh 20 36"
  else
    ok "configurator build has no SciChart (uPlot/VAOC path)"
  fi
fi

# --- 9) Clear klipper bytecode cache so patched extensions/kinematics reload -------------
# Python does NOT reliably invalidate __pycache__ for symlinked, in-place-edited modules,
# so a stale .pyc can mask patches above (e.g. missing clear_homing_state at runtime).
report "Clearing klipper bytecode cache (forces recompile of patched modules)"
find "${RK_KLIPPER_DIR}/klippy" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
ok "bytecode cache cleared — restart klipper to load patched modules"
