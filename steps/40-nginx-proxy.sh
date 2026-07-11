# 40 — nginx: proxy /configure -> configurator (:3000)
# (sourced by install.sh) — this is what serves /configure/analysis and
# /configure/calibration (realtime analysis + VAOC visual calibration).

# upstream in http context (conf.d/*.conf is included by Debian's nginx.conf)
UPSTREAM_CONF="/etc/nginx/conf.d/ratos-configurator-upstream.conf"
report "Writing nginx upstream ${UPSTREAM_CONF}"
sudo tee "${UPSTREAM_CONF}" >/dev/null <<EOF
# added by ratos-kalico-generic
upstream ratos_configurator { server 127.0.0.1:${RK_CONFIGURATOR_PORT}; }
EOF

# find the mainsail server site (KIAUH default)
SITE=""
for c in /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail /etc/nginx/sites-available/mainsail.conf; do
  [[ -f "$c" ]] && { SITE="$c"; break; }
done
[[ -n "$SITE" ]] || die "mainsail nginx site not found — is Mainsail installed (KIAUH)?"
report "Patching ${SITE} with /configure location"

if sudo grep -q 'location /configure' "$SITE"; then
  ok "/configure block already present"
else
  BLOCK="$(cat <<'EOF'

    # RatOS Configurator (added by ratos-kalico-generic)
    location /configure {
        proxy_pass http://ratos_configurator$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
EOF
)"
  # insert after the first server_name line in the mainsail server block
  tmp="$(mktemp)"
  awk -v block="$BLOCK" '
    !done && /server_name/ { print; print block; done=1; next }
    { print }
  ' "$SITE" | sudo tee "$tmp" >/dev/null
  if ! sudo grep -q 'location /configure' "$tmp"; then
    rm -f "$tmp"; die "failed to inject /configure block (no server_name line?) — patch ${SITE} manually"
  fi
  sudo cp "$SITE" "${SITE}.pre-ratos"
  sudo cp "$tmp" "$SITE"; rm -f "$tmp"
  ok "/configure block injected (backup: ${SITE}.pre-ratos)"
fi

report "Testing + reloading nginx"
sudo nginx -t || die "nginx config test failed — check ${SITE}"
sudo systemctl reload nginx
ok "nginx reloaded — /configure now proxied to :${RK_CONFIGURATOR_PORT}"
