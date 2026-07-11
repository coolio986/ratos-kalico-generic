# 60 — extras: linear movement analysis (realtime analysis backend) + crowsnest (webcam)
# (sourced by install.sh). beacon is installed by ratos-install.sh in step 30.

# --- Klipper Linear Movement Analysis (powers /configure/analysis) ----------
LMA_DIR="${RK_HOME}/klipper_linear_movement_analysis"
git_ensure "${RK_LMA_REPO}" "${LMA_DIR}" "main"

report "Installing linear_movement_analysis into klippy-env + registering"
as_user "'${RK_KLIPPY_ENV}/bin/pip' install -q matplotlib" || warn "matplotlib pip install failed"
if [[ -f "${LMA_DIR}/install.sh" ]]; then
  as_user "bash '${LMA_DIR}/install.sh'" || warn "LMA install.sh failed (non-fatal)"
fi
if command -v ratos >/dev/null 2>&1; then
  as_user "ratos extensions register klipper linear_movement_analysis '${LMA_DIR}/linear_movement_vibrations.py'" \
    || warn "LMA extension registration failed"
  ok "linear_movement_analysis registered"
else
  warn "ratos CLI missing — cannot register LMA (rerun step 20 first)"
fi

# --- Crowsnest (webcam streamer; VAOC/timelapse use the camera) -------------
if [[ -d "${RK_HOME}/crowsnest/.git" ]]; then
  ok "crowsnest already installed"
else
  report "Installing crowsnest (best-effort)"
  git_ensure "https://github.com/mainsail-crew/crowsnest.git" "${RK_HOME}/crowsnest" "master"
  if [[ -f "${RK_HOME}/crowsnest/tools/install.sh" ]]; then
    sudo bash -lc "cd '${RK_HOME}/crowsnest' && BASE_USER='${RK_USER}' tools/install.sh" || warn "crowsnest install failed (non-fatal — webcam only)"
  fi
fi
