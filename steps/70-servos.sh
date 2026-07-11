# 70 — step-servo support (X/Y IDEX, 4 servos)
# (sourced by install.sh)
#
# NATIVE GOAL (task #3): the forked configurator should NOT emit [tmc5160 stepper_x/y/
# dual_carriage/stepper_y1] blocks for servo axes, which removes the need for the old
# strip_tmc.py / watcher / systemd-override hack entirely.
# Until that fork change lands, this step installs the servo_enable_delay klippy
# extension (dwell before homing so step servos finish their ~500ms enable init).

RK_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SRC="${RK_ROOT}/files/servo_enable_delay.py"
# Prefer the fork's bundled copy if present (native path)
FORK_COPY="${RK_CONFIG}/RatOS/klippy/servo_enable_delay.py"
[[ -f "${FORK_COPY}" ]] && SRC="${FORK_COPY}"

[[ -f "${SRC}" ]] || { warn "servo_enable_delay.py not found; skipping servo step"; return 0; }

DEST="${RK_CONFIG}/RatOS/klippy/servo_enable_delay.py"
report "Installing servo_enable_delay extension"
as_user "mkdir -p '$(dirname "${DEST}")' && cp '${SRC}' '${DEST}'"

if command -v ratos >/dev/null 2>&1; then
  # no -e: -e means error-if-exists; we want idempotent re-runs
  as_user "ratos extensions register klipper servo_enable_delay '${DEST}'" \
    || warn "servo_enable_delay registration failed (may already be registered)"
  as_user "ratos extensions symlink klipper" || warn "symlink failed"
  ok "servo_enable_delay registered + symlinked"
else
  warn "ratos CLI missing — cannot register servo_enable_delay (rerun step 20)"
fi

cat <<EOF

  Reminder — add to your printer.cfg (already in your 'Current Configuration/printer.cfg'):

    [servo_enable_delay]
    axes: stepper_x, stepper_y, dual_carriage, stepper_y1
    delay: 0.5

  Servo axes use: microsteps=1, full_steps_per_rotation=4096, rotation_distance=40,
  step_pulse_duration=0.0000025, and NO [tmc....] block.
EOF
