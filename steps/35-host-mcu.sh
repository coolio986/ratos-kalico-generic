# 35 — Klipper host MCU (linux process) for rpi: pins (e.g. sacrificial fan on rpi:gpio4)
# (sourced by install.sh) — RatOS's initial-setup + V-Core configs use a [mcu]/[mcu rpi]
# linux process at /tmp/klipper_host_mcu. Without it klipper can't connect. Mirrors the
# RatOS rpi_mcu module.

FW="${RK_CONFIG}/RatOS/boards/rpi/firmware.config"

if systemctl list-unit-files 2>/dev/null | grep -q '^klipper_mcu.service'; then
  ok "klipper_mcu.service already installed"
  return 0
fi
[[ -f "${FW}" ]] || die "rpi firmware.config not found at ${FW} — did step 20/30 run? (config/RatOS must be linked)"

report "Building klipper host MCU (linux process) — this compiles, ~1-2 min"
as_user "cd '${RK_KLIPPER_DIR}' && cp -f '${FW}' .config && make olddefconfig >/dev/null 2>&1 && make clean >/dev/null 2>&1 && make >/dev/null 2>&1"
[[ -f "${RK_KLIPPER_DIR}/out/klipper.elf" ]] || die "host MCU build failed (no out/klipper.elf)"

report "Installing klipper_mcu binary + service"
sudo cp "${RK_KLIPPER_DIR}/out/klipper.elf" /usr/local/bin/klipper_mcu
sudo cp "${RK_KLIPPER_DIR}/scripts/klipper-mcu.service" /etc/systemd/system/klipper_mcu.service
sudo systemctl daemon-reload
sudo systemctl enable klipper_mcu.service 2>/dev/null || true
sudo systemctl restart klipper_mcu.service
sleep 2
if [[ -e /tmp/klipper_host_mcu ]] && systemctl is-active --quiet klipper_mcu; then
  ok "host MCU running (/tmp/klipper_host_mcu up)"
else
  warn "klipper_mcu started but socket not confirmed — check: systemctl status klipper_mcu"
fi
