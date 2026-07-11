# 90 — finalize: restart services, print next steps
# (sourced by install.sh)

report "Restarting services"
sudo systemctl daemon-reload || true
for svc in ratos-configurator klipper moonraker nginx; do
  sudo systemctl restart "${svc}" 2>/dev/null && ok "restarted ${svc}" || warn "could not restart ${svc}"
done

cat <<EOF

  ${RK_GREEN}Base install complete.${RK_NC}

  Next:
    1) Open  http://<printer-ip>/configure/   -> finish the hardware wizard
       (board = BTT Octopus 1.1, toolboards = 2x EBB42, printer = V-Core 4 IDEX).
       This is what GENERATES RatOS.cfg.
    2) VAOC + visual calibration:   http://<printer-ip>/configure/calibration
       Realtime analysis:           http://<printer-ip>/configure/analysis
    3) Restore your real V-Core 4 IDEX printer.cfg overrides + ratos-variables.cfg
       from 'Current Configuration/' (servos, beacon model, bed meshes, shapers).
    4) FLASH MCUs (Octopus + 2x EBB42) via the configurator or 'make flash'.
    5) Calibrate beacon:  BEACON_RATOS_CALIBRATE

  Health checks:
    sudo systemctl status ratos-configurator klipper moonraker nginx
    curl -s -o /dev/null -w '%{http_code}\n' http://localhost/configure/
EOF
