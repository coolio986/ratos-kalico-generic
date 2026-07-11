# 10 — verify the KIAUH base exists (Kalico + Moonraker + Mainsail)
# (sourced by install.sh)
# This installer LAYERS onto a KIAUH base; it does not install klipper itself.

report "Checking KIAUH base install"

missing=()
[[ -d "${RK_KLIPPER_DIR}/.git" ]]   || missing+=("klipper (${RK_KLIPPER_DIR})")
[[ -d "${RK_KLIPPY_ENV}" ]]         || missing+=("klippy-env (${RK_KLIPPY_ENV})")
[[ -d "${RK_MOONRAKER_DIR}/.git" ]] || missing+=("moonraker (${RK_MOONRAKER_DIR})")
[[ -d "${RK_PRINTER_DATA}" ]]       || missing+=("printer_data (${RK_PRINTER_DATA})")
[[ -d "${RK_MAINSAIL_DIR}" ]]       || missing+=("mainsail (${RK_MAINSAIL_DIR})")

if [[ ${#missing[@]} -gt 0 ]]; then
  warn "Base components missing: ${missing[*]}"
  cat <<EOF

  Install the base with KIAUH first, then re-run this installer:

    cd ~ && git clone https://github.com/dw-0/kiauh.git && ./kiauh/kiauh.sh

  In KIAUH:
    1) (Optional) Settings -> set the Klipper repo to Kalico:
         ${RK_KALICO_REPO}   branch: main
    2) Install -> Klipper   (python3, single instance)
    3) Install -> Moonraker
    4) Install -> Mainsail
    5) Install -> Mainsail-Config?  NO  (RatOS provides the config)

EOF
  die "KIAUH base not found — see instructions above"
fi
ok "KIAUH base present"

# Confirm the klipper checkout is actually Kalico (warn only — non-fatal).
origin="$(as_user "cd '${RK_KLIPPER_DIR}' && git remote get-url origin" 2>/dev/null || true)"
if echo "${origin}" | grep -qiE 'kalico|danger'; then
  ok "klipper remote is Kalico: ${origin}"
else
  warn "klipper remote is '${origin}', not Kalico. To switch: KIAUH -> Settings -> custom repo -> ${RK_KALICO_REPO}, then re-run KIAUH Klipper install."
fi
