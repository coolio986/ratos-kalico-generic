#!/usr/bin/env python3
"""Nginx auth_request helper: start RatOS configurator / crowsnest on first use,
then idle-stop them after a quiet period.

Endpoints (local only):
  GET /wake/configure  -> ensure ratos-configurator is up (port 3000)
  GET /wake/crowsnest  -> ensure crowsnest is up (port 8080)
  GET /health
"""
from __future__ import annotations

import os
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = os.environ.get("RATOS_ONDEMAND_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("RATOS_ONDEMAND_PORT", "3199"))
IDLE_SEC = int(os.environ.get("RATOS_ONDEMAND_IDLE_SEC", "900"))  # 15 min
POLL_SEC = int(os.environ.get("RATOS_ONDEMAND_POLL_SEC", "30"))
START_TIMEOUT = int(os.environ.get("RATOS_ONDEMAND_START_TIMEOUT", "120"))

SERVICES = {
    "configure": {
        "unit": "ratos-configurator.service",
        "host": "127.0.0.1",
        "port": int(os.environ.get("RATOS_CONFIGURATOR_PORT", "3000")),
    },
    "crowsnest": {
        "unit": "crowsnest.service",
        "host": "127.0.0.1",
        "port": int(os.environ.get("RATOS_CROWSNEST_PORT", "8080")),
    },
}

_lock = threading.Lock()
_last_touch: dict[str, float] = {k: 0.0 for k in SERVICES}
_starting: set[str] = set()


def _port_open(host: str, port: int, timeout: float = 0.2) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _systemctl(*args: str) -> None:
    subprocess.run(
        ["systemctl", *args],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _touch(name: str) -> None:
    _last_touch[name] = time.monotonic()


def _http_ok(url: str, timeout: float = 0.5) -> bool:
    try:
        import urllib.request

        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return 200 <= getattr(resp, "status", 200) < 300
    except Exception:
        return False


def _ready(name: str) -> bool:
    svc = SERVICES[name]
    if not _port_open(svc["host"], svc["port"]):
        return False
    # crowsnest opens :8080 before the camera pipeline is ready — wait for a real snapshot
    if name == "crowsnest":
        return _http_ok(f"http://{svc['host']}:{svc['port']}/snapshot")
    return True


def _ensure(name: str) -> tuple[int, str]:
    svc = SERVICES[name]
    host, port, unit = svc["host"], svc["port"], svc["unit"]

    if _ready(name):
        _touch(name)
        return 200, "already-up"

    with _lock:
        if name not in _starting:
            _starting.add(name)
            _systemctl("start", unit)

    deadline = time.monotonic() + START_TIMEOUT
    try:
        while time.monotonic() < deadline:
            if _ready(name):
                _touch(name)
                return 200, "started"
            time.sleep(0.4)
        return 503, f"timeout waiting for {unit} on {host}:{port}"
    finally:
        with _lock:
            _starting.discard(name)


def _idle_stop_loop() -> None:
    while True:
        time.sleep(POLL_SEC)
        now = time.monotonic()
        for name, svc in SERVICES.items():
            last = _last_touch[name]
            if last <= 0:
                continue
            if now - last < IDLE_SEC:
                continue
            if not _port_open(svc["host"], svc["port"]):
                _last_touch[name] = 0.0
                continue
            # Stop only if truly idle (no concurrent start)
            with _lock:
                if name in _starting:
                    continue
                if time.monotonic() - _last_touch[name] < IDLE_SEC:
                    continue
                _systemctl("stop", svc["unit"])
                _last_touch[name] = 0.0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # quieter journal
        if args and str(args[0]).startswith("GET /health"):
            return
        super().log_message(fmt, *args)

    def _reply(self, code: int, body: str) -> None:
        data = body.encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        except BrokenPipeError:
            # nginx/client may disconnect if auth_request is aborted
            pass

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._reply(200, "ok")
            return
        if path == "/wake/configure":
            code, msg = _ensure("configure")
            self._reply(code, msg)
            return
        if path == "/wake/crowsnest":
            code, msg = _ensure("crowsnest")
            self._reply(code, msg)
            return
        self._reply(404, "not found")


def main() -> None:
    threading.Thread(target=_idle_stop_loop, name="idle-stop", daemon=True).start()
    httpd = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
