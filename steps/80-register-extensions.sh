# 80 — ensure ALL bundled klippy extensions are registered + symlinked
# (sourced by install.sh) — runs AFTER extras (LMA, step 60) so every extension's
# file exists. The bundled ratos-install.sh registers extensions via a loop whose
# realpath fails for not-yet-installed files (LMA) and can miss the newer set
# (fastconfig, named_offsets, beacon_*, ratos_dual_carriage_extras). This step is the
# order-independent safety net: register every bundled extension, then symlink.

K="${RK_CONFIG}/RatOS/klippy"
[[ -d "${K}" ]] || { warn "klippy dir ${K} missing — did step 30 run?"; return 0; }
command -v ratos >/dev/null 2>&1 || { warn "ratos CLI missing — cannot register (rerun step 20)"; return 0; }

report "Registering all bundled klippy extras"
for py in "${K}"/*.py; do
  [[ -e "${py}" ]] || continue
  base="$(basename "${py}" .py)"
  # vaoc_led is experimental / registered on demand — skip to match RatOS.
  [[ "${base}" == "vaoc_led" ]] && continue
  as_user "ratos extensions register klipper '${base}' '${py}'" >/dev/null 2>&1 || true
done

report "Registering bundled kinematics extensions"
for py in "${K}"/kinematics/*.py; do
  [[ -e "${py}" ]] || continue
  base="$(basename "${py}" .py)"
  as_user "ratos extensions register klipper -k '${base}' '${py}'" >/dev/null 2>&1 || true
done

report "Symlinking all registered extensions into klipper"
as_user "ratos extensions symlink" || warn "ratos extensions symlink failed — run manually"
ok "all bundled klippy extensions registered + symlinked"
