#!/usr/bin/env bash
# esc bash - Project: ship a small app with Docker and GitHub Actions.
# Seeds /root/orders-web: a stdlib Python HTTP service, a stdlib smoke test, and a git repo with two seed commits.
# Idempotent: does nothing if the repo already exists.
set -euo pipefail

if [ -d /root/orders-web/.git ]; then
  echo "Already set up: /root/orders-web"
  exit 0
fi

mkdir -p /root/orders-web/tests
cd /root/orders-web

cat > app.py <<'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"ok\n"
        else:
            body = b"esc bash orders v1\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
EOF

cat > tests/smoke_test.py <<'EOF'
"""Smoke test: the service must answer on BASE_URL (default http://127.0.0.1:8000).
Stdlib only, so it runs anywhere Python runs: this VM, a container, a CI runner."""
import os
import sys
import time
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8000")


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=3) as r:
        return r.status, r.read().decode()


def main():
    last = None
    for _ in range(20):  # the container may still be starting
        try:
            status, body = get("/")
            break
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(0.5)
    else:
        print(f"FAIL: nothing answered at {BASE}: {last}")
        return 1
    if status != 200 or "esc bash orders" not in body:
        print(f"FAIL: unexpected reply {status!r} {body!r}")
        return 1
    status, body = get("/health")
    if status != 200 or body.strip() != "ok":
        print(f"FAIL: /health returned {status!r} {body!r}")
        return 1
    print("PASS: / and /health answer as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOF

cat > requirements.txt <<'EOF'
# stdlib only - nothing to install
EOF

cat > README.md <<'EOF'
# orders-web

A tiny HTTP service. `python3 app.py` serves on :8000; `python3 tests/smoke_test.py` checks it.
EOF

cat > .gitignore <<'EOF'
__pycache__/
*.pyc
EOF

export GIT_AUTHOR_DATE="2026-02-02T09:00:00" GIT_COMMITTER_DATE="2026-02-02T09:00:00"
git init -q -b main .
git -c user.name="Priya Sharma" -c user.email="priya@example.com" add app.py requirements.txt README.md .gitignore
git -c user.name="Priya Sharma" -c user.email="priya@example.com" commit -q -m "Add the orders-web service"
git -c user.name="Priya Sharma" -c user.email="priya@example.com" add tests/smoke_test.py
git -c user.name="Priya Sharma" -c user.email="priya@example.com" commit -q -m "Add an HTTP smoke test"

echo "Setup complete: /root/orders-web (app.py, tests/smoke_test.py, two seed commits on main)"
