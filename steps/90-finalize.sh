# 90 — finalize: restart core services, leave configurator/crowsnest on-demand
# (sourced by install.sh)

report "Installing optional manual helpers (nginx auto-wakes; these are fallbacks)"
sudo tee /usr/local/bin/ratos-start-configure >/dev/null <<'H'
#!/bin/sh
exec sudo systemctl start ratos-configurator.service
H
sudo tee /usr/local/bin/ratos-start-vaoc >/dev/null <<'H'
#!/bin/sh
sudo systemctl start ratos-configurator.service
exec sudo systemctl start crowsnest.service
H
sudo tee /usr/local/bin/ratos-stop-vaoc >/dev/null <<'H'
#!/bin/sh
sudo systemctl stop crowsnest.service
if [ "$1" = "--all" ]; then
  sudo systemctl stop ratos-configurator.service
fi
H
sudo chmod 755 /usr/local/bin/ratos-start-configure /usr/local/bin/ratos-start-vaoc /usr/local/bin/ratos-stop-vaoc

report "Restarting core printer services"
sudo systemctl daemon-reload || true
for svc in klipper moonraker nginx ratos-ondemand; do
  sudo systemctl restart "${svc}" 2>/dev/null && ok "restarted ${svc}" || warn "could not restart ${svc}"
done
# Not enabled on boot — nginx /configure and /webcam wake them via ratos-ondemand.
sudo systemctl disable --now crowsnest.service 2>/dev/null || true
sudo systemctl disable --now ratos-configurator.service 2>/dev/null || true
ok "configurator + crowsnest on-demand (auto via nginx; idle-stop ~15 min)"

cat <<EOF

  Base install complete.

  Auto on-demand (no manual start needed):
    http://<printer-ip>/configure/     → starts ratos-configurator
    http://<printer-ip>/webcam/…       → starts crowsnest (VAOC)
    Idle ~15 min with no use           → both stop automatically

  Next:
    1) Open http://<printer-ip>/configure/
       (board = BTT Octopus 1.1, toolboards = 2x EBB42, printer = V-Core 4 IDEX).
       This GENERATES RatOS.cfg. First load may take ~30–90s (cold start).
    2) FLASH MCUs (Octopus + 2x EBB42) via the configurator or 'make flash'.
    3) Home XY, then calibrate Beacon (required before full G28 / Z):
         G28 X Y
         BEACON_RATOS_CALIBRATE
       If you see "Toolhead stopped below model range", the proximity model is
       stale/out-of-domain — remove it and recalibrate:
         BEACON_MODEL_REMOVE NAME=default
         BEACON_RATOS_CALIBRATE
    4) Full home + leveling:  G28  then  Z_TILT_ADJUST  then bed mesh.
    5) VAOC:  http://<printer-ip>/configure/calibration
       Analysis: http://<printer-ip>/configure/analysis

  Re-publish OSS configurator UI (PC, not Pi):
    BUILD_DIR=…/src/build ./scripts/publish-configurator-deployment.sh

  Health checks:
    sudo systemctl status klipper moonraker nginx ratos-ondemand
    # must print nothing:
    find ~/ratos-configurator/app/build -name 'scichart*.wasm'
EOF

