# 90 — finalize: restart services, print next steps
# (sourced by install.sh)

report "Restarting services"
sudo systemctl daemon-reload || true
for svc in ratos-configurator klipper moonraker nginx; do
  sudo systemctl restart "${svc}" 2>/dev/null && ok "restarted ${svc}" || warn "could not restart ${svc}"
done

cat <<EOF

  Base install complete.

  Next:
    1) Open  http://<printer-ip>/configure/   -> finish the hardware wizard
       (board = BTT Octopus 1.1, toolboards = 2x EBB42, printer = V-Core 4 IDEX).
       This is what GENERATES RatOS.cfg.
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
       (OSS uPlot + MJPEG stream — SciChart must not be present.)

  Re-publish OSS configurator UI (PC, not Pi):
    BUILD_DIR=…/src/build ./scripts/publish-configurator-deployment.sh

  Health checks:
    sudo systemctl status ratos-configurator klipper moonraker nginx
    curl -s -o /dev/null -w '%{http_code}\n' http://localhost/configure/
    # must print nothing:
    find ~/ratos-configurator/app/build -name 'scichart*.wasm'
EOF

