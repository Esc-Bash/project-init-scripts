#!/usr/bin/env bash
# esc bash - Linux Project #1 setup
# Seeds the app log directory with a live log and some old rotated logs
# for the automated-cleanup task. Safe to re-run (resets to a clean start).
set -euo pipefail

LOG_DIR=/var/log/escbash-app
mkdir -p "$LOG_DIR"

# The live log the learner must keep.
cat > "$LOG_DIR/app.log" <<'EOF'
2026-07-22 09:00:01 INFO  service started
2026-07-22 09:00:02 INFO  listening on :8080
2026-07-22 09:05:14 INFO  request handled path=/health status=200
EOF

# Old rotated logs the cleanup job should delete (names end in .old).
for d in 2026-05-01 2026-06-01 2026-07-01; do
  printf 'rotated application log from %s\n' "$d" > "$LOG_DIR/app-$d.log.old"
done
printf 'rotated access log\n' > "$LOG_DIR/access-2026-07-01.log.old"

# Start the project from a clean state (in case this is a re-run).
rm -f "$LOG_DIR/cleanup.log"

echo "Project 1 ready. Files in $LOG_DIR:"
ls -1 "$LOG_DIR"
echo
echo "The .old files are old rotated logs. Your job: clean them up on a schedule,"
echo "keep app.log, and record each run in $LOG_DIR/cleanup.log."
