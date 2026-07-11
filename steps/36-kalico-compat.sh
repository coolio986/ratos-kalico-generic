# 36 — Kalico compatibility patches for RatOS helper scripts
# (sourced by install.sh)
# Kalico moved klippy to a package with relative imports (`from . import chelper, util`),
# so scripts that import klippy modules top-level break with
#   "ImportError: attempted relative import with no known parent package".
# check-version.py (board version detection used by the wizard) is one such script — its
# failure makes freshly-flashed boards show as "unresponsive" in the wizard.

CV="${RK_CONFIGURATOR_DIR}/app/scripts/check-version.py"
if [[ ! -f "${CV}" ]]; then
  warn "check-version.py not found at ${CV} — skipping Kalico compat patch"
  return 0
fi

if grep -q "from klippy import reactor" "${CV}"; then
  ok "check-version.py already Kalico-compatible"
  return 0
fi

report "Patching check-version.py for Kalico package imports"
as_user "cp '${CV}' '${CV}.pre-kalico'"
# Put klippy's PARENT dir on sys.path (so `klippy` resolves as a package, not klippy.py),
# and import the modules via the package.
as_user "sed -i 's|sys.path.append(os.path.join(KLIPPER_DIR, \"klippy\"))|sys.path.append(KLIPPER_DIR)|' '${CV}'"
as_user "sed -i 's|^import reactor\$|from klippy import reactor|; s|^import serialhdl\$|from klippy import serialhdl|; s|^import clocksync\$|from klippy import clocksync|; s|^import mcu\$|from klippy import mcu|' '${CV}'"

if grep -q "from klippy import reactor" "${CV}"; then
  ok "check-version.py patched for Kalico"
else
  warn "check-version.py patch did not apply cleanly — inspect ${CV}"
fi
