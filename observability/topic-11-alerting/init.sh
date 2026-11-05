#!/usr/bin/env bash
# esc bash - Observability Fundamentals topic 11 setup: rebuilds the state at the end of topic 10 on this machine
set -euo pipefail
export OBS_TOPIC=11
curl -fsSL "${INIT_RAW:-https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main}/observability/lib.sh" | bash
