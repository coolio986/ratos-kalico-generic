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
| 40 | nginx `/configure` proxy -> :3000 |
| 50 | wire moonraker: origins -> your forks, includes, service perms |
| 60 | linear movement analysis (realtime analysis) + crowsnest |
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

## Notes / open items
- **Kalico compatibility** of RatOS klippy extensions (`ratos_hybrid_corexy` kinematics, `ratos.py`,
  `vaoc_led.py`, `resonance_generator.py`, `z_offset_probe.py`) is being validated.
- **Native step-servos:** the fork should stop emitting `[tmc5160 ...]` for servo axes, retiring the
  old `strip_tmc.py` / watcher / systemd-override hack. Until then step 70 installs `servo_enable_delay`.
- Target host validated so far: **Pi 4, 1GB, Debian 13 (trixie)** — configurator uses the *prebuilt*
  deployment branch (never build Node on-device).
