# 50 — wire moonraker: point update_manager at YOUR forks, include RatOS config,
# grant service permissions.
# (sourced by install.sh)

MOON_TOP="${RK_CONFIG}/moonraker.conf"
MOON_RATOS="${RK_CONFIG}/RatOS/moonraker.conf"

# 1) top-level moonraker.conf must include RatOS/moonraker.conf
report "Ensuring ${MOON_TOP} includes RatOS/moonraker.conf"
if [[ ! -f "${MOON_TOP}" ]]; then
  as_user "printf '[include RatOS/moonraker.conf]\n' > '${MOON_TOP}'"
  ok "created moonraker.conf with RatOS include"
elif ! grep -q 'include RatOS/moonraker.conf' "${MOON_TOP}"; then
  as_user "sed -i '1i [include RatOS/moonraker.conf]' '${MOON_TOP}'"
  ok "prepended RatOS include"
else
  ok "RatOS include already present"
fi

# 2) repoint the three RatOS update_manager origins to your fork (community independence)
if [[ -f "${MOON_RATOS}" ]]; then
  report "Repointing update_manager origins Rat-OS -> ${RK_GH_OWNER}"
  as_user "sed -i 's#github.com/Rat-OS/RatOS-configuration#github.com/${RK_GH_OWNER}/RatOS-configuration#g; s#github.com/Rat-OS/RatOS-configurator#github.com/${RK_GH_OWNER}/RatOS-configurator#g; s#github.com/Rat-OS/RatOS-theme#github.com/${RK_GH_OWNER}/RatOS-theme#g' '${MOON_RATOS}'"
  ok "origins repointed (verify: grep origin ${MOON_RATOS})"
  warn "Best practice: bake this repoint into the fork so 'git pull' never reverts it."
else
  warn "${MOON_RATOS} not found — did step 30 run?"
fi

# 3) moonraker service-permission allowlist (lets moonraker restart the configurator)
ASVC="${RK_PRINTER_DATA}/moonraker.asvc"
report "Ensuring moonraker.asvc grants ratos-configurator + klipper_mcu"
for svc in klipper_mcu ratos-configurator crowsnest sonar webcamd; do
  if [[ ! -f "${ASVC}" ]] || ! grep -qx "${svc}" "${ASVC}"; then
    as_user "printf '%s\n' '${svc}' >> '${ASVC}'"
  fi
done
ok "moonraker.asvc updated"
