#!/usr/bin/env bash
# esc bash - Linux Project #2 setup
# Adds some realistic log data under /var/log/escbash-app so the machine
# has meaningful disk usage to report on. Safe to re-run.
set -euo pipefail

LOG_DIR=/var/log/escbash-app
mkdir -p "$LOG_DIR"

# A small live log.
cat > "$LOG_DIR/app.log" <<'EOF'
2026-07-22 09:00:01 INFO service started
2026-07-22 09:05:14 INFO request handled path=/health status=200
EOF

# A chunky archive so folder sizes and disk usage are worth looking at.
yes "2026-07-22 09:10:00 INFO request handled path=/api status=200" \
  | head -n 80000 > "$LOG_DIR/app-archive.log"

echo "Project 2 ready. Sample logs are in $LOG_DIR."
echo "Capture the machine's health into /root/health-report.txt."
