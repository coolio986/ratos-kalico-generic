#!/usr/bin/env bash
# Publish a local Next.js build into coolio986/RatOS-configurator (v2.1.x-deployment)
# so `./install.sh 20` on a fresh Pi pulls the OSS UI (uPlot analysis + MJPEG VAOC).
#
# Usage (from a machine that can build / already has a build):
#   BUILD_DIR=~/Downloads/RatOS-configurator-source-v2.1.1/src/build \
#     ./scripts/publish-configurator-deployment.sh
#
# Requires: git push access to github.com/${RK_GH_OWNER}/RatOS-configurator
set -Eeuo pipefail

RK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
# shellcheck source=../config.env
source "${RK_ROOT}/config.env"

BUILD_DIR="${BUILD_DIR:-}"
WORK="${WORK:-/tmp/ratos-configurator-deployment-$$}"
BRANCH="${RK_CONFIGURATOR_BRANCH}"
REPO="${RK_CONFIGURATOR_REPO}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${BUILD_DIR}" ]] || die "Set BUILD_DIR to the Next.js app/build directory"
[[ -d "${BUILD_DIR}" ]] || die "BUILD_DIR not found: ${BUILD_DIR}"
if find "${BUILD_DIR}" -name 'scichart2d.wasm' -print -quit | grep -q .; then
  die "BUILD_DIR still contains scichart2d.wasm — refuse to publish SciChart builds"
fi
if grep -Rql --include='*.js' 'UseCommunityLicense\|SciChartSurface' "${BUILD_DIR}" 2>/dev/null; then
  die "BUILD_DIR still references SciChart — refuse to publish"
fi

echo "Cloning ${REPO} (${BRANCH}) -> ${WORK}"
rm -rf "${WORK}"
git clone --depth 1 -b "${BRANCH}" "${REPO}" "${WORK}"

echo "Replacing app/build with ${BUILD_DIR}"
rm -rf "${WORK}/app/build"
mkdir -p "${WORK}/app"
cp -a "${BUILD_DIR}" "${WORK}/app/build"

# Kalico beacon_mesh patch in bundled configuration (survives without step 36)
BM="${WORK}/configuration/klippy/beacon_mesh.py"
if [[ -f "${BM}" ]] && grep -qE 'BedMesh\.ZMesh\([^)]*self\.reactor\)' "${BM}"; then
  echo "Patching configuration/klippy/beacon_mesh.py for Kalico ZMesh API"
  python3 - <<PY
from pathlib import Path
p = Path("${BM}")
s = p.read_text()
s = s.replace(
    'BedMesh.ZMesh(profiles[profile]["mesh_params"], profile, self.reactor)',
    'BedMesh.ZMesh(profiles[profile]["mesh_params"], profile)  # Kalico: no reactor arg')
s = s.replace(
    'BedMesh.ZMesh(params, profile_name, self.reactor)',
    'BedMesh.ZMesh(params, profile_name)  # Kalico: no reactor arg')
p.write_text(s)
PY
fi

# Kalico kinematics helpers in bundled configuration
KIN="${WORK}/configuration/klippy/kinematics/ratos_hybrid_corexy.py"
if [[ -f "${KIN}" ]]; then
  if ! grep -q "supports_dual_carriage" "${KIN}"; then
    echo "Adding supports_dual_carriage to bundled kinematics"
    python3 - <<PY
from pathlib import Path
p = Path("${KIN}")
s = p.read_text()
s = s.replace(
    "self.printer = config.get_printer()",
    "self.printer = config.get_printer()\n        self.supports_dual_carriage = True  # Kalico kinematics API (IDEX)",
    1,
)
p.write_text(s)
PY
  fi
  if ! grep -q "def clear_homing_state" "${KIN}"; then
    echo "Adding clear_homing_state to bundled kinematics"
    python3 - <<PY
from pathlib import Path
p = Path("${KIN}")
s = p.read_text()
m = """    def clear_homing_state(self, axes):
        for i, _ in enumerate(self.limits):
            if i in axes:
                self.limits[i] = (1.0, -1.0)

"""
s = s.replace("    def home_axis(", m + "    def home_axis(", 1)
p.write_text(s)
PY
  fi
fi

# Bake KLIPPER_ENV wrappers into bundled shaper/belt graph scripts (Kalico cffi)
for _bt in \
  "${WORK}/configuration/scripts/idex-generate-belt-tension-graph.sh" \
  "${WORK}/configuration/scripts/generate-belt-tension-graph.sh" \
  "${WORK}/configuration/scripts/idex-generate-shaper-graph.sh" \
  "${WORK}/configuration/scripts/generate-shaper-graph-x.sh" \
  "${WORK}/configuration/scripts/generate-shaper-graph-y.sh"
do
  [[ -f "${_bt}" ]] || continue
  python3 - <<PY
from pathlib import Path
p = Path("${_bt}")
s = p.read_text()
orig = s
for name in ("calibrate_shaper.py", "graph_accelerometer.py"):
    bare = '"\${KLIPPER_DIR}"/scripts/' + name
    wrapped = '"\${KLIPPER_ENV}"/bin/python ' + bare
    s = s.replace(wrapped, "@@WRAPPED@@")
    s = s.replace(bare, wrapped)
    s = s.replace("@@WRAPPED@@", wrapped)
if s != orig:
    p.write_text(s)
    print(f"patched graph wrapper: {p.name}")
else:
    print(f"graph wrapper ok: {p.name}")
PY
done

cd "${WORK}"
git add -A
if git diff --cached --quiet; then
  echo "No changes to publish."
  exit 0
fi

git commit -m "$(cat <<'EOF'
feat: OSS analysis/VAOC build + Kalico beacon/kinematics/graphs

Replace SciChart with uPlot; MJPEG-first VAOC. Bake Kalico ZMesh,
ratos_hybrid_corexy API, and KLIPPER_ENV graph-script wrappers.
EOF
)"

echo "Pushing to origin/${BRANCH} ..."
git push origin "HEAD:${BRANCH}"
echo "Done. Fresh installs: RK_GH_OWNER=${RK_GH_OWNER} ./install.sh 20"
