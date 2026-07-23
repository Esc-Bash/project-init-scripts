#!/usr/bin/env bash
# esc bash - AI Project 2 setup: seed a realistic log file with an error to explain.
set -euo pipefail

cat > /root/sample.log <<'EOF'
2026-07-23T02:14:01Z INFO  api starting, pid 812
2026-07-23T02:14:02Z INFO  connected to db pool (size 10)
2026-07-23T02:15:44Z WARN  db pool at 9/10 connections in use
2026-07-23T02:15:59Z ERROR could not acquire db connection after 5000ms
2026-07-23T02:15:59Z ERROR unhandled exception in request handler
  File "/app/handlers/reports.py", line 88, in build_report
    conn = pool.acquire(timeout=5)
  File "/app/db/pool.py", line 41, in acquire
    raise TimeoutError("no free connections")
TimeoutError: no free connections
2026-07-23T02:16:00Z ERROR request failed 500 GET /v1/reports duration=5001ms
2026-07-23T02:16:20Z INFO  db pool recovered (3/10 connections in use)
EOF

echo "Setup complete: /root/sample.log created"
