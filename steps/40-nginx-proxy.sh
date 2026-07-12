# 40 — nginx: proxy /configure -> configurator (:3000) + on-demand wake
# (sourced by install.sh) — /configure and /webcam auto-start their backends
# via nginx auth_request → ratos-ondemand (idle-stops after RATOS_ONDEMAND_IDLE_SEC).

# --- On-demand wake daemon (always enabled; tiny loopback HTTP helper) --------
ONDEMAND_DIR="/usr/local/lib/ratos-ondemand"
ONDEMAND_PY="${ONDEMAND_DIR}/ratos-ondemand-wake.py"
ONDEMAND_UNIT="/etc/systemd/system/ratos-ondemand.service"
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

report "Installing ratos-ondemand wake helper"
sudo mkdir -p "${ONDEMAND_DIR}"
sudo install -m 0755 "${SCRIPT_ROOT}/files/ratos-ondemand-wake.py" "${ONDEMAND_PY}"
sudo install -m 0644 "${SCRIPT_ROOT}/files/ratos-ondemand.service" "${ONDEMAND_UNIT}"
sudo systemctl daemon-reload
sudo systemctl enable --now ratos-ondemand.service
ok "ratos-ondemand active on 127.0.0.1:3199"

# upstream in http context (conf.d/*.conf is included by Debian's nginx.conf)
UPSTREAM_CONF="/etc/nginx/conf.d/ratos-configurator-upstream.conf"
report "Writing nginx upstream ${UPSTREAM_CONF}"
sudo tee "${UPSTREAM_CONF}" >/dev/null <<EOF
# added by ratos-kalico-generic
upstream ratos_configurator { server 127.0.0.1:${RK_CONFIGURATOR_PORT}; }
upstream ratos_ondemand { server 127.0.0.1:3199; }
EOF

# find the mainsail server site (KIAUH default)
SITE=""
for c in /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail /etc/nginx/sites-available/mainsail.conf; do
  [[ -f "$c" ]] && { SITE="$c"; break; }
done
[[ -n "$SITE" ]] || die "mainsail nginx site not found — is Mainsail installed (KIAUH)?"
report "Patching ${SITE} for on-demand /configure + /webcam"

# Idempotent Python patcher: inject auth_request wake locations + update proxies.
sudo python3 - "${SITE}" <<'PY'
import pathlib, re, sys
site = pathlib.Path(sys.argv[1])
text = site.read_text()
backup = pathlib.Path(str(site) + ".pre-ondemand")
if not backup.exists():
    backup.write_text(text)

WAKE_SNIPPET = """
    # RatOS on-demand wake (ratos-kalico-generic) — internal auth_request targets
    location = /ratos_wake_configure {
        internal;
        proxy_pass http://ratos_ondemand/wake/configure;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_connect_timeout 2s;
        proxy_read_timeout 120s;
    }
    location = /ratos_wake_crowsnest {
        internal;
        proxy_pass http://ratos_ondemand/wake/crowsnest;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_connect_timeout 2s;
        proxy_read_timeout 120s;
    }
"""

CONFIGURE_BLOCK = """
    # RatOS Configurator (on-demand via ratos-ondemand)
    location /configure {
        auth_request /ratos_wake_configure;
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
"""

def ensure_wake(s: str) -> str:
    if "location = /ratos_wake_configure" in s:
        return s
    m = re.search(r"(^[ \t]*server_name[^\n]*\n)", s, re.M)
    if not m:
        raise SystemExit("no server_name line — cannot inject wake locations")
    return s[: m.end()] + WAKE_SNIPPET + s[m.end() :]

def replace_configure(s: str) -> str:
    pat = re.compile(
        r"[ \t]*# RatOS Configurator[^\n]*\n[ \t]*location /configure \{.*?\n[ \t]*\}\n",
        re.S,
    )
    if pat.search(s):
        return pat.sub(CONFIGURE_BLOCK.lstrip("\n"), s, count=1)
    pat2 = re.compile(r"[ \t]*location /configure \{.*?\n[ \t]*\}\n", re.S)
    if pat2.search(s):
        return pat2.sub(CONFIGURE_BLOCK.lstrip("\n"), s, count=1)
    anchor = "location = /ratos_wake_crowsnest"
    idx = s.find(anchor)
    if idx >= 0:
        end = s.find("}", idx)
        end = s.find("\n", end) + 1
        return s[:end] + CONFIGURE_BLOCK + s[end:]
    raise SystemExit("could not place /configure block")

def patch_webcam(s: str) -> str:
    def repl(m: re.Match) -> str:
        block = m.group(0)
        if "auth_request /ratos_wake_crowsnest" in block:
            return block
        return re.sub(
            r"(location /webcam/ \{\n)",
            r"\1        auth_request /ratos_wake_crowsnest;\n",
            block,
            count=1,
        )

    news, n = re.subn(
        r"[ \t]*location /webcam/ \{.*?\n[ \t]*\}\n",
        repl,
        s,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise SystemExit("could not patch location /webcam/")
    return news

text = ensure_wake(text)
text = replace_configure(text)
text = patch_webcam(text)
site.write_text(text)
print(f"patched {site}")
PY

report "Testing + reloading nginx"
sudo nginx -t || die "nginx config test failed — check ${SITE}"
sudo systemctl reload nginx
ok "nginx reloaded — /configure and /webcam auto-wake backends"
