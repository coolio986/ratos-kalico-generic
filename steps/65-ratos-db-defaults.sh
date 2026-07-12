# 65 — seed RatOS moonraker DB defaults needed by /configure UIs
# (sourced by install.sh). Fresh installs have wizard printer keys but not VAOC
# camera-settings; missing keys spam console errors and can leave calibration UI
# half-initialized.

MOON="http://127.0.0.1:7125"

seed_item() {
  local key="$1"
  local json_value="$2"
  local existing
  existing="$(curl -sf "${MOON}/server/database/item?namespace=RatOS&key=${key}" 2>/dev/null || true)"
  if echo "${existing}" | grep -q '"value"'; then
    ok "RatOS/${key} already present"
    return 0
  fi
  report "Seeding RatOS/${key}"
  curl -sf -X POST "${MOON}/server/database/item" \
    -H "Content-Type: application/json" \
    -d "{\"namespace\":\"RatOS\",\"key\":\"${key}\",\"value\":${json_value}}" \
    >/dev/null \
    && ok "RatOS/${key} seeded" \
    || warn "Failed to seed RatOS/${key} (moonraker up?)"
}

# VAOC visual calibration defaults (pixelPrMm tuned later in UI)
seed_item "camera-settings" '{"flipHorizontal":false,"flipVertical":false,"pixelPrMm":160,"outerNozzleDiameter":1}'
seed_item "camera-stream-settings" '{}'
