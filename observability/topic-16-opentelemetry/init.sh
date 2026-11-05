#!/usr/bin/env bash
# esc bash - Observability Fundamentals topic 16 setup: rebuilds the state at the end of topic 15 on this machine
set -euo pipefail
export OBS_TOPIC=16
curl -fsSL "${INIT_RAW:-https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main}/observability/lib.sh" | bash
