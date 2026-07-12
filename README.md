# ratos-kalico-generic

Convert a **stock Raspberry Pi OS** box into a full **RatOS-equivalent** printer stack on
**Kalico** (Danger-Klipper) — keeping VAOC, visual calibration, realtime analysis, and every
RatOS macro/hook — with **no dependency on Rat Rig's prebuilt image**. Everything points at
community forks so you (and anyone) can fix issues yourselves.

## What it does
Layers RatOS on top of a KIAUH-installed base:

| Step | Does |
|---|---|
| 00 | apt deps, Node.js, groups, swap (1GB Pi needs it) |
| 10 | verify KIAUH base (Kalico + Moonraker + Mainsail) exists |
| 20 | install + run **RatOS Configurator** (`/configure`, `ratos` CLI) on :3000 |
| 30 | clone **RatOS-configuration** fork, run `ratos-install.sh` (macros, hooks, klippy extensions, udev, beacon) |
| 40 | nginx `/configure` + on-demand wake (`ratos-ondemand`; `/webcam` wakes crowsnest) |
| 50 | wire moonraker: origins -> your forks, includes, service perms |
| 60 | LMA + crowsnest (disabled on boot; auto-woken by `/webcam`) |
| 70 | step-servo support (servo_enable_delay) |
| 90 | restart + next steps |

## Prerequisites
1. Raspberry Pi OS 64-bit, user **`pi`**, SSH enabled.
2. KIAUH base installed — **Klipper set to Kalico**, plus Moonraker + Mainsail:
   ```
   cd ~ && git clone https://github.com/dw-0/kiauh.git && ./kiauh/kiauh.sh
   ```
3. Forks under your GitHub (default `coolio986`): RatOS-configuration, RatOS-configurator, RatOS-theme.

## Run
```
git clone <this repo> ~/ratos-kalico-generic
cd ~/ratos-kalico-generic
./install.sh                # all steps
./install.sh 20 30          # only steps 20 and 30
RK_GH_OWNER=youruser ./install.sh
```

## What gets baked where

| Change | Fresh-install path |
|---|---|
| Kalico `beacon_mesh` ZMesh API (no `reactor`) | step `36` re-applies; also baked by `scripts/publish-configurator-deployment.sh` into the configurator’s bundled `configuration/` |
| Kalico `ratos_hybrid_corexy` (`supports_dual_carriage`, `clear_homing_state`) | step `36` (+ publish script into fork) |
| Belt/shaper graphs via `KLIPPER_ENV` python + klipper script shebang (cffi) | step `36` (+ configuration scripts / publish) |
| `[resonance_tester]` `sweeping_period: 1.2` (Kalico default is 0) | configurator `klipper-config.ts` + templates + step `36` |
| `split_delta_z` / `log_points` / `pygam` / `check-version.py` | step `36` |
| OSS analysis (uPlot) + MJPEG-first VAOC | must live in `RatOS-configurator` **`v2.1.x-deployment`** `app/build` — publish with the script below. SciChart is **removed**, not patched. |
| Moonraker DB seeds (VAOC camera-settings) | step `65` |
| Step-servo enable delay | step `70` |

### Publish the OSS configurator deployment branch
Build on a PC (never on the Pi), then push:

```bash
# after: cd RatOS-configurator-source-…/src && pnpm build
BUILD_DIR=/path/to/RatOS-configurator-source-…/src/build \
  ./scripts/publish-configurator-deployment.sh
```

That replaces `app/build` on `v2.1.x-deployment` and applies the Kalico `beacon_mesh` / kinematics patches into the bundled `configuration/`. Step `36` still re-applies those patches so a stale fork cannot brick a reinstall.

## Homing / Beacon
`G28 X Y` should work with step-servos. Full `G28` (Z) needs a **valid Beacon proximity model**.

`Toolhead stopped below model range` means post-homing Beacon samples returned `dist: inf` (sensor reading outside the saved model). Typical recovery:

```text
G28 X Y
BEACON_MODEL_REMOVE NAME=default
BEACON_RATOS_CALIBRATE          # bed clear; writes a new [beacon model default]
G28                             # full home
```

Do **not** restore an old SAVE_CONFIG beacon model from another sheet/temp without re-running calibrate.

## Notes / open items
- **Native step-servos:** the fork should stop emitting `[tmc5160 ...]` for servo axes, retiring the
  old `strip_tmc.py` / watcher / systemd-override hack. Until then step 70 installs `servo_enable_delay`.
- Target host validated so far: **Pi 4, 1GB, Debian 13 (trixie)** — configurator uses the *prebuilt*
  deployment branch (never build Node on-device).
